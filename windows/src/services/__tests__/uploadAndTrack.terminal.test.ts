import { beforeEach, expect, it, vi } from "vitest";
import { uploadAndTrack } from "../uploadAndTrack";
import { useRecordingStore } from "../../stores/recordingStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import type { Transcript, TranscriptTask } from "../../types";

const mocks = vi.hoisted(() => ({
  update: undefined as undefined | ((task: Partial<TranscriptTask>) => void),
  complete: undefined as undefined | ((status?: string) => Promise<void>),
  transcripts: vi.fn(),
}));
vi.mock("../api", () => ({ api: {
  uploadRecordingWithProgress: vi.fn(async () => ({ task_id: "uploaded" })),
  getStreamUrl: (id: string) => id, getTranscripts: mocks.transcripts,
} }));
vi.mock("../sse", () => ({ createSSEClient: () => ({ connect: (update: typeof mocks.update, _error: unknown, complete: typeof mocks.complete) => { mocks.update = update; mocks.complete = complete; } }) }));
vi.mock("../quickNotes", () => ({ linkQuickNote: vi.fn() }));
vi.mock("../obsidian", () => ({ exportToObsidian: vi.fn() }));
vi.mock("../offlineQueue", () => ({ enqueue: vi.fn() }));
beforeEach(() => {
  vi.clearAllMocks();
  useRecordingStore.setState({ backgroundTasks: [] });
  useTranscriptsStore.setState({ transcripts: [] });
});
it.each(["failed", "cancelled", "error"])("keeps an uploaded %s task without exporting a partial result", async status => {
  await uploadAndTrack("C:\\QA.wav", "standaard", "microphone");
  mocks.update!({ status: status as "failed", error_message: "Eigen QA-serverfout" });
  mocks.transcripts.mockResolvedValue([{ id: "partial", task_id: "uploaded" }]);
  await mocks.complete!(status);
  expect(mocks.transcripts).not.toHaveBeenCalled();
  expect(useTranscriptsStore.getState().transcripts).toEqual([]);
  expect(useRecordingStore.getState().backgroundTasks).toEqual([expect.objectContaining({ task_id: "uploaded", status, error_message: "Eigen QA-serverfout" })]);
});
it.each(["completed", undefined])("still fetches the matching successful result for %s", async status => {
  await uploadAndTrack("C:\\QA.wav", "standaard", "microphone");
  const result = { id: "result", task_id: "uploaded" } as Transcript;
  mocks.transcripts.mockResolvedValue([{ id: "unrelated", task_id: "other" }, result]);
  await mocks.complete!(status);
  expect(useTranscriptsStore.getState().transcripts).toEqual([result]);
  expect(useRecordingStore.getState().backgroundTasks).toEqual([]);
});
