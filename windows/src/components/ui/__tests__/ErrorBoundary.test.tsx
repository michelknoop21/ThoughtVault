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

it("retries in the existing realm while capture and a local continuation retain their context", async () => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  const { useRecordingStore } = await import("../../../stores/recordingStore");
  const previous = useRecordingStore.getState();
  const task = { task_id: "local", status: "transcribing" as const, created_at: "2026-11-10" };
  useRecordingStore.setState({ phase: "recording", selectedProfileId: "profile", selectedParticipantIds: ["person"], recordingStartedAt: 42, backgroundTasks: [task] });
  let finish!: () => void;
  const continuation = new Promise<void>(resolve => { finish = resolve; }).then(() => {
    useRecordingStore.getState().updateBackgroundTask("local", { progress: 81 });
  });
  let fail = true;
  function Child() { if (fail) throw new Error("Transient render failure"); return <span>Recovered</span>; }
  const host = document.createElement("div");
  const root = createRoot(host);
  const pathname = window.location.pathname;
  const hash = window.location.hash;
  await act(async () => root.render(<ErrorBoundary><Child /></ErrorBoundary>));
  fail = false;
  await act(async () => { host.querySelector("button")!.click(); });
  await act(async () => { finish(); await continuation; });
  expect(host.textContent).toBe("Recovered");
  expect(window.location.pathname).toBe(pathname);
  expect(window.location.hash).toBe(hash);
  expect(useRecordingStore.getState()).toMatchObject({ phase: "recording", selectedProfileId: "profile", selectedParticipantIds: ["person"], recordingStartedAt: 42, backgroundTasks: [{ ...task, progress: 81 }] });
  await act(async () => root.unmount());
  useRecordingStore.setState(previous, true);
  consoleError.mockRestore();
});
