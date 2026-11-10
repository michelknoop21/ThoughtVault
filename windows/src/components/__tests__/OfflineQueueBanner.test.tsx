import { expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { OfflineQueueBanner } from "../OfflineQueueBanner";
import { useSettingsStore } from "../../stores/settingsStore";
import { useUploadQueueStore } from "../../stores/uploadQueueStore";

vi.mock("../../services/offlineQueue", () => ({ getQueue: vi.fn(async () => []), processQueue: vi.fn(), clearQueue: vi.fn() }));

async function render() {
  const host = document.createElement("div");
  document.body.append(host);
  await act(async () => createRoot(host).render(<OfflineQueueBanner />));
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
