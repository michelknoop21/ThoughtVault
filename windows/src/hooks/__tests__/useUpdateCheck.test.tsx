import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { useUpdateCheck } from "../useUpdateCheck";
import { useSettingsStore } from "../../stores/settingsStore";
vi.mock("@tauri-apps/api/app", () => ({getVersion: async () => "1.0.260", getName: async () => "ThoughtVault"}));
vi.mock("@tauri-apps/plugin-updater", () => ({check: async () => null}));
afterEach(() => { vi.unstubAllGlobals(); });
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
