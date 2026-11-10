import { beforeEach, expect, it, vi } from "vitest";
import recordingPageSource from "../RecordingPage.tsx?raw";
import ts from "typescript";
import { invoke } from "@tauri-apps/api/core";
import { startRecording, stopRecording, pauseRecording, resumeRecording, shouldReportRecordingFailure, recordingErrorForUI } from "../../services/tauriCommands";
import { beginMainRecordingHandler, requireMainRecordingHandler } from "../../services/mainRecordingLifetime";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

// Exercise the actual nested handlers without replacing the studio's geometry/audio UI.
const source = ts.createSourceFile("RecordingPage.tsx", recordingPageSource, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
function handler(name: string, dependencies: Record<string, unknown>): () => Promise<void> {
  let text = "";
  function visit(node: ts.Node) {
    if (ts.isFunctionDeclaration(node) && node.name?.text === name) text = node.getText(source);
    ts.forEachChild(node, visit);
  }
  visit(source); if (!text) throw new Error(`Missing handler ${name}`);
  const js = ts.transpileModule(text, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
  return new Function(...Object.keys(dependencies), `${js}; return ${name};`)(...Object.values(dependencies));
}
function fixture() {
  const state = { pendingSeedAttendees: [], minimizeOnAutoStart: false, reset: vi.fn(), filePath: "", quickNote: "" };
  return {
    startRecording, stopRecording, pauseRecording, resumeRecording, shouldReportRecordingFailure, recordingErrorForUI, requireMainRecordingHandler,
    mode: "microphone", setMode: vi.fn(), setPhase: vi.fn(), setError: vi.fn(), reportFailure: vi.fn(),
    getRecordingsDir: vi.fn(async () => "local"), filePathRef: { current: "local.wav" }, setFilePath: vi.fn(),
    audioLevelsRef: { current: [] }, startTimer: vi.fn(), openWidgetWindow: vi.fn(async () => {}),
    useRecordingStore: { getState: () => state, setState: vi.fn() }, confirm: vi.fn(async () => true),
    closeWidgetWindow: vi.fn(async () => {}), saveQuickNote: vi.fn(), quickNote: "", calendarAccountEmail: null,
  };
}
beforeEach(() => { vi.mocked(invoke).mockReset(); });
const cases = [
  ["handleStartRecording", "Opname starten mislukt", "recording_start_failed", "start_recording"],
  ["handleStopRecording", "Opname stoppen mislukt", "recording_stop_failed", "stop_recording"],
  ["handleKeepRecording", "Opname stoppen mislukt", "recording_stop_failed", "stop_recording"],
  ["handlePause", "Pauzeren mislukt", "pause_failed", "pause_recording"],
  ["handleResume", "Hervatten mislukt", "resume_failed", "resume_recording"],
];
for (const [name, shown, code, command] of cases) {
  for (const diagnostic of ["expected", "native-owned", "unknown"]) {
    it(`${name}: ${diagnostic} preserves UI and only unknown failures report fixed metadata`, async () => {
      const registration = beginMainRecordingHandler(); registration.activate();
      try {
        const f = fixture();
        vi.mocked(invoke).mockRejectedValue(diagnostic === "unknown" ? "PRIVATE_NATIVE" : { message: "PRIVATE_NATIVE", diagnostic });
        await handler(name, f)();
        expect(invoke).toHaveBeenCalledWith(command, ...(command === "start_recording" ? [{ deviceId: null, mode: "microphone", outputDir: "local" }] : []));
        expect(f.setError).toHaveBeenCalledWith(name === "handlePause" || name === "handleResume" ? shown : "PRIVATE_NATIVE");
        if (diagnostic === "unknown") expect(f.reportFailure).toHaveBeenCalledExactlyOnceWith("opnemen", shown, code);
        else expect(f.reportFailure).not.toHaveBeenCalled();
      } finally { registration.dispose(); }
    });
  }
}
it("blocks start, including the shared calendar auto-start handler, until listener readiness", async () => {
  const registration = beginMainRecordingHandler(), f = fixture();
  vi.mocked(invoke).mockResolvedValue("local.wav");
  const pending = handler("handleStartRecording", f)();
  for (let n = 0; n < 10; n++) await Promise.resolve();
  expect(invoke).not.toHaveBeenCalled(); expect(f.getRecordingsDir).not.toHaveBeenCalled();
  registration.activate(); await pending;
  expect(invoke).toHaveBeenCalledOnce(); registration.dispose();
});
it("failed listener readiness prevents native start", async () => {
  const registration = beginMainRecordingHandler(), f = fixture();
  const pending = handler("handleStartRecording", f)(); registration.dispose(); await pending;
  expect(invoke).not.toHaveBeenCalled(); expect(f.setPhase).toHaveBeenLastCalledWith("idle");
  expect(f.reportFailure).toHaveBeenCalledExactlyOnceWith("opnemen", "Opname starten mislukt", "recording_start_failed");
});
it("directory failure remains a fixed automatic start report", async () => {
  const registration = beginMainRecordingHandler(); registration.activate();
  const f = fixture(); f.getRecordingsDir.mockRejectedValueOnce(new Error("PRIVATE_PATH"));
  await handler("handleStartRecording", f)();
  expect(invoke).not.toHaveBeenCalled();
  expect(f.reportFailure).toHaveBeenCalledExactlyOnceWith("opnemen", "Opname starten mislukt", "recording_start_failed");
  expect(f.setError).toHaveBeenCalledWith("PRIVATE_PATH"); registration.dispose();
});
it("import chooser cancellation remains silent; import rejection keeps private UI locally", async () => {
  const f = { ...fixture(), open: vi.fn(), setIsImporting: vi.fn(), importAudio: vi.fn(), settings: { processing_mode: "local" } };
  f.open.mockResolvedValueOnce(null); await handler("handleImportAudio", f)();
  expect(f.importAudio).not.toHaveBeenCalled(); expect(f.reportFailure).not.toHaveBeenCalled();
  f.open.mockResolvedValueOnce("local.wav"); f.importAudio.mockRejectedValueOnce(new Error("PRIVATE_IMPORT"));
  await handler("handleImportAudio", f)();
  expect(f.setError).toHaveBeenCalledWith("PRIVATE_IMPORT");
  expect(f.reportFailure).toHaveBeenCalledExactlyOnceWith("transcriberen", "Audio importeren mislukt", "audio_import_failed");
});
it("YouTube submit rejection reports fixed metadata; invalid/empty URL stays local", async () => {
  const f = { ...fixture(), youtubeURL: "", setYouTubeError: vi.fn(), setSubmittingYouTube: vi.fn(),
    youtubeProfileId: "p", selectedProfileId: "p", api: { transcribeYouTube: vi.fn() } };
  await handler("handleSubmitYouTube", f)(); f.youtubeURL = "invalid"; await handler("handleSubmitYouTube", f)();
  expect(f.api.transcribeYouTube).not.toHaveBeenCalled(); expect(f.reportFailure).not.toHaveBeenCalled();
  f.youtubeURL = "https://youtu.be/example"; f.api.transcribeYouTube.mockRejectedValueOnce(new Error("PRIVATE_BODY"));
  await handler("handleSubmitYouTube", f)();
  expect(f.setYouTubeError).toHaveBeenLastCalledWith("PRIVATE_BODY");
  expect(f.reportFailure).toHaveBeenCalledExactlyOnceWith("transcriberen", "YouTube transcriptie mislukt", "youtube_submit_failed");
});
