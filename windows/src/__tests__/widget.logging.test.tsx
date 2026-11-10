import { expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ console: vi.fn(), clicks: vi.fn(), render: vi.fn() }));
vi.mock("react-dom/client", () => ({ default: { createRoot: vi.fn(() => ({ render: mocks.render })) } }));
vi.mock("../services/appLog", () => ({ installConsoleForwarding: mocks.console, installClickPath: mocks.clicks }));
vi.mock("../components/recording/RecordingWidget", () => ({ RecordingWidget: () => null }));
vi.mock("../App", () => { throw new Error("The widget must initialize without importing App"); });

it("installs diagnostic hooks in the separate widget context before rendering", async () => {
  document.body.innerHTML = '<div id="widget-root"></div>';
  await import("../widget");
  expect(mocks.console).toHaveBeenCalledTimes(1);
  expect(mocks.clicks).toHaveBeenCalledTimes(1);
  expect(mocks.render).toHaveBeenCalledTimes(1);
  expect(mocks.console.mock.invocationCallOrder[0]).toBeLessThan(mocks.render.mock.invocationCallOrder[0]);
  expect(mocks.clicks.mock.invocationCallOrder[0]).toBeLessThan(mocks.render.mock.invocationCallOrder[0]);
});
