import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useTaskHistory } from "../taskHistory";
import { deleteTaskRecording } from "../taskActions";
import { useRecordingStore } from "../../stores/recordingStore";
import type { TranscriptTask } from "../../types";

vi.mock("../tauriCommands", async (original) => ({ ...await original<typeof import("../tauriCommands")>(), deleteRecording: vi.fn().mockResolvedValue(undefined) }));

const task = (patch: Partial<TranscriptTask> = {}): TranscriptTask => ({
  task_id: "local-1", status: "completed", progress: 100, mode: "microphone", created_at: "2026-11-16T10:00:00.000Z",
  filename: "recording_1.wav", local_audio_path: "C:/rec/recording_1.wav", ...patch,
});

beforeEach(() => { localStorage.clear(); useTaskHistory.setState({ entries: [], pendingTitles: {} }); useRecordingStore.setState({ backgroundTasks: [] }); });
afterEach(() => vi.restoreAllMocks());

describe("task history review findings", () => {
  it("marks every entry that shares the deleted recording", async () => {
    useTaskHistory.getState().track(task());
    useTaskHistory.getState().track(task({ task_id: "local-2" }));
    await deleteTaskRecording(useTaskHistory.getState().entries.find(e => e.id === "local-1")!);
    expect(useTaskHistory.getState().entries.map(e => e.recording_deleted)).toEqual([true, true]);
  });

  it("keeps processing going when the stored history is invalid", async () => {
    localStorage.setItem("task-history", JSON.stringify({ state: { entries: null }, version: 0 }));
    await useTaskHistory.persist.rehydrate();
    expect(() => useTaskHistory.getState().track(task({ status: "transcribing" }))).not.toThrow();
    expect(useTaskHistory.getState().entries.map(e => e.id)).toEqual(["local-1"]);
    const keys = Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i) ?? "");
    const aside = keys.find(key => key.startsWith("task-history.corrupt-"));
    expect(aside && localStorage.getItem(aside)).toContain('"entries":null');
  });

  it("keeps processing going when the history cannot be written", () => {
    const setItem = vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new DOMException("full", "QuotaExceededError"); });
    expect(() => useRecordingStore.getState().addBackgroundTask(task({ status: "transcribing" }))).not.toThrow();
    expect(setItem).toHaveBeenCalled();
    expect(useTaskHistory.getState().entries.map(e => e.id)).toEqual(["local-1"]);
  });

  it("moves the upload entry to the server task id", () => {
    const store = useRecordingStore.getState();
    store.addBackgroundTask({ task_id: "pending-1", status: "uploading", progress: 0, mode: "microphone" });
    store.updateBackgroundTask("pending-1", { task_id: "srv-1", status: "uploading", progress: 10 });
    store.updateBackgroundTask("srv-1", { status: "completed", progress: 100 });
    const entries = useTaskHistory.getState().entries;
    expect(entries.map(e => e.id)).toEqual(["srv-1"]);
    expect(entries[0].transcript_id).toBe("srv-1");
    expect(entries[0].finished_at).toBeDefined();
  });
});
