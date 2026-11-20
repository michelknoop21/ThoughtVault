import { beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService } from "../llm";
import { processLocally } from "../localPipeline";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn().mockResolvedValue(() => {}) }));

beforeEach(() => {
  vi.clearAllMocks();
  useRecordingStore.setState({ backgroundTasks: [] });
  useLocalTranscriptsStore.setState({ items: [], add: vi.fn().mockResolvedValue(undefined), update: vi.fn().mockResolvedValue(undefined) });
});

it("uses the cloud API without a Whisper model when the cloud engine is selected", async () => {
  useSettingsStore.setState({ transcription_engine: "cloud_api", cloud_stt_provider: "groq", cloud_stt_model: "whisper-large-v3-turbo" });
  vi.mocked(invoke).mockImplementation(async (cmd: string) =>
    cmd === "transcribe_cloud" ? "We hebben besloten volgende week te beginnen met de planning." : { version: 1, entries: [] });
  vi.spyOn(LLMService, "generateNotulen").mockResolvedValue("<h2>Besluit</h2><p>Planning start volgende week.</p>");

  await processLocally("C:\\recording.wav", "standaard", "microphone", [], 12);

  const commands = vi.mocked(invoke).mock.calls.map(([cmd]) => cmd);
  expect(commands).not.toContain("whisper_model_status");
  expect(commands).not.toContain("transcribe_local");
  expect(invoke).toHaveBeenCalledWith("transcribe_cloud", expect.objectContaining({
    filePath: "C:\\recording.wav",
    baseUrl: "https://api.groq.com/openai",
    model: "whisper-large-v3-turbo",
    credentialKey: "groq_api_key",
  }));
});
