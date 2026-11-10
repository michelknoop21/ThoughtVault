import { act } from "react";
import { Update } from "@tauri-apps/plugin-updater";
import { createRoot } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { CHECK_UPDATES_EVENT, UPDATE_CHECK_INTERVAL_MS, useUpdateCheck } from "../useUpdateCheck";
import { useSettingsStore } from "../../stores/settingsStore";
import { useRecordingStore } from "../../stores/recordingStore";
const { checkMock } = vi.hoisted(() => ({ checkMock: vi.fn(async (): Promise<Update | null> => null) }));
let closeHandler: (e: unknown) => Promise<void> | void = () => {};
const fakeWindow = {
  onCloseRequested: vi.fn(async (cb: (e: unknown) => Promise<void> | void) => { closeHandler = cb; return () => {}; }),
  destroy: vi.fn(async () => {}),
  hide: vi.fn(async () => {}),
};
vi.mock("@tauri-apps/api/webviewWindow", () => ({ WebviewWindow: { getByLabel: vi.fn(async () => null) } }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => false) }));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => fakeWindow }));
vi.mock("@tauri-apps/api/app", () => ({getVersion: async () => "1.0.260", getName: async () => "ThoughtVault"}));
vi.mock("@tauri-apps/plugin-updater", async (importOriginal) => ({
  ...await importOriginal<typeof import("@tauri-apps/plugin-updater")>(), check: checkMock,
}));
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });
it("uses the existing private installer URL without doubling its origin", async () => {
  Object.assign(window, {__TAURI_INTERNALS__:{}});
  useSettingsStore.setState({check_for_updates:true});
  const url = "https://thoughtvault.yinga.ai/d-05921304471ce66e62d0a2b7f324c2354dfb1d895d23a895bba7f86110e2472e/ThoughtVault_1.0.262_x64.msi";
  const fetch = vi.fn(async () => ({ok:true,json:async () => ({windows_x64:{version:"1.0.262",url}})}));
  vi.stubGlobal("fetch", fetch);
  const host = document.createElement("div");
  const root = createRoot(host);
  function Probe() { const result = useUpdateCheck(); return <span>{result.downloadUrl}</span>; }
  await act(async () => { root.render(<Probe/>); });
  expect(fetch.mock.calls).toHaveLength(1);
  expect(host.textContent).toBe(url);
  await act(async () => { root.unmount(); });
});

function fakeUpdate(version: string) {
  return Object.assign(new Update({ rid: 1, version, currentVersion: "1.0.260", rawJson: {} }), {
    download: vi.fn(async () => {}),
    install: vi.fn(async () => {}),
    downloadAndInstall: vi.fn(async () => {}),
    close: vi.fn(async () => {}),
  });
}
let lastResult: ReturnType<typeof useUpdateCheck>;
const mounted: ReturnType<typeof createRoot>[] = [];
async function render() {
  Object.assign(window, {__TAURI_INTERNALS__:{}});
  vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })));
  const root = createRoot(document.createElement("div"));
  mounted.push(root);
  function Probe() { lastResult = useUpdateCheck(); return null; }
  await act(async () => { root.render(<Probe/>); });
  return root;
}
beforeEach(() => {
  vi.restoreAllMocks();
  fakeWindow.destroy.mockReset().mockResolvedValue();
  fakeWindow.hide.mockReset().mockResolvedValue();
  closeHandler = () => {};
  useSettingsStore.setState({ check_for_updates: true });
  useRecordingStore.setState({ phase: "idle", backgroundTasks: [] });
  checkMock.mockReset();
  checkMock.mockResolvedValue(null);
});
afterEach(async () => {
  for (const r of mounted.splice(0)) { try { await act(async () => { r.unmount(); }); } catch { /* already unmounted */ } }
});

it("downloads a found update without asking", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  expect(u.download).toHaveBeenCalledTimes(1);
  expect(u.install).not.toHaveBeenCalled();
});
it("does not check or download when updates are switched off", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  await render();
  expect(checkMock).not.toHaveBeenCalled();
});
it("checks again every six hours", async () => {
  vi.useFakeTimers(); checkMock.mockResolvedValue(null);
  await render();
  await act(async () => { await vi.advanceTimersByTimeAsync(UPDATE_CHECK_INTERVAL_MS - 1000); });
  expect(checkMock).toHaveBeenCalledTimes(1);
  await act(async () => { await vi.advanceTimersByTimeAsync(1000); });
  expect(checkMock).toHaveBeenCalledTimes(2);
});
it("checks when tv-check-updates is dispatched", async () => {
  checkMock.mockResolvedValue(null);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(checkMock).toHaveBeenCalledTimes(2);
});
it("checks on tv-check-updates even when updates are switched off, without downloading", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(checkMock).toHaveBeenCalledTimes(1);
  expect(u.download).not.toHaveBeenCalled();
});
it("does not download the same version twice", async () => {
  vi.useFakeTimers();
  const first = fakeUpdate("1.0.400"), second = fakeUpdate("1.0.400");
  checkMock.mockResolvedValueOnce(first).mockResolvedValueOnce(second);
  await render();
  await act(async () => { await vi.advanceTimersByTimeAsync(UPDATE_CHECK_INTERVAL_MS); });
  expect(first.download).toHaveBeenCalledTimes(1);
  expect(second.download).not.toHaveBeenCalled();
  expect(second.close).toHaveBeenCalled();
});
it("retries a failed download on the next check", async () => {
  vi.spyOn(console, "warn").mockImplementation(() => {});
  vi.useFakeTimers();
  const bad = fakeUpdate("1.0.400"); bad.download.mockRejectedValue(new Error("offline"));
  const good = fakeUpdate("1.0.400");
  checkMock.mockResolvedValueOnce(bad).mockResolvedValueOnce(good);
  await render();
  await act(async () => { await vi.advanceTimersByTimeAsync(UPDATE_CHECK_INTERVAL_MS); });
  expect(bad.download).toHaveBeenCalledTimes(1);
  expect(good.download).toHaveBeenCalledTimes(1);
});
it("stops the interval and the event listener on unmount", async () => {
  vi.useFakeTimers(); checkMock.mockResolvedValue(null);
  const root = await render(); await act(async () => { root.unmount(); });
  await act(async () => { await vi.advanceTimersByTimeAsync(UPDATE_CHECK_INTERVAL_MS); window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(checkMock).toHaveBeenCalledTimes(1);
});

async function close() {
  const ev = { preventDefault: vi.fn() };
  await act(async () => { await closeHandler(ev); });
  return ev;
}
it("installs on close when the download is done and nothing is busy", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render(); const ev = await close();
  expect(ev.preventDefault).toHaveBeenCalled();
  expect(u.install).toHaveBeenCalledTimes(1);
});
it("does not install on close while recording", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render(); useRecordingStore.setState({ phase: "recording" });
  const ev = await close();
  expect(ev.preventDefault).toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("does not install on close while a task is processing", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  useRecordingStore.setState({ backgroundTasks: [{ task_id: "t1", status: "transcribing", progress: 40, mode: "combined", created_at: "2026-11-10T10:00:00Z" }] });
  expect((await close()).preventDefault).toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("does not install on close before the download is finished", async () => {
  const u = fakeUpdate("1.0.400"); u.download.mockReturnValue(new Promise(() => {}));
  checkMock.mockResolvedValue(u);
  await render();
  expect((await close()).preventDefault).toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("closes normally when the download failed", async () => {
  vi.spyOn(console, "warn").mockImplementation(() => {});
  const u = fakeUpdate("1.0.400"); u.download.mockRejectedValue(new Error("offline"));
  checkMock.mockResolvedValue(u);
  await render();
  expect((await close()).preventDefault).toHaveBeenCalled();
});
it("does not install on close when updates are switched off", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render(); await act(async () => { useSettingsStore.setState({ check_for_updates: false }); });
  expect((await close()).preventDefault).toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("closes the window when install fails", async () => {
  vi.spyOn(console, "warn").mockImplementation(() => {});
  const u = fakeUpdate("1.0.400"); u.install.mockRejectedValue(new Error("bad signature"));
  checkMock.mockResolvedValue(u);
  await render(); await close();
  expect(fakeWindow.destroy).toHaveBeenCalled();
});
it("prevents repeated close requests from starting another install", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  let finish: () => void = () => {};
  u.install.mockReturnValue(new Promise<void>((r) => { finish = r; }));
  await render();
  const firstEvent = { preventDefault: vi.fn() };
  const first = closeHandler(firstEvent);
  const repeatedEvent = { preventDefault: vi.fn() };
  const repeated = closeHandler(repeatedEvent);
  expect(repeatedEvent.preventDefault).toHaveBeenCalled();
  await act(async () => {});
  expect(u.install).toHaveBeenCalledTimes(1);
  finish(); await Promise.all([first, repeated]);
});
it("prevents default without acting on close events after unmount", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  const root = await render();
  await act(async () => { root.unmount(); });
  expect((await close()).preventDefault).toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("removes a close listener that finishes registering after unmount", async () => {
  const unlisten = vi.fn();
  let registered: () => void = () => {};
  fakeWindow.onCloseRequested.mockImplementationOnce(async (cb) => {
    closeHandler = cb;
    await new Promise<void>((r) => { registered = r; });
    return unlisten;
  });
  const root = await render();
  await act(async () => { root.unmount(); registered(); });
  expect(unlisten).toHaveBeenCalledTimes(1);
});
it("prevents SDK destruction from a disposed, still-registering close callback", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  const unlisten = vi.fn();
  let registered: () => void = () => {};
  fakeWindow.onCloseRequested.mockImplementationOnce(async (cb) => {
    closeHandler = cb;
    await new Promise<void>((resolve) => { registered = resolve; });
    return unlisten;
  });
  const root = await render();
  await act(async () => { root.unmount(); });
  expect(unlisten).not.toHaveBeenCalled();
  await act(async () => {
    let prevented = false;
    const event = { preventDefault: () => { prevented = true; } };
    // The SDK awaits the callback, then explicitly destroys unless it prevented the event.
    await closeHandler(event);
    if (!prevented) await fakeWindow.destroy();
    expect(prevented).toBe(true);
  });
  expect(fakeWindow.destroy).not.toHaveBeenCalled();
  expect(fakeWindow.hide).not.toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
  await act(async () => { registered(); });
  expect(unlisten).toHaveBeenCalledTimes(1);
});
it("handles a failed fallback window destruction", async () => {
  vi.spyOn(console, "warn").mockImplementation(() => {});
  const u = fakeUpdate("1.0.400"); u.install.mockRejectedValue(new Error("bad signature"));
  fakeWindow.destroy.mockRejectedValue(new Error("already closed"));
  checkMock.mockResolvedValue(u);
  await render();
  await expect(close()).resolves.toBeDefined();
});
it("replaces a held, downloaded update by a newer version", async () => {
  vi.useFakeTimers();
  const v1 = fakeUpdate("1.0.400"), v2 = fakeUpdate("1.0.401");
  let release: () => void = () => {};
  v2.download.mockReturnValue(new Promise<void>((r) => { release = r; }));
  checkMock.mockResolvedValueOnce(v1).mockResolvedValueOnce(v2);
  await render();
  expect(lastResult.downloaded).toBe(true);
  await act(async () => { await vi.advanceTimersByTimeAsync(UPDATE_CHECK_INTERVAL_MS); });
  expect(v1.close).toHaveBeenCalled();
  expect(v2.download).toHaveBeenCalledTimes(1);
  expect(lastResult.downloaded).toBe(false);
  await act(async () => { release(); });
  expect(lastResult.downloaded).toBe(true);
});
it("exposes downloaded only after the download has finished", async () => {
  const u = fakeUpdate("1.0.400");
  let release: () => void = () => {};
  u.download.mockReturnValue(new Promise<void>((r) => { release = r; }));
  checkMock.mockResolvedValue(u);
  await render();
  expect(lastResult.downloaded).toBe(false);
  await act(async () => { release(); });
  expect(lastResult.downloaded).toBe(true);
});
it("starts the download when the toggle is switched on while an update is held", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(u.download).not.toHaveBeenCalled();
  await act(async () => { useSettingsStore.setState({ check_for_updates: true }); });
  expect(u.download).toHaveBeenCalledTimes(1);
});

it("installNow waits for the running download and shares installation completion across clicks", async () => {
  const u = fakeUpdate("1.0.400");
  let finish!: () => void, finishInstall!: () => void;
  u.download.mockReturnValue(new Promise<void>((resolve) => { finish = resolve; }));
  u.install.mockReturnValue(new Promise<void>((resolve) => { finishInstall = resolve; }));
  checkMock.mockResolvedValue(u);
  await render();
  const firstFinished = vi.fn(), secondFinished = vi.fn();
  const first = lastResult.installNow().then(firstFinished), second = lastResult.installNow().then(secondFinished);
  expect(u.install).not.toHaveBeenCalled();
  await act(async () => { finish(); });
  expect(firstFinished).not.toHaveBeenCalled();
  expect(secondFinished).not.toHaveBeenCalled();
  expect(u.download).toHaveBeenCalledTimes(1);
  expect(u.install).toHaveBeenCalledTimes(1);
  await act(async () => { finishInstall(); await Promise.all([first, second]); });
  expect(firstFinished).toHaveBeenCalledTimes(1);
  expect(secondFinished).toHaveBeenCalledTimes(1);
});

it("installNow downloads and installs an explicitly checked update with the toggle off", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  await act(async () => { await lastResult.installNow(); });
  expect(u.download).toHaveBeenCalledTimes(1);
  expect(u.install).toHaveBeenCalledTimes(1);
});
it("installNow does nothing without a native update", async () => {
  await render();
  await expect(lastResult.installNow()).resolves.toBeUndefined();
});
it("installNow does not download or install while busy", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  useRecordingStore.setState({ phase: "recording" });
  await lastResult.installNow();
  expect(u.download).not.toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("installNow rechecks busy after waiting for the download", async () => {
  const u = fakeUpdate("1.0.400");
  let finish!: () => void;
  u.download.mockReturnValue(new Promise<void>((resolve) => { finish = resolve; }));
  checkMock.mockResolvedValue(u);
  await render();
  const pending = lastResult.installNow();
  useRecordingStore.setState({ backgroundTasks: [{ task_id: "t1", status: "transcribing", progress: 40, mode: "combined", created_at: "2026-11-10T10:00:00Z" }] });
  await act(async () => { finish(); await pending; });
  expect(u.install).not.toHaveBeenCalled();
});
it("installNow does not install an update replaced during its download", async () => {
  const first = fakeUpdate("1.0.400"), second = fakeUpdate("1.0.401");
  let finish!: () => void;
  first.download.mockReturnValue(new Promise<void>((resolve) => { finish = resolve; }));
  checkMock.mockResolvedValueOnce(first).mockResolvedValueOnce(second);
  await render();
  const pending = lastResult.installNow();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  await act(async () => { finish(); await pending; });
  expect(first.install).not.toHaveBeenCalled();
  expect(second.install).not.toHaveBeenCalled();
});
it("installNow surfaces a failed background download instead of installing", async () => {
  vi.spyOn(console, "warn").mockImplementation(() => {});
  const u = fakeUpdate("1.0.400");
  let fail!: (reason: Error) => void;
  u.download.mockReturnValue(new Promise<void>((_resolve, reject) => { fail = reject; }));
  checkMock.mockResolvedValue(u);
  await render();
  const pending = lastResult.installNow();
  const rejected = expect(pending).rejects.toThrow("Update download failed");
  await act(async () => {}); // Join the background download after native lifetime checks.
  await act(async () => { fail(new Error("offline")); await rejected; });
  expect(u.install).not.toHaveBeenCalled();
});
it("installNow surfaces manual download failure and allows retry", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  const u = fakeUpdate("1.0.400");
  u.download.mockRejectedValueOnce(new Error("offline")); checkMock.mockResolvedValue(u);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  await expect(lastResult.installNow()).rejects.toThrow("offline");
  expect(u.install).not.toHaveBeenCalled();
  await act(async () => { await lastResult.installNow(); });
  expect(u.download).toHaveBeenCalledTimes(2);
  expect(u.install).toHaveBeenCalledTimes(1);
});
it("prevents closing and replacement while a manual installation is running", async () => {
  const u = fakeUpdate("1.0.400"), replacement = fakeUpdate("1.0.401");
  let finish!: () => void;
  u.install.mockReturnValue(new Promise<void>((resolve) => { finish = resolve; }));
  checkMock.mockResolvedValueOnce(u).mockResolvedValueOnce(replacement);
  await render();
  let pending!: Promise<void>;
  await act(async () => { pending = lastResult.installNow(); });
  const closeEvent = { preventDefault: vi.fn() };
  const closing = closeHandler(closeEvent);
  expect(closeEvent.preventDefault).toHaveBeenCalled();
  const secondFinished = vi.fn();
  const second = lastResult.installNow().then(secondFinished);
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(secondFinished).not.toHaveBeenCalled();
  expect(u.install).toHaveBeenCalledTimes(1);
  expect(u.close).not.toHaveBeenCalled();
  expect(replacement.close).toHaveBeenCalledTimes(1);
  expect(replacement.download).not.toHaveBeenCalled();
  expect(lastResult.nativeUpdate).toBe(u);
  await act(async () => { finish(); await Promise.all([pending, closing, second]); });
  expect(secondFinished).toHaveBeenCalledTimes(1);
});
it("installNow cannot race an installation started by closing", async () => {
  const u = fakeUpdate("1.0.400");
  let finish!: () => void;
  u.install.mockReturnValue(new Promise<void>((resolve) => { finish = resolve; }));
  checkMock.mockResolvedValue(u);
  await render();
  const pending = closeHandler({ preventDefault: vi.fn() });
  const manualFinished = vi.fn();
  const manual = lastResult.installNow().then(manualFinished);
  await act(async () => {});
  expect(manualFinished).not.toHaveBeenCalled();
  expect(u.install).toHaveBeenCalledTimes(1);
  finish(); await Promise.all([pending, manual]);
  expect(manualFinished).toHaveBeenCalledTimes(1);
});
it("installNow does not install after unmount while a download was pending", async () => {
  const u = fakeUpdate("1.0.400");
  let finish!: () => void;
  u.download.mockReturnValue(new Promise<void>((resolve) => { finish = resolve; }));
  checkMock.mockResolvedValue(u);
  const root = await render();
  const pending = lastResult.installNow();
  await act(async () => { root.unmount(); finish(); await pending; });
  expect(u.install).not.toHaveBeenCalled();
});
it("installNow reports install failure and releases the guard for retry", async () => {
  const u = fakeUpdate("1.0.400");
  u.install.mockRejectedValueOnce(new Error("bad signature")); checkMock.mockResolvedValue(u);
  await render();
  await expect(lastResult.installNow()).rejects.toThrow("bad signature");
  await lastResult.installNow();
  expect(u.install).toHaveBeenCalledTimes(2);
  expect(u.download).toHaveBeenCalledTimes(1);
});

it("closes the window when a shared manual installation fails and still rejects to the banner", async () => {
  vi.spyOn(console, "warn").mockImplementation(() => {});
  const u = fakeUpdate("1.0.400");
  let fail!: (reason: Error) => void;
  u.install.mockReturnValue(new Promise<void>((_resolve, reject) => { fail = reject; }));
  checkMock.mockResolvedValue(u);
  await render();
  let manual!: Promise<void>;
  await act(async () => { manual = lastResult.installNow(); });
  const rejected = expect(manual).rejects.toThrow("bad signature");
  const secondRejected = expect(lastResult.installNow()).rejects.toThrow("bad signature");
  const event = { preventDefault: vi.fn() };
  const closing = closeHandler(event);
  expect(event.preventDefault).toHaveBeenCalled();
  expect(u.install).toHaveBeenCalledTimes(1);
  await act(async () => { fail(new Error("bad signature")); await Promise.all([rejected, secondRejected, closing]); });
  expect(fakeWindow.destroy).toHaveBeenCalledTimes(1);
});

it("keeps the owner while a widget exists even with idle recording state", async () => {
  const { WebviewWindow } = await import("@tauri-apps/api/webviewWindow");
  vi.mocked(WebviewWindow.getByLabel).mockResolvedValueOnce({} as Awaited<ReturnType<typeof WebviewWindow.getByLabel>>);
  await render();
  const event = await close();
  expect(event.preventDefault).toHaveBeenCalled();
  expect(fakeWindow.hide).toHaveBeenCalledTimes(1);
  expect(fakeWindow.destroy).not.toHaveBeenCalled();
});
it("contains an idle destroy rejection and permits a later close retry", async () => {
  await render();
  fakeWindow.destroy.mockRejectedValueOnce(new Error("native close failed"));
  await expect(close()).resolves.toBeDefined();
  await expect(close()).resolves.toBeDefined();
  expect(fakeWindow.destroy).toHaveBeenCalledTimes(2);
});

it("keeps main when native recording survived reload with an idle JS store", async () => {
  const { invoke } = await import("@tauri-apps/api/core");
  vi.mocked(invoke).mockResolvedValueOnce(true);
  await render();
  await close();
  expect(fakeWindow.hide).toHaveBeenCalledTimes(1);
  expect(fakeWindow.destroy).not.toHaveBeenCalled();
});
