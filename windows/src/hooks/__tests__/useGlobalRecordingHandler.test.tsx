import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { useGlobalRecordingHandler } from "../useGlobalRecordingHandler";
import { useRecordingStore } from "../../stores/recordingStore";
import { useSettingsStore } from "../../stores/settingsStore";

const mocks = vi.hoisted(() => ({
  emit: vi.fn(async () => {}),
  events: new Map<string, (event: { payload: unknown }) => void>(),
  process: vi.fn(() => new Promise<void>(() => {})),
}));
vi.mock("@tauri-apps/api/event", () => ({ emit: mocks.emit, listen: vi.fn(async (name, callback) => {
  mocks.events.set(name, callback); return () => mocks.events.delete(name);
}) }));
vi.mock("../../services/localPipeline", () => ({ processLocally: mocks.process }));
vi.mock("../../services/uploadAndTrack", () => ({ uploadAndTrack: vi.fn() }));
vi.mock("../../services/participants", () => ({ resolveParticipants: () => [] }));
vi.mock("../useWidgetWindow", () => ({ closeWidgetWindow: vi.fn(async () => {}) }));
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
