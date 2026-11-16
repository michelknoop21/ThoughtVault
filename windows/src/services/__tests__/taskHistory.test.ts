import { beforeEach, describe, expect, it } from "vitest";
import { applyTaskUpdate, outcomeLabel, useTaskHistory, type TaskHistoryContext } from "../taskHistory";
import type { TranscriptTask } from "../../types";

const context: TaskHistoryContext = { transcription_engine: "Whisper · medium", notule_provider: "OpenAI", notule_model: "model-a", profile_name: "Standaard" };
const task = (patch: Partial<TranscriptTask> = {}): TranscriptTask => ({
  task_id: "local-1", status: "transcribing", progress: 10, mode: "microphone", created_at: "2026-11-16T10:00:00.000Z",
  filename: "recording_1.wav", local_audio_path: "C:/rec/recording_1.wav", profile_id: "standaard", ...patch,
});
const at = (seconds: number) => new Date(Date.parse("2026-11-16T10:00:00.000Z") + seconds * 1000).toISOString();

describe("applyTaskUpdate", () => {
  it("records steps, durations and the outcome", () => {
    let entries = applyTaskUpdate([], task(), context, at(0));
    entries = applyTaskUpdate(entries, task({ progress: 30 }), context, at(5));
    entries = applyTaskUpdate(entries, task({ status: "generating", message: "Concept schrijven" }), context, at(60));
    entries = applyTaskUpdate(entries, task({ status: "completed", extracted_title: "Weekstart" }), context, at(90));
    const [entry] = entries;
    expect(entry.steps.map(s => s.label)).toEqual(["Transcriberen", "Concept schrijven"]);
    expect(entry.steps.map(s => s.finished_at)).toEqual([at(60), at(90)]);
    expect(entry.finished_at).toBe(at(90));
    expect(entry.title).toBe("Weekstart");
    expect(entry.notule_model).toBe("model-a");
    expect(outcomeLabel(entry, false)).toBe("Voltooid");
  });

  it("returns the same list when nothing changed", () => {
    const entries = applyTaskUpdate([], task(), context, at(0));
    expect(applyTaskUpdate(entries, task({ progress: 40 }), context, at(3))).toBe(entries);
  });

  it("links a regeneration to its notule and uses a carried title", () => {
    const [entry] = applyTaskUpdate([], task({ task_id: "regen-local-9", status: "generating" }), context, at(0), "Eigen titel");
    expect(entry.transcript_id).toBe("local-9");
    expect(entry.title).toBe("Eigen titel");
    expect(entry.title_edited).toBe(true);
  });

  it("reopens a failed entry when it is retried under the same id", () => {
    let entries = applyTaskUpdate([], task({ status: "failed", error_message: "Mislukt" }), context, at(0));
    entries = applyTaskUpdate(entries, task(), context, at(10));
    expect(entries[0].finished_at).toBeUndefined();
    expect(entries[0].error_message).toBeUndefined();
    expect(outcomeLabel(entries[0], false)).toBe("Onderbroken");
  });
});

describe("useTaskHistory", () => {
  beforeEach(() => { localStorage.clear(); useTaskHistory.setState({ entries: [], pendingTitles: {} }); });

  it("persists, updates and removes entries", () => {
    useTaskHistory.getState().track(task());
    useTaskHistory.getState().update("local-1", { recording_deleted: true });
    const saved = JSON.parse(localStorage.getItem("task-history") ?? "{}");
    expect(saved.state.entries[0].recording_deleted).toBe(true);
    expect(saved.state.pendingTitles).toBeUndefined();
    useTaskHistory.getState().remove("local-1");
    expect(JSON.parse(localStorage.getItem("task-history") ?? "{}").state.entries).toEqual([]);
  });

  it("gives the next task for a recording the carried title", () => {
    useTaskHistory.getState().carryTitle("Klantgesprek", "C:/rec/recording_1.wav");
    useTaskHistory.getState().track(task({ task_id: "local-2" }));
    expect(useTaskHistory.getState().entries[0].title).toBe("Klantgesprek");
    expect(useTaskHistory.getState().pendingTitles).toEqual({});
  });
});
