import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { StrictMode, act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
import { reportFailure } from "../../services/crashReporter";
import { reportPreviousCrash, useSupportLifecycle } from "../useSupportLifecycle";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../services/crashReporter", () => ({ reportFailure: vi.fn(async () => {}) }));
const mocks = vi.hoisted(() => ({ flush: vi.fn(async () => {}), refresh: vi.fn(async () => {}) }));
vi.mock("../../stores/supportStore", () => ({ useSupportStore: { getState: () => ({ flushQueue: mocks.flush, refreshUnread: mocks.refresh }) } }));
function Lifecycle() { useSupportLifecycle(); return null; }
let root: Root | undefined;
async function mount(strict = false) {
  root = createRoot(document.createElement("div"));
  await act(async () => root!.render(strict ? <StrictMode><Lifecycle /></StrictMode> : <Lifecycle />));
}
async function unmount() { await act(async () => root?.unmount()); root = undefined; }
beforeEach(() => {
  vi.resetAllMocks();
  vi.useFakeTimers();
  Object.assign(window, { __TAURI_INTERNALS__: {} });
  vi.mocked(invoke).mockResolvedValue({ crashed: false, stage: null });
  mocks.flush.mockResolvedValue(); mocks.refresh.mockResolvedValue();
  vi.mocked(reportFailure).mockResolvedValue();
});
afterEach(async () => {
  await unmount();
  delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
  vi.useRealTimers();
});

it.each(["opnemen", "transcriberen", "notule"])("reports a previous %s failure with fixed metadata", async stage => {
  vi.mocked(invoke).mockResolvedValueOnce({ crashed: true, stage });
  await reportPreviousCrash();
  expect(invoke).toHaveBeenCalledExactlyOnceWith("session_begin");
  expect(reportFailure).toHaveBeenCalledExactlyOnceWith(stage, `ThoughtVault stopte onverwacht tijdens ${stage}.`, `gestopt tijdens ${stage}`);
});
it.each([null, undefined, "private meeting body", "__proto__", {}, 1])("uses a bare crash for an untrusted stage %j", async stage => {
  vi.mocked(invoke).mockResolvedValueOnce({ crashed: true, stage });
  await reportPreviousCrash();
  expect(reportFailure).toHaveBeenCalledExactlyOnceWith("crash", "ThoughtVault stopte onverwacht.", "gestopt zonder af te sluiten");
});
it("does not report after a clean exit", async () => {
  await reportPreviousCrash(); expect(reportFailure).not.toHaveBeenCalled();
});
it("flushes after crash reporting settles, refreshes at startup/focus/15 minutes, and retries online", async () => {
  let finish!: (value: unknown) => void;
  vi.mocked(invoke).mockReturnValueOnce(new Promise(resolve => { finish = resolve; }));
  await mount();
  expect(mocks.flush).not.toHaveBeenCalled(); expect(mocks.refresh).toHaveBeenCalledTimes(1);
  await act(async () => finish({ crashed: false, stage: null }));
  expect(mocks.flush).toHaveBeenCalledTimes(1);
  await act(async () => { window.dispatchEvent(new Event("online")); });
  expect(mocks.flush).toHaveBeenCalledTimes(2);
  await act(async () => { window.dispatchEvent(new Event("focus")); });
  await act(async () => vi.advanceTimersByTime(15 * 60 * 1000));
  expect(mocks.refresh).toHaveBeenCalledTimes(3);
  await unmount();
  await act(async () => {
    window.dispatchEvent(new Event("online")); window.dispatchEvent(new Event("focus"));
    vi.advanceTimersByTime(30 * 60 * 1000);
  });
  expect(mocks.flush).toHaveBeenCalledTimes(2); expect(mocks.refresh).toHaveBeenCalledTimes(3);
  expect(vi.getTimerCount()).toBe(0);
});
it.each(["session", "report"])("flushes even when deferred %s startup fails without rejecting", async kind => {
  let fail!: (error: Error) => void;
  if (kind === "session") vi.mocked(invoke).mockReturnValueOnce(new Promise((_resolve, reject) => { fail = reject; }));
  else {
    vi.mocked(invoke).mockResolvedValueOnce({ crashed: true, stage: "notule" });
    vi.mocked(reportFailure).mockImplementationOnce(() => new Promise((_resolve, reject) => { fail = reject; }));
  }
  await mount(); expect(mocks.flush).not.toHaveBeenCalled();
  await act(async () => fail(new Error("diagnostic unavailable")));
  expect(mocks.flush).toHaveBeenCalledTimes(1);
});
it("contains refresh and queue rejections at startup and later events", async () => {
  mocks.flush.mockRejectedValue(new Error("queue unavailable"));
  mocks.refresh.mockRejectedValue(new Error("relay unavailable"));
  await mount();
  await act(async () => {
    window.dispatchEvent(new Event("online")); window.dispatchEvent(new Event("focus"));
    vi.advanceTimersByTime(15 * 60 * 1000);
  });
  expect(mocks.flush).toHaveBeenCalledTimes(2); expect(mocks.refresh).toHaveBeenCalledTimes(3);
});
it("does not flush a disposed mount when startup settles late", async () => {
  let finish!: (value: unknown) => void;
  vi.mocked(invoke).mockReturnValueOnce(new Promise(resolve => { finish = resolve; }));
  await mount(); await unmount();
  await act(async () => finish({ crashed: true, stage: "notule" }));
  expect(reportFailure).toHaveBeenCalledTimes(1);
  expect(mocks.flush).not.toHaveBeenCalled(); expect(vi.getTimerCount()).toBe(0);
});
it("keeps a single active listener/timer generation through StrictMode and remount", async () => {
  // Model the native once-per-process session_begin contract, rather than JS deduplication.
  vi.mocked(invoke).mockResolvedValueOnce({ crashed: true, stage: "opnemen" });
  await mount(true);
  expect(reportFailure).toHaveBeenCalledTimes(1); expect(vi.getTimerCount()).toBe(1);
  const before = mocks.flush.mock.calls.length;
  await act(async () => { window.dispatchEvent(new Event("online")); });
  expect(mocks.flush).toHaveBeenCalledTimes(before + 1);
  await unmount(); await mount();
  expect(reportFailure).toHaveBeenCalledTimes(1); expect(vi.getTimerCount()).toBe(1);
});
it("does nothing in browser preview", async () => {
  delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
  await mount();
  window.dispatchEvent(new Event("online")); window.dispatchEvent(new Event("focus"));
  expect(invoke).not.toHaveBeenCalled(); expect(mocks.flush).not.toHaveBeenCalled();
  expect(mocks.refresh).not.toHaveBeenCalled(); expect(vi.getTimerCount()).toBe(0);
});
