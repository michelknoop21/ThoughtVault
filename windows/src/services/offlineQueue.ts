import { Store } from "@tauri-apps/plugin-store";
import { exists } from "@tauri-apps/plugin-fs";
import type { QueuedUpload } from "../types";
import { api } from "./api";
import { useUploadQueueStore } from "../stores/uploadQueueStore";

const QUEUE_STORE_KEY = "offline-upload-queue";
const MAX_RETRIES = 50;

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

export async function incrementRetry(id: string, errorMessage?: string): Promise<void> {
  const s = await getStore();
  const existing = (await s.get<QueuedUpload[]>(QUEUE_STORE_KEY)) || [];
  const updated = existing.map((item) =>
    item.id === id ? { ...item, retry_count: item.retry_count + 1, last_error: errorMessage } : item
  );
  await s.set(QUEUE_STORE_KEY, updated);
  await s.save();
}

export async function processQueue(): Promise<void> {
  const queue = await getQueue();
  if (queue.length === 0) return;

  const queueStore = useUploadQueueStore.getState();
  queueStore.setItems(queue);

  for (const item of queue) {
    // Remove if max retries exceeded
    if (item.retry_count >= MAX_RETRIES) {
      await removeFromQueue(item.id);
      continue;
    }

    // Remove if file no longer exists on disk
    try {
      const fileExists = await exists(item.file_path);
      if (!fileExists) {
        await removeFromQueue(item.id);
        continue;
      }
    } catch {
      // Can't check — try upload anyway
    }

    queueStore.startItem(item);

    try {
      await api.uploadRecordingWithProgress(
        item.file_path,
        item.profile_id,
        item.mode,
        (fraction) => queueStore.updateProgress(fraction),
      );
      queueStore.finishItem();
      await removeFromQueue(item.id);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Upload mislukt";
      queueStore.finishItem();
      await incrementRetry(item.id, msg);
    }
  }

  // Update items after processing
  const remaining = await getQueue();
  queueStore.setItems(remaining);
  if (remaining.length === 0) {
    queueStore.reset();
  }
}
