import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { CHECK_UPDATES_EVENT, UPDATE_CHECK_INTERVAL_MS, useUpdateCheck } from "../useUpdateCheck";
import { useSettingsStore } from "../../stores/settingsStore";
import { useRecordingStore } from "../../stores/recordingStore";
const { checkMock } = vi.hoisted(() => ({ checkMock: vi.fn(async (): Promise<any> => null) }));
let closeHandler: ((e: unknown) => void) | null = null;
const fakeWindow = {
  onCloseRequested: vi.fn(async (cb: (e: unknown) => void) => { closeHandler = cb; return () => {}; }),
  destroy: vi.fn(async () => {}),
};
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => fakeWindow }));
vi.mock("@tauri-apps/api/app", () => ({getVersion: async () => "1.0.260", getName: async () => "ThoughtVault"}));
vi.mock("@tauri-apps/plugin-updater", () => ({check: checkMock}));
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
  return {
    version,
    download: vi.fn(async () => {}),
    install: vi.fn(async () => {}),
    downloadAndInstall: vi.fn(async () => {}),
    close: vi.fn(async () => {}),
  };
}
const mounted: ReturnType<typeof createRoot>[] = [];
async function render() {
  Object.assign(window, {__TAURI_INTERNALS__:{}});
  vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })));
  const root = createRoot(document.createElement("div"));
  mounted.push(root);
  function Probe() { useUpdateCheck(); return null; }
  await act(async () => { root.render(<Probe/>); });
  return root;
}
beforeEach(() => {
  closeHandler = null;
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
  vi.useFakeTimers();
  const bad = fakeUpdate("1.0.400"); bad.download.mockRejectedValue(new Error("offline"));
  const good = fakeUpdate("1.0.400");
  checkMock.mockResolvedValueOnce(bad).mockResolvedValueOnce(good);
  await render();
  await act(async () => { await vi.advanceTimersByTimeAsync(UPDATE_CHECK_INTERVAL_MS); });
  expect(good.download).toHaveBeenCalledTimes(1);
});
it("stops the interval and the event listener on unmount", async () => {
  vi.useFakeTimers(); checkMock.mockResolvedValue(null);
  const root = await render(); await act(async () => { root.unmount(); });
  await act(async () => { await vi.advanceTimersByTimeAsync(UPDATE_CHECK_INTERVAL_MS); window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(checkMock).toHaveBeenCalledTimes(1);
});
