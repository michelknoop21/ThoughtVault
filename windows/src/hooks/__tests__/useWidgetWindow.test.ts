import { expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ create: vi.fn(), existing: vi.fn().mockResolvedValue(null) }));
vi.mock("@tauri-apps/api/webviewWindow", () => ({ WebviewWindow: class {
  static getByLabel = mocks.existing;
  constructor(label: string, options: unknown) { mocks.create(label, options); }
  once = vi.fn();
} }));
vi.mock("@tauri-apps/api/window", () => ({ availableMonitors: vi.fn().mockResolvedValue([
  { name: "", position: { x: 2560, y: 1440 }, size: { width: 2560, height: 1440 }, scaleFactor: 2 },
]) }));
vi.mock("@tauri-apps/api/event", () => ({ emit: vi.fn() }));
import { openWidgetWindow } from "../useWidgetWindow";
it("uses native widget dimensions and logical coordinates on a scaled monitor", async () => {
  await openWidgetWindow();
  expect(mocks.create).toHaveBeenCalledWith("recording-widget", expect.objectContaining({
    width: 470, height: 60, minHeight: 60, maxHeight: 60, x: 2070, y: 1312,
  }));
});
