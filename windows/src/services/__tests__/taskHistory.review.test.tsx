import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { isFinished, outcomeLabel, useTaskHistory } from "../taskHistory";
import { TaskDetailDialog } from "../../components/tasks/TaskDialogs";
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

  it("repairs nested history data so the details never throw", async () => {
    const entry = { id: "local-1", title: "Overleg", created_at: "2026-11-16T10:00:00.000Z", status: "completed", transcript_id: "local-1",
      steps: [null, { label: "Transcriberen" }, { label: "Concept", started_at: "2026-11-16T10:00:00.000Z" }] };
    localStorage.setItem("task-history", JSON.stringify({ state: { entries: [entry, { id: 5 }] }, version: 0 }));
    await useTaskHistory.persist.rehydrate();
    const [loaded, ...rest] = useTaskHistory.getState().entries;
    expect(rest).toEqual([]);
    expect(loaded.steps.map(step => step.label)).toEqual(["Concept"]);
    const root = createRoot(document.createElement("div"));
    await act(async () => { root.render(<TaskDetailDialog entry={loaded} onAction={() => {}} onOpenNotule={() => {}} onClose={() => {}} />); });
    act(() => root.unmount());
  });

  it("marks a local run cut off by a quit as interrupted and starts the next run clean", async () => {
    const stale = { id: "local-1", title: "Oude titel", title_edited: true, created_at: "2026-11-16T10:00:00.000Z", status: "transcribing",
      transcript_id: "local-1", steps: [{ label: "Transcriberen", started_at: "2026-11-16T10:00:00.000Z" }] };
    const server = { ...stale, id: "srv-1", transcript_id: "srv-1", title_edited: false };
    localStorage.setItem("task-history", JSON.stringify({ state: { entries: [stale, server] }, version: 0 }));
    await useTaskHistory.persist.rehydrate();
    const [local, remote] = useTaskHistory.getState().entries;
    expect(isFinished(local.status)).toBe(true);
    expect(outcomeLabel(local, false)).toBe("Onderbroken");
    expect(remote.status).toBe("transcribing");  // a server run may still be going

    useTaskHistory.getState().track(task({ status: "transcribing", extracted_title: "Nieuwe titel" }));
    const rerun = useTaskHistory.getState().entries[0];
    expect(rerun.title_edited).toBe(false);
    expect(rerun.title).toBe("Nieuwe titel");
    expect(rerun.steps).toHaveLength(1);
    expect(rerun.error_message).toBeUndefined();
  });
});
