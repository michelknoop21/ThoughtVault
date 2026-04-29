import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// In-memory store mock that mimics the @tauri-apps/plugin-store API surface used by offlineQueue.
const memory = new Map<string, unknown>();
vi.mock("@tauri-apps/plugin-store", () => ({
  Store: {
    load: async () => ({
      get: async (key: string) => memory.get(key),
      set: async (key: string, value: unknown) => { memory.set(key, value); },
      save: async () => {},
    }),
  },
}));

vi.mock("@tauri-apps/plugin-fs", () => ({
  exists: vi.fn(async () => true),
}));

const uploadMock = vi.fn();
vi.mock("../api", () => ({
  api: {
    uploadRecordingWithProgress: (...args: unknown[]) => uploadMock(...args),
  },
}));

const queueStoreState = {
  setItems: vi.fn(),
  startItem: vi.fn(),
  finishItem: vi.fn(),
  updateProgress: vi.fn(),
  addPermanentlyFailed: vi.fn(),
  reset: vi.fn(),
};
vi.mock("../../stores/uploadQueueStore", () => ({
  useUploadQueueStore: { getState: () => queueStoreState },
}));

import { enqueue, getQueue, processQueue } from "../offlineQueue";

beforeEach(() => {
  memory.clear();
  uploadMock.mockReset();
  Object.values(queueStoreState).forEach((fn) => fn.mockReset?.());
});

afterEach(() => {
  vi.useRealTimers();
});

describe("offlineQueue retry policy", () => {
  it("422 client errors are NOT retried — go straight to permanent-failed", async () => {
    await enqueue({
      file_path: "/tmp/x.wav",
      profile_id: "zakelijk",
      mode: "microphone",
    });
    uploadMock.mockRejectedValueOnce(new Error("Upload mislukt (HTTP 422)"));

    await processQueue();

    expect(queueStoreState.addPermanentlyFailed).toHaveBeenCalledOnce();
    expect(await getQueue()).toHaveLength(0);
  });

  it("401 IS retried (transient auth) — stays in queue with backoff", async () => {
    await enqueue({
      file_path: "/tmp/x.wav",
      profile_id: "zakelijk",
      mode: "microphone",
    });
    uploadMock.mockRejectedValueOnce(new Error("Upload mislukt (HTTP 401)"));

    await processQueue();

    expect(queueStoreState.addPermanentlyFailed).not.toHaveBeenCalled();
    const q = await getQueue();
    expect(q).toHaveLength(1);
    expect(q[0].retry_count).toBe(1);
    expect(q[0].next_retry_at).toBeDefined();
  });

  it("network errors are retried with exponential backoff", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-28T10:00:00Z"));

    await enqueue({
      file_path: "/tmp/x.wav",
      profile_id: "zakelijk",
      mode: "microphone",
    });
    uploadMock.mockRejectedValue(new Error("netwerkfout"));

    await processQueue();
    let q = await getQueue();
    expect(q[0].retry_count).toBe(1);
    // 30s backoff after first failure
    expect(new Date(q[0].next_retry_at!).getTime() - Date.now()).toBe(30_000);

    // Second processQueue call before backoff window expires — should NOT attempt upload
    uploadMock.mockClear();
    await processQueue();
    expect(uploadMock).not.toHaveBeenCalled();

    // Advance time past backoff
    vi.setSystemTime(new Date("2026-04-28T10:00:31Z"));
    await processQueue();
    expect(uploadMock).toHaveBeenCalledOnce();
    q = await getQueue();
    expect(q[0].retry_count).toBe(2);
    // 2m backoff after second failure
    expect(new Date(q[0].next_retry_at!).getTime() - Date.now()).toBe(2 * 60_000);
  });

  it("after MAX_RETRIES (5) the item is dropped and surfaced as permanent failure", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-28T10:00:00Z"));

    await enqueue({
      file_path: "/tmp/x.wav",
      profile_id: "zakelijk",
      mode: "microphone",
      file_name: "x.wav",
    });
    uploadMock.mockRejectedValue(new Error("Server unavailable"));

    // 5 attempts, advancing time past each backoff window
    for (let i = 0; i < 5; i++) {
      await processQueue();
      vi.setSystemTime(new Date(Date.now() + 2 * 60 * 60 * 1000)); // jump 2h forward
    }

    // 6th processQueue call: should mark as permanently failed
    await processQueue();
    expect(queueStoreState.addPermanentlyFailed).toHaveBeenCalledWith({
      id: expect.any(String),
      fileName: "x.wav",
    });
    expect(await getQueue()).toHaveLength(0);
  });

  it("legacy items without next_retry_at are processed immediately", async () => {
    // Inject a legacy item directly (simulates upgrade from old version)
    memory.set("offline-upload-queue", [{
      id: "legacy-1",
      file_path: "/tmp/legacy.wav",
      profile_id: "zakelijk",
      mode: "microphone",
      created_at: new Date().toISOString(),
      retry_count: 2, // already had retries on the old code
    }]);
    uploadMock.mockResolvedValueOnce({ task_id: "ok" });

    await processQueue();

    expect(uploadMock).toHaveBeenCalledOnce();
    expect(await getQueue()).toHaveLength(0);
  });
});
