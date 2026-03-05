import { Store } from "@tauri-apps/plugin-store";
import type { QueuedUpload } from "../types";
import { api } from "./api";

const QUEUE_STORE_KEY = "offline-upload-queue";

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

export async function incrementRetry(id: string): Promise<void> {
  const s = await getStore();
  const existing = (await s.get<QueuedUpload[]>(QUEUE_STORE_KEY)) || [];
  const updated = existing.map((item) =>
    item.id === id ? { ...item, retry_count: item.retry_count + 1 } : item
  );
  await s.set(QUEUE_STORE_KEY, updated);
  await s.save();
}

export async function processQueue(): Promise<void> {
  const queue = await getQueue();
  if (queue.length === 0) return;

  for (const item of queue) {
    if (item.retry_count >= 5) {
      await removeFromQueue(item.id);
      continue;
    }

    try {
      await api.uploadRecording(item.file_path, item.profile_id, item.mode);
      await removeFromQueue(item.id);
    } catch {
      await incrementRetry(item.id);
    }
  }
}
