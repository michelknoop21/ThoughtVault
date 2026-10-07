import { Store } from "@tauri-apps/plugin-store";
import { exists } from "@tauri-apps/plugin-fs";
import type { QueuedUpload } from "../types";
import { api } from "./api";
import { linkQuickNote } from "./quickNotes";
import { useUploadQueueStore } from "../stores/uploadQueueStore";

const QUEUE_STORE_KEY = "offline-upload-queue";
const MAX_RETRIES = 5;

// Backoff after a failed attempt. Index = retry_count of the just-failed attempt.
// retry_count=0 → first attempt failed → wait BACKOFF_MS[0] before next try.
const BACKOFF_MS = [
  30_000,        // 30s
  2 * 60_000,    // 2m
  10 * 60_000,   // 10m
  30 * 60_000,   // 30m
  60 * 60_000,   // 1h
];

// 4xx that *can* succeed on retry (transient auth, request timeout, rate limit).
// Anything else 4xx (422/400/404/...) means the request itself is malformed —
// retrying won't help, surface immediately instead of grinding through the queue.
function isRetryable4xx(msg: string): boolean {
  return /HTTP\s+(401|408|429)\b/.test(msg);
}

function isClientError4xx(msg: string): boolean {
  return /HTTP\s+4\d\d\b/.test(msg);
}

let store: Store | null = null;

async function getStore(): Promise<Store> {
  if (!store) {
    store = await Store.load("offline-queue.json");
  }
  return store;
}

export async function enqueue(item: Omit<QueuedUpload, "id" | "created_at" | "retry_count">): Promise<void> {
  const s = await getStore();
  const existing = (await s.get<QueuedUpload[]>(QUEUE_STORE_KEY)) || [];
  // Don't enqueue if the same file is already in the queue
  if (existing.some((e) => e.file_path === item.file_path)) return;
  const newItem: QueuedUpload = {
    ...item,
    id: crypto.randomUUID(),
    created_at: new Date().toISOString(),
    retry_count: 0,
  };
  await s.set(QUEUE_STORE_KEY, [...existing, newItem]);
  await s.save();
}

export async function getQueue(): Promise<QueuedUpload[]> {
  const s = await getStore();
  return (await s.get<QueuedUpload[]>(QUEUE_STORE_KEY)) || [];
}

export async function removeFromQueue(id: string): Promise<void> {
  const s = await getStore();
  const existing = (await s.get<QueuedUpload[]>(QUEUE_STORE_KEY)) || [];
  await s.set(QUEUE_STORE_KEY, existing.filter((item) => item.id !== id));
  await s.save();
}

export async function clearQueue(): Promise<void> {
  const s = await getStore();
  await s.set(QUEUE_STORE_KEY, []);
  await s.save();
}

async function recordFailure(id: string, errorMessage: string): Promise<void> {
  const s = await getStore();
  const existing = (await s.get<QueuedUpload[]>(QUEUE_STORE_KEY)) || [];
  const updated = existing.map((item) => {
    if (item.id !== id) return item;
    const failedAttempts = item.retry_count;
    const backoffMs = BACKOFF_MS[Math.min(failedAttempts, BACKOFF_MS.length - 1)];
    return {
      ...item,
      retry_count: failedAttempts + 1,
      last_error: errorMessage,
      next_retry_at: new Date(Date.now() + backoffMs).toISOString(),
    };
  });
  await s.set(QUEUE_STORE_KEY, updated);
  await s.save();
}

export async function processQueue(): Promise<void> {
  const queue = await getQueue();
  if (queue.length === 0) return;

  const queueStore = useUploadQueueStore.getState();
  queueStore.setItems(queue);

  const now = Date.now();

  for (const item of queue) {
    // Drop items that exhausted their retries — surface to user.
    if (item.retry_count >= MAX_RETRIES) {
      const fileName = item.file_name || item.file_path.split(/[\\/]/).pop() || "onbekend bestand";
      queueStore.addPermanentlyFailed({ id: item.id, fileName });
      await removeFromQueue(item.id);
      continue;
    }

    // Drop items whose source file has disappeared — nothing to upload.
    try {
      const fileExists = await exists(item.file_path);
      if (!fileExists) {
        await removeFromQueue(item.id);
        continue;
      }
    } catch {
      // Can't check — try upload anyway
    }

    // Honour backoff window — skip until next_retry_at has passed.
    if (item.next_retry_at && new Date(item.next_retry_at).getTime() > now) {
      continue;
    }

    queueStore.startItem(item);

    try {
      const { task_id } = await api.uploadRecordingWithProgress(
        item.file_path,
        item.profile_id,
        item.mode,
        (fraction) => queueStore.updateProgress(fraction),
      );
      linkQuickNote(task_id, item.file_path);
      queueStore.finishItem();
      await removeFromQueue(item.id);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Upload mislukt";
      queueStore.finishItem();

      // Non-retryable client error (422/400/etc.): retrying won't help. Surface immediately.
      if (isClientError4xx(msg) && !isRetryable4xx(msg)) {
        const fileName = item.file_name || item.file_path.split(/[\\/]/).pop() || "onbekend bestand";
        queueStore.addPermanentlyFailed({ id: item.id, fileName });
        await removeFromQueue(item.id);
        continue;
      }

      await recordFailure(item.id, msg);
    }
  }

  // Update items after processing
  const remaining = await getQueue();
  queueStore.setItems(remaining);
  if (remaining.length === 0) {
    queueStore.reset();
  }
}
