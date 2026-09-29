import { beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
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
