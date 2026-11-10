import { act } from "react";
import { createRoot } from "react-dom/client";
import { Update } from "@tauri-apps/plugin-updater";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { UpdateBanner } from "../UpdateBanner";
import { useRecordingStore } from "../../../stores/recordingStore";

const { open } = vi.hoisted(() => ({ open: vi.fn(async () => {}) }));
vi.mock("@tauri-apps/plugin-shell", () => ({ open }));
let root: ReturnType<typeof createRoot>;
let host: HTMLDivElement;
const nativeUpdate = new Update({ rid: 1, version: "1.0.400", currentVersion: "1.0.260", rawJson: {} });
beforeEach(() => {
  open.mockReset().mockResolvedValue();
  useRecordingStore.setState({ phase: "idle", backgroundTasks: [] });
  host = document.createElement("div");
  document.body.appendChild(host);
  root = createRoot(host);
});
afterEach(async () => { await act(async () => { root.unmount(); }); host.remove(); });
async function render(props: Partial<Parameters<typeof UpdateBanner>[0]> = {}) {
  await act(async () => { root.render(<UpdateBanner version="1.0.400" downloadUrl={null} onDismiss={() => {}} {...props} />); });
}
function updateButton() {
  return [...host.querySelectorAll<HTMLButtonElement>("button")].find(button => button.textContent === "Nu bijwerken")!;
}
it("calls onInstall from Nu bijwerken", async () => {
  const onInstall = vi.fn(async () => {});
  await render({ nativeUpdate, onInstall });
  await act(async () => { updateButton().click(); });
  expect(onInstall).toHaveBeenCalledTimes(1);
});
it("tells the user a downloaded update installs on close", async () => {
  await render({ nativeUpdate, downloaded: true });
  expect(host.textContent).toContain("Versie 1.0.400 is gedownload en wordt geïnstalleerd als je ThoughtVault afsluit");
});
it("keeps Nu bijwerken disabled while recording", async () => {
  const onInstall = vi.fn(async () => {});
  useRecordingStore.setState({ phase: "recording" });
  await render({ nativeUpdate, onInstall });
  expect(updateButton().disabled).toBe(true);
  await act(async () => { updateButton().click(); });
  expect(onInstall).not.toHaveBeenCalled();
});
it("keeps Nu bijwerken disabled while processing", async () => {
  useRecordingStore.setState({ backgroundTasks: [{ task_id: "t1", status: "transcribing", progress: 40, mode: "combined", created_at: "2026-11-10T10:00:00Z" }] });
  await render({ nativeUpdate });
  expect(updateButton().disabled).toBe(true);
});
it("opens the download page when there is no native update", async () => {
  const downloadUrl = "https://thoughtvault.yinga.ai/download";
  const onInstall = vi.fn(async () => {});
  await render({ downloadUrl, onInstall });
  await act(async () => { updateButton().click(); });
  expect(open).toHaveBeenCalledWith(downloadUrl);
  expect(onInstall).not.toHaveBeenCalled();
});
it("shows the existing error and permits retry when installation fails", async () => {
  const onInstall = vi.fn(async () => {}).mockRejectedValueOnce(new Error("offline"));
  await render({ nativeUpdate, onInstall });
  await act(async () => { updateButton().click(); });
  expect(host.querySelector('[role="alert"]')?.textContent).toBe("Bijwerken mislukt. Probeer opnieuw.");
  await act(async () => { updateButton().click(); });
  expect(onInstall).toHaveBeenCalledTimes(2);
  expect(host.querySelector('[role="alert"]')).toBeNull();
});
it("disables Nu bijwerken while installation is pending", async () => {
  let finish!: () => void;
  const onInstall = vi.fn(() => new Promise<void>(resolve => { finish = resolve; }));
  await render({ nativeUpdate, onInstall });
  await act(async () => { updateButton().click(); });
  expect([...host.querySelectorAll<HTMLButtonElement>("button")].find(button => button.textContent === "Bezig...")?.disabled).toBe(true);
  await act(async () => { finish(); });
  expect(updateButton().disabled).toBe(false);
});
