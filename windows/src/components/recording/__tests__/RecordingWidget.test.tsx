import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { RecordingWidget } from "../RecordingWidget";

const mocks = vi.hoisted(() => ({
  close: vi.fn(async () => {}),
  events: new Map<string, (event: { payload: unknown }) => void>(),
}));
vi.mock("@tauri-apps/api/event", () => ({ emit: vi.fn(async () => {}), listen: vi.fn(async (name, callback) => {
  mocks.events.set(name, callback); return () => mocks.events.delete(name);
}) }));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => ({ close: mocks.close }) }));
vi.mock("../../../services/tauriCommands", () => ({ stopRecording: vi.fn(), pauseRecording: vi.fn(), resumeRecording: vi.fn() }));
vi.mock("../../../hooks/useAudioLevel", () => ({ useAudioLevelsRef: () => ({ current: [] }), useAudioBandsRef: () => ({ current: [] }) }));
vi.mock("../WaveformVisualizer", () => ({ WaveformVisualizer: () => null }));
afterEach(() => { mocks.close.mockClear(); mocks.events.clear(); });

it("closes a late widget that missed stop, but keeps an active or paused recording", async () => {
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<RecordingWidget />));
  const sync = mocks.events.get("widget-sync-timer")!;
  for (const phase of ["recording", "paused", "stopping"]) {
    await act(async () => sync({ payload: { phase, recordingStartedAt: Date.now(), pausedAt: null, pausedDuration: 0 } }));
    expect(mocks.close).not.toHaveBeenCalled();
  }
  await act(async () => sync({ payload: { phase: "idle", recordingStartedAt: null, pausedAt: null, pausedDuration: 0 } }));
  expect(mocks.close).toHaveBeenCalledOnce();
  await act(async () => root.unmount());
});
