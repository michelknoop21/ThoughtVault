import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { OfflineQueueBanner } from "../OfflineQueueBanner";
import { useSettingsStore } from "../../stores/settingsStore";
import { useUploadQueueStore } from "../../stores/uploadQueueStore";

vi.mock("../../services/offlineQueue", () => ({ getQueue: vi.fn(async () => []), processQueue: vi.fn(), clearQueue: vi.fn() }));

const mounted: { root: Root; host: HTMLDivElement }[] = [];
const settings = useSettingsStore.getState();
const uploads = useUploadQueueStore.getState();
afterEach(async () => {
  await act(async () => { for (const { root, host } of mounted.splice(0)) { root.unmount(); host.remove(); } });
  useSettingsStore.setState(settings);
  useUploadQueueStore.setState(uploads);
});

async function render() {
  const host = document.createElement("div");
  document.body.append(host);
  const root = createRoot(host);
  mounted.push({ root, host });
  await act(async () => root.render(<OfflineQueueBanner />));
  return host;
}

it("renders nothing in local mode", async () => {
  useSettingsStore.setState({ processing_mode: "local" });
  expect((await render()).textContent).toBe("");
});

it("shows permanently failed uploads in cloud mode", async () => {
  useSettingsStore.setState({ processing_mode: "cloud" });
  useUploadQueueStore.setState({ items: [], currentItem: null, permanentlyFailed: [{ id: "1", fileName: "opname.wav" }] as never });
  expect((await render()).textContent).toContain("'opname.wav' kon na meerdere pogingen niet worden geüpload");
});
