import { expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { ErrorBoundary } from "../ErrorBoundary";
import { reportFailure } from "../../../services/crashReporter";
vi.mock("../../../services/crashReporter", () => ({ reportFailure: vi.fn(async () => {}) }));
it("reports a render failure without uploading the error or component stack", async () => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  function PrivateComponentName(): never { throw new Error("PRIVATE_RENDER_BODY"); }
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<ErrorBoundary><PrivateComponentName /></ErrorBoundary>));
  expect(reportFailure).toHaveBeenCalledExactlyOnceWith("crash", "Er is iets misgegaan", "react_render_failed");
  expect(host.textContent).toContain("PRIVATE_RENDER_BODY");
  await act(async () => root.unmount());
  consoleError.mockRestore();
});
