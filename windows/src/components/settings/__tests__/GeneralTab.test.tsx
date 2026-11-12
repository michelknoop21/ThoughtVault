import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { GeneralTab } from "../GeneralTab";
import { CHECK_UPDATES_EVENT } from "../../../hooks/useUpdateCheck";
import { useSettingsStore } from "../../../stores/settingsStore";

vi.mock("@tauri-apps/api/app", () => ({ getVersion: async () => "1.0.400" }));
let root: ReturnType<typeof createRoot>;
let host: HTMLDivElement;
beforeEach(() => {
  useSettingsStore.setState({ check_for_updates: true });
  host = document.createElement("div"); document.body.appendChild(host);
  root = createRoot(host);
});
afterEach(async () => { await act(async () => { root.unmount(); }); host.remove(); });
async function render() {
  await act(async () => { root.render(<GeneralTab />); });
}
it("labels the switch Automatisch bijwerken", async () => {
  await render();
  expect(host.querySelector('[role="switch"]')?.getAttribute("aria-label")).toBe("Automatisch bijwerken");
  expect(host.textContent).not.toContain("Controleer op updates");
  expect(host.textContent).toContain("Nieuwe versies worden op de achtergrond gedownload en geïnstalleerd als je ThoughtVault afsluit. Nooit tijdens een opname of verwerking.");
  expect(host.textContent).toContain("Versie 1.0.400");
});
it.each([true, false])("dispatches tv-check-updates from Zoek naar updates with auto updates %s", async (enabled) => {
  useSettingsStore.setState({ check_for_updates: enabled });
  await render();
  const spy = vi.fn();
  window.addEventListener(CHECK_UPDATES_EVENT, spy);
  try {
    const button = [...host.querySelectorAll<HTMLButtonElement>("button")].find(button => button.textContent === "Zoek naar updates")!;
    expect(button.disabled).toBe(false);
    await act(async () => { button.click(); });
    expect(spy).toHaveBeenCalledTimes(1);
    expect(useSettingsStore.getState().check_for_updates).toBe(enabled);
  } finally { window.removeEventListener(CHECK_UPDATES_EVENT, spy); }
});
