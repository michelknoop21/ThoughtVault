import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { beginMainCloseHandler, hasMainWork, requireMainCloseHandler } from "../../services/mainWindowLifetime";
import { useRecordingStore } from "../../stores/recordingStore";
const mocks = vi.hoisted(() => ({
  create: vi.fn(), existing: vi.fn(), monitors: vi.fn(),
  created: undefined as undefined | (() => void), autoCreate: true,
}));
vi.mock("../../services/supportOwner", () => ({ requireSupportOwner: async () => () => true }));
vi.mock("@tauri-apps/api/webviewWindow", () => ({ WebviewWindow: class {
  static getByLabel = mocks.existing;
  constructor(label: string, options: unknown) { mocks.create(label, options); }
  show = async () => {}; setFocus = async () => {}; destroy = async () => {};
  once = async (event: string, callback: () => void) => {
    if (event === "tauri://created") {
      mocks.created = callback;
      if (mocks.autoCreate) queueMicrotask(callback);
    }
    return () => {};
  };
} }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => false) }));
vi.mock("@tauri-apps/api/window", () => ({ availableMonitors: mocks.monitors }));
vi.mock("@tauri-apps/api/event", () => ({ emit: vi.fn(async () => {}) }));
import { openWidgetWindow } from "../useWidgetWindow";
let registration: ReturnType<typeof beginMainCloseHandler>;
beforeEach(() => {
  vi.clearAllMocks(); mocks.autoCreate = true; mocks.created = undefined;
  mocks.existing.mockResolvedValue(null);
  mocks.monitors.mockResolvedValue([{ name: "", position: { x: 2560, y: 1440 }, size: { width: 2560, height: 1440 }, scaleFactor: 2 }]);
  useRecordingStore.setState({ phase: "idle", backgroundTasks: [] });
  registration = beginMainCloseHandler(); registration.activate();
});
afterEach(() => registration.dispose());
it("uses native widget dimensions and logical coordinates on a scaled monitor", async () => {
  await openWidgetWindow();
  expect(mocks.create).toHaveBeenCalledWith("recording-widget", expect.objectContaining({ width: 470, height: 60, x: 2070, y: 1312 }));
  expect(hasMainWork()).toBe(false);
});
it("reserves main before monitor/create awaits and releases after creation", async () => {
  let finish!: (value: never[]) => void;
  mocks.monitors.mockReturnValue(new Promise(resolve => { finish = resolve; }));
  mocks.autoCreate = false;
  const pending = openWidgetWindow();
  expect(hasMainWork()).toBe(true);
  for (let n = 0; n < 10; n++) await Promise.resolve();
  expect(hasMainWork()).toBe(true);
  finish([]);
  for (let n = 0; n < 10; n++) await Promise.resolve();
  expect(hasMainWork()).toBe(true);
  mocks.created!(); await pending;
  expect(hasMainWork()).toBe(false);
});
it("rejects stale starts and never reuses resolved readiness after remount", async () => {
  const old = await requireMainCloseHandler();
  registration.dispose(); registration = beginMainCloseHandler();
  expect(old()).toBe(false);
  const pending = openWidgetWindow();
  await Promise.resolve(); expect(mocks.create).not.toHaveBeenCalled();
  registration.activate(); await pending;
  expect(mocks.create).toHaveBeenCalledTimes(1);
});
