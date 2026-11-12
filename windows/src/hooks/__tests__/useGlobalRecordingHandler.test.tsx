import { afterEach, expect, it, vi } from "vitest";
import { StrictMode, act } from "react";
import { createRoot } from "react-dom/client";
import { requireMainRecordingHandler } from "../../services/mainRecordingLifetime";
import { listen } from "@tauri-apps/api/event";
import { useGlobalRecordingHandler } from "../useGlobalRecordingHandler";
import { useRecordingStore } from "../../stores/recordingStore";
import { reportFailure } from "../../services/crashReporter";
import { useToast } from "../../components/ui/InfoBar";
import { useSettingsStore } from "../../stores/settingsStore";

const mocks = vi.hoisted(() => ({
  emit: vi.fn(async () => {}),
  events: new Map<string, (event: { payload: unknown }) => void>(),
  process: vi.fn(() => new Promise<void>(() => {})),
}));
vi.mock("@tauri-apps/api/event", () => ({ emit: mocks.emit, listen: vi.fn(async (name, callback) => {
  mocks.events.set(name, callback); return () => { if (mocks.events.get(name) === callback) mocks.events.delete(name); };
}) }));
vi.mock("../../services/localPipeline", () => ({ processLocally: mocks.process }));
vi.mock("../../services/uploadAndTrack", () => ({ uploadAndTrack: vi.fn() }));
vi.mock("../../services/participants", () => ({ resolveParticipants: () => [] }));
vi.mock("../useWidgetWindow", () => ({ closeWidgetWindow: vi.fn(async () => {}) }));
vi.mock("../../services/crashReporter", async original => ({
  ...(await original<object>()), reportFailure: vi.fn(async () => {}), markStage: vi.fn(),
}));
function Handler() { useGlobalRecordingHandler(); return null; }
afterEach(() => { useRecordingStore.getState().reset(); mocks.process.mockClear(); });
it("processes a second recording while the first job is pending and ignores stale stop events", async () => {
  useSettingsStore.setState({ processing_mode: "local" });
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Handler />));
  const stop = mocks.events.get("recording-stopped")!;
  useRecordingStore.setState({ phase: "stopping", filePath: "first.wav", selectedProfileId: "first" });
  await act(async () => stop({ payload: { file_path: "first.wav", duration_seconds: 10 } }));
  useRecordingStore.setState({ phase: "recording", filePath: "second.wav", selectedProfileId: "second" });
  await act(async () => stop({ payload: { file_path: "first.wav", duration_seconds: 10 } }));
  expect(useRecordingStore.getState().phase).toBe("recording");
  await act(async () => stop({ payload: { file_path: "second.wav", duration_seconds: 20 } }));
  expect(mocks.process).toHaveBeenCalledTimes(2);
  expect(mocks.process).toHaveBeenLastCalledWith("second.wav", "second", "combined", [], 20);
  expect(useRecordingStore.getState().phase).toBe("idle");
  await act(async () => root.unmount());
});

it("synchronizes widget pause and resume while the recording page is unmounted", async () => {
  vi.spyOn(Date, "now").mockReturnValue(10000);
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Handler />));
  useRecordingStore.setState({ phase: "recording", recordingStartedAt: 5000, filePath: "test.wav" });
  await act(async () => mocks.events.get("recording-paused")!({ payload: null }));
  expect(useRecordingStore.getState()).toMatchObject({ phase: "paused", pausedAt: 10000 });
  expect(mocks.emit).toHaveBeenLastCalledWith("widget-sync-timer", expect.objectContaining({ phase: "paused", pausedAt: 10000 }));
  vi.mocked(Date.now).mockReturnValue(14000);
  await act(async () => mocks.events.get("recording-resumed")!({ payload: null }));
  expect(useRecordingStore.getState()).toMatchObject({ phase: "recording", pausedAt: null, pausedDuration: 4000 });
  await act(async () => mocks.events.get("recording-stopping")!({ payload: null }));
  expect(useRecordingStore.getState()).toMatchObject({ phase: "stopping", pausedAt: 14000 });
  await act(async () => root.unmount());
  vi.restoreAllMocks();
});
it("keeps an unprocessed recording busy without sending it to a provider", async () => {
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Handler />));
  useRecordingStore.setState({ phase: "stopping", filePath: "saved.wav", processOnStop: false });
  await act(async () => mocks.events.get("recording-stopped")!({ payload: { file_path: "saved.wav", duration_seconds: 10 } }));
  expect(mocks.process).not.toHaveBeenCalled();
  expect(useRecordingStore.getState().phase).toBe("stopping");
  await act(async () => root.unmount());
});

it("keeps raw native error UI without uploading its private content", async () => {
  vi.mocked(reportFailure).mockClear();
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<Handler />));
  await act(async () => mocks.events.get("recording-error")!({ payload: "PRIVATE_NATIVE_BODY" }));
  expect(reportFailure).not.toHaveBeenCalled();
  expect(useToast.getState().toasts.at(-1)?.message).toBe("PRIVATE_NATIVE_BODY");
  await act(async () => root.unmount());
});

it("accepts only five static native codes, each with fixed metadata", async () => {
  vi.mocked(reportFailure).mockClear();
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Handler />));
  await requireMainRecordingHandler();
  const receive = mocks.events.get("recording-diagnostic")!;
  for (const payload of [null, {}, { code: "start_failed", message: "PRIVATE" }, "PRIVATE", "toString", "__proto__", 1]) receive({ payload });
  expect(reportFailure).not.toHaveBeenCalled();
  const cases = [
    ["start_failed", "Opname starten mislukt", "recording_start_failed"],
    ["capture_failed", "Opnemen mislukt", "native_recording_failed"],
    ["stop_failed", "Opname stoppen mislukt", "recording_stop_failed"],
    ["pause_failed", "Pauzeren mislukt", "pause_failed"],
    ["resume_failed", "Hervatten mislukt", "resume_failed"],
  ];
  for (const [payload, shown, code] of cases) {
    receive({ payload }); expect(reportFailure).toHaveBeenLastCalledWith("opnemen", shown, code);
  }
  receive({ payload: "pause_failed" }); // independent native queue errors remain independent
  expect(reportFailure).toHaveBeenCalledTimes(6);
  await act(async () => root.unmount());
});
it("blocks recording readiness until delayed listen resolves and unlistens after late cleanup", async () => {
  const original = vi.mocked(listen).getMockImplementation()!;
  let finish!: (stop: () => void) => void;
  const stop = vi.fn();
  vi.mocked(listen).mockImplementation((name, callback) => name === "recording-diagnostic"
    ? new Promise(resolve => { finish = resolve; }) : original(name, callback));
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Handler />));
  let ready = false;
  const pending = requireMainRecordingHandler().then(() => { ready = true; });
  const rejection = expect(pending).rejects.toThrow();
  await Promise.resolve(); expect(ready).toBe(false);
  await act(async () => root.unmount());
  finish(stop); await rejection;
  for (let n = 0; n < 10; n++) await Promise.resolve();
  expect(stop).toHaveBeenCalledOnce();
  vi.mocked(listen).mockImplementation(original);
});
it("a rejected listener blocks readiness and cleans every successful registration", async () => {
  const original = vi.mocked(listen).getMockImplementation()!;
  vi.mocked(listen).mockImplementation((name, callback) => name === "recording-diagnostic"
    ? Promise.reject(new Error("listen failed")) : original(name, callback));
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Handler />));
  await expect(requireMainRecordingHandler()).rejects.toThrow();
  expect(mocks.events.size).toBe(0);
  await act(async () => root.unmount());
  vi.mocked(listen).mockImplementation(original);
});
it("StrictMode late old listener cannot activate the replacement generation", async () => {
  const original = vi.mocked(listen).getMockImplementation()!;
  let finishOld!: (stop: () => void) => void, finishNew!: (stop: () => void) => void;
  const oldStop = vi.fn(), newStop = vi.fn();
  let diagnostics = 0;
  vi.mocked(listen).mockImplementation((name, callback) => name === "recording-diagnostic"
    ? new Promise(resolve => { if (++diagnostics === 1) finishOld = resolve; else finishNew = resolve; })
    : original(name, callback));
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<StrictMode><Handler /></StrictMode>));
  let ready = false; const pending = requireMainRecordingHandler().then(() => { ready = true; });
  finishOld(oldStop); for (let n = 0; n < 10; n++) await Promise.resolve();
  expect(oldStop).toHaveBeenCalledOnce(); expect(ready).toBe(false);
  finishNew(newStop); await pending; expect(ready).toBe(true);
  await act(async () => root.unmount()); expect(newStop).toHaveBeenCalledOnce();
  vi.mocked(listen).mockImplementation(original);
});
