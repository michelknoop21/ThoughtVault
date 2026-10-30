import { beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import { usePersonalCorrectionsStore } from "../../stores/personalCorrectionsStore";
import { LLMService } from "../llm";
import { processLocally } from "../localPipeline";
import type { Transcript } from "../../types";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn().mockResolvedValue(() => {}) }));

const partial: Transcript = {
  id: "local-partial", title: "Transcriptie", raw_transcription: "We hebben besloten volgende week te beginnen met de planning.",
  notule_html: "", has_transcription: true, has_notes: false, duration_seconds: 12, tags: [],
  created_at: "2026-09-29T10:00:00Z", updated_at: "2026-09-29T10:00:00Z",
};

beforeEach(() => {
  vi.clearAllMocks();
  useRecordingStore.setState({ backgroundTasks: [] });
  useTranscriptsStore.setState({ transcripts: [partial] });
});

it("finishes the existing partial document on retry without retranscribing", async () => {
  const add = vi.fn();
  const update = vi.fn().mockResolvedValue(undefined);
  useLocalTranscriptsStore.setState({ items: [partial], add, update });
  vi.spyOn(LLMService, "generateNotulen").mockResolvedValue("<h2>Besluit</h2><p>Volgende week begint de planning.</p>");

  await processLocally("C:\\recording.wav", "standaard", "microphone", [], 12, partial.id);

  expect(invoke).not.toHaveBeenCalled();
  expect(add).not.toHaveBeenCalled();
  expect(update).toHaveBeenCalledWith(partial.id, expect.objectContaining({ has_notes: true }));
  expect(useRecordingStore.getState().backgroundTasks).toHaveLength(1);
  expect(useRecordingStore.getState().backgroundTasks[0].task_id).toBe(partial.id);
});

it("keeps simultaneous transcription progress attached to its own task", async () => {
  const progressListeners: Array<(event: { payload: { request_id: string; progress: number } }) => void> = [];
  vi.mocked(listen).mockImplementation(async (_name, callback) => {
    progressListeners.push(callback as typeof progressListeners[number]);
    return () => {};
  });
  const finishTranscription = new Map<string, (text: string) => void>();
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "whisper_model_status") return { exists: true } as never;
    if (command === "transcribe_local") {
      return new Promise<string>((resolve) => finishTranscription.set((args as { requestId: string }).requestId, resolve)) as never;
    }
    throw new Error(`Unexpected command: ${command}`);
  });
  vi.spyOn(usePersonalCorrectionsStore.getState(), "hydrate").mockResolvedValue(undefined);
  useLocalTranscriptsStore.setState({ items: [], add: vi.fn(), update: vi.fn() });
  vi.spyOn(LLMService, "generateNotulen").mockResolvedValue("<h2>Besluit</h2><p>De planning begint maandag.</p>");

  const first = processLocally("C:\\first.wav", "standaard", "microphone", [], 12, "local-first");
  const second = processLocally("C:\\second.wav", "standaard", "microphone", [], 12, "local-second");
  await vi.waitFor(() => expect(finishTranscription.size).toBe(2));
  progressListeners.forEach((listener) => listener({ payload: { request_id: "local-first", progress: 80 } }));
  expect(useRecordingStore.getState().backgroundTasks.find((task) => task.task_id === "local-first")?.progress).toBe(42);
  expect(useRecordingStore.getState().backgroundTasks.find((task) => task.task_id === "local-second")?.progress).toBe(10);
  for (const finish of finishTranscription.values()) finish("De planning begint maandag om tien uur.");
  await Promise.all([first, second]);
});

it("shows native transcription errors without discarding the original message", async () => {
  vi.mocked(invoke).mockImplementation(async (command) => {
    if (command === "whisper_model_status") return { exists: true } as never;
    throw "Segment lezen mislukt: invalid UTF-8";
  });
  vi.spyOn(usePersonalCorrectionsStore.getState(), "hydrate").mockResolvedValue(undefined);
  const add = vi.fn();
  useLocalTranscriptsStore.setState({ items: [], add, update: vi.fn() });
  await processLocally("C:\\recording.wav", "standaard", "combined", [], 12, "local-failed");
  expect(useRecordingStore.getState().backgroundTasks[0]).toMatchObject({
    status: "failed", error_message: "Segment lezen mislukt: invalid UTF-8",
  });
  expect(add).not.toHaveBeenCalled();
});

it("persists imported audio duration and keeps it on the task", async () => {
  vi.mocked(invoke).mockImplementation(async command => {
    if (command === "audio_duration") return 600 as never;
    if (command === "whisper_model_status") return { exists: true } as never;
    if (command === "transcribe_local") return "Alex controleert maandag de eigen QA opname." as never;
    throw new Error(`Unexpected command: ${command}`);
  });
  vi.spyOn(usePersonalCorrectionsStore.getState(), "hydrate").mockResolvedValue(undefined);
  const add = vi.fn();
  useLocalTranscriptsStore.setState({ items: [], add, update: vi.fn() });
  vi.spyOn(LLMService, "generateNotulen").mockResolvedValue("<h2>Besluit</h2><p>Alex controleert maandag de opname.</p>");
  await processLocally("C:\\import.wav", "standaard", "microphone", [], 0, "local-import");
  expect(add).toHaveBeenCalledWith(expect.objectContaining({ duration_seconds: 600 }));
  expect(useRecordingStore.getState().backgroundTasks[0].duration_seconds).toBe(600);
});

it("keeps a duration read failure visible without saving an incomplete import", async () => {
  vi.mocked(invoke).mockRejectedValue("Kan de audioduur niet lezen");
  const add = vi.fn();
  useLocalTranscriptsStore.setState({ items: [], add, update: vi.fn() });
  await processLocally("C:\\missing.wav", "standaard", "microphone", [], 0, "local-missing");
  expect(invoke).toHaveBeenCalledWith("audio_duration", { filePath: "C:\\missing.wav" });
  expect(useRecordingStore.getState().backgroundTasks[0]).toMatchObject({
    status: "failed", error_message: "Kan de audioduur niet lezen",
  });
  expect(add).not.toHaveBeenCalled();
});

it("keeps a rejected draft separate, preserves transcript and never completes or autoexports", async () => {
  const { NotuleReviewError } = await import("../notuleAudit");
  const { useSettingsStore } = await import("../../stores/settingsStore");
  useSettingsStore.setState({ obsidian_enabled: true });
  const update = vi.fn().mockResolvedValue(undefined);
  useLocalTranscriptsStore.setState({ items: [partial], add: vi.fn(), update });
  vi.spyOn(LLMService, "generateNotulen").mockRejectedValue(new NotuleReviewError("Actie ontbreekt", "<p>Ongecontroleerd concept</p>"));
  await processLocally("C:\\recording.wav", "standaard", "microphone", [], 12, partial.id);
  expect(update).toHaveBeenCalledExactlyOnceWith(partial.id, expect.objectContaining({
    notule_draft_html: "<p>Ongecontroleerd concept</p>", notule_review_reason: "Actie ontbreekt",
  }));
  const patch = update.mock.calls[0][1];
  expect(patch).not.toHaveProperty("notule_html");
  expect(patch).not.toHaveProperty("raw_transcription");
  expect(patch).not.toHaveProperty("has_notes");
  expect(invoke).not.toHaveBeenCalled();
  expect(useRecordingStore.getState().backgroundTasks[0]).toMatchObject({ status: "failed", error_message: expect.stringContaining("apart bewaard") });
});

it("reports a failed draft write without claiming the concept was saved", async () => {
  const { NotuleReviewError } = await import("../notuleAudit");
  useLocalTranscriptsStore.setState({ items: [partial], add: vi.fn(), update: vi.fn().mockRejectedValue(new Error("disk full")) });
  vi.spyOn(LLMService, "generateNotulen").mockRejectedValue(new NotuleReviewError("Controle onzeker", "<p>Concept</p>"));
  await processLocally("C:\\recording.wav", "standaard", "microphone", [], 12, partial.id);
  const task = useRecordingStore.getState().backgroundTasks[0];
  expect(task.status).toBe("failed");
  expect(task.error_message).toContain("kon niet worden bewaard");
  expect(task.error_message).not.toContain("apart bewaard");
  expect(useTranscriptsStore.getState().transcripts[0]).toEqual(partial);
});

it("clears stale review fields only when a new validated replacement is saved", async () => {
  const update = vi.fn().mockResolvedValue(undefined);
  useLocalTranscriptsStore.setState({ items: [{ ...partial, notule_draft_html: "old draft", notule_review_reason: "old reason" }], add: vi.fn(), update });
  vi.spyOn(LLMService, "generateNotulen").mockResolvedValue("<p>De planning begint maandag.</p>");
  const { useSettingsStore } = await import("../../stores/settingsStore");
  useSettingsStore.setState({ obsidian_enabled: false });
  await processLocally("C:\\recording.wav", "standaard", "microphone", [], 12, partial.id);
  expect(update).toHaveBeenCalledWith(partial.id, expect.objectContaining({ has_notes: true, notule_draft_html: "", notule_review_reason: "" }));
  expect(useRecordingStore.getState().backgroundTasks[0].status).toBe("completed");
});
