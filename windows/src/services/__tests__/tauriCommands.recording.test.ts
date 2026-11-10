import { beforeEach, describe, expect, it, vi } from "vitest";
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
import { startRecording, stopRecording, pauseRecording, resumeRecording, shouldReportRecordingFailure, recordingErrorForUI } from "../tauriCommands";

const commands = [() => startRecording(null, "microphone", "local"), stopRecording, pauseRecording, resumeRecording];
beforeEach(() => invoke.mockReset());

describe("recording-specific native rejection contract", () => {
  for (const command of commands) {
    for (const diagnostic of ["expected", "native-owned"]) {
      it(`${command.name || "start"} preserves legacy UI and accepts ${diagnostic}`, async () => {
        invoke.mockRejectedValueOnce({ message: "original native message", diagnostic });
        const error = await command().catch((error: unknown) => error);
        expect(shouldReportRecordingFailure(error)).toBe(false);
        const uiError = recordingErrorForUI(error);
        expect(String(uiError)).toBe("original native message");
        // Pause/resume historically receive a String and keep their fallback text.
        expect(uiError instanceof Error ? uiError.message : "existing fallback").toBe("existing fallback");
      });
    }
  }
  it("retains unknown IPC failures and malformed classifications for caller reporting", async () => {
    const inherited = Object.create({ message: "native", diagnostic: "expected" });
    for (const error of ["permission denied", new Error("IPC failed"), null, { message: "x", diagnostic: "reported" }, { message: 1, diagnostic: "expected" }, { diagnostic: "native-owned" }, { message: "x", diagnostic: "expected", extra: true }, inherited, Object.assign(new Error("IPC"), { diagnostic: "expected" })]) {
      invoke.mockRejectedValueOnce(error);
      const rejection = await stopRecording().catch((error: unknown) => error);
      expect(shouldReportRecordingFailure(rejection)).toBe(true);
      expect(recordingErrorForUI(rejection)).toBe(error);
    }
  });
  it("normalizes no unrelated invoke API", async () => {
    const { getAudioDevices } = await import("../tauriCommands");
    const error = { message: "other command", diagnostic: "expected" };
    invoke.mockRejectedValueOnce(error);
    const rejection = await getAudioDevices().catch((error: unknown) => error);
    expect(rejection).toBe(error);
    expect(shouldReportRecordingFailure(rejection)).toBe(true);
  });
  it("keeps successive independent pause failures observable", async () => {
    for (let attempt = 0; attempt < 2; attempt++) {
      invoke.mockRejectedValueOnce("unknown queue/IPC rejection");
      expect(shouldReportRecordingFailure(await pauseRecording().catch((error: unknown) => error))).toBe(true);
    }
  });
});
