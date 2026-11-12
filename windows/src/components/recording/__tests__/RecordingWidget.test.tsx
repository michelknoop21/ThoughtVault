import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { handoffWidgetFailure } from "../../../services/widgetSupport";
import { RecordingWidget } from "../RecordingWidget";

const mocks = vi.hoisted(() => ({
  close: vi.fn(async () => {}),
  events: new Map<string, (event: { payload: unknown }) => void>(),
}));
vi.mock("@tauri-apps/api/event", () => ({ emit: vi.fn(async () => {}), listen: vi.fn(async (name, callback) => {
  mocks.events.set(name, callback); return () => mocks.events.delete(name);
}) }));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => ({ close: mocks.close }) }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
import { invoke } from "@tauri-apps/api/core";
vi.mock("../../../hooks/useAudioLevel", () => ({ useAudioLevelsRef: () => ({ current: [] }), useAudioBandsRef: () => ({ current: [] }) }));
vi.mock("../WaveformVisualizer", () => ({ WaveformVisualizer: () => null }));
vi.mock("../../../services/widgetSupport", () => ({ handoffWidgetFailure: vi.fn(async () => true) }));
vi.mock("../../../services/crashReporter", () => { throw new Error("Widget imported main reporter"); });
vi.mock("../../../stores/supportStore", () => { throw new Error("Widget imported C6 owner"); });
afterEach(() => { mocks.close.mockClear(); mocks.events.clear(); vi.clearAllMocks(); });

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

it.each(["recording", "paused"])("hands off fixed metadata after %s command failure", async phase => {
  vi.mocked(invoke).mockRejectedValue(new Error("PRIVATE_PAUSE_BODY"));
  vi.mocked(invoke).mockRejectedValue(new Error("PRIVATE_RESUME_BODY"));
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<RecordingWidget />));
  await act(async () => mocks.events.get("widget-sync-timer")!({ payload: { phase, recordingStartedAt: Date.now(), pausedAt: null, pausedDuration: 0 } }));
  await act(async () => host.querySelector<HTMLButtonElement>(".widget-btn")!.click());
  expect(handoffWidgetFailure).toHaveBeenCalledExactlyOnceWith(phase === "paused" ? "resume_failed" : "pause_failed");
  await act(async () => root.unmount());
});
it("hands off unknown stop invoke failure with fixed metadata", async () => {
  vi.mocked(invoke).mockRejectedValue(new Error("PRIVATE_STOP_BODY"));
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<RecordingWidget />));
  await act(async () => host.querySelector<HTMLButtonElement>(".widget-btn-stop")!.click());
  expect(handoffWidgetFailure).toHaveBeenCalledExactlyOnceWith("stop_failed");
  expect(host.textContent).toContain("REC");
  await act(async () => root.unmount());
});
it("marks failed handoff as unconfirmed without retrying with a new incident", async () => {
  vi.mocked(invoke).mockRejectedValue(new Error("PRIVATE_BODY"));
  vi.mocked(handoffWidgetFailure).mockResolvedValueOnce(false);
  const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<RecordingWidget />));
  await act(async () => host.querySelector<HTMLButtonElement>(".widget-btn")!.click());
  expect(handoffWidgetFailure).toHaveBeenCalledExactlyOnceWith("pause_failed");
  expect(warn).toHaveBeenCalledWith("[Widget] Support delivery not confirmed");
  await act(async () => root.unmount());
  warn.mockRestore();
});

for (const diagnostic of ["expected", "native-owned"]) {
  it.each(["stop", "pause", "resume"])(`suppresses ${diagnostic} %s catch handoff`, async operation => {
    vi.mocked(invoke).mockRejectedValue({ message: "PRIVATE_NATIVE", diagnostic });
    const host = document.createElement("div"), root = createRoot(host);
    await act(async () => root.render(<RecordingWidget />));
    if (operation === "resume") await act(async () => mocks.events.get("widget-sync-timer")!({ payload: {
      phase: "paused", recordingStartedAt: Date.now(), pausedAt: Date.now(), pausedDuration: 0,
    } }));
    await act(async () => host.querySelector<HTMLButtonElement>(operation === "stop" ? ".widget-btn-stop" : ".widget-btn")!.click());
    expect(invoke).toHaveBeenCalledWith(operation + "_recording");
    expect(handoffWidgetFailure).not.toHaveBeenCalled();
    await act(async () => root.unmount());
  });
}
