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
