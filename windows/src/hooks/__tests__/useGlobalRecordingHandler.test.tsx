import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { useGlobalRecordingHandler } from "../useGlobalRecordingHandler";
import { useRecordingStore } from "../../stores/recordingStore";
import { useSettingsStore } from "../../stores/settingsStore";

const mocks = vi.hoisted(() => ({
  events: new Map<string, (event: { payload: unknown }) => void>(),
  process: vi.fn(() => new Promise<void>(() => {})),
}));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async (name, callback) => {
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
