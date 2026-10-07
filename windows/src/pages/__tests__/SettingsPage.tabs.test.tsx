import { expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter } from "react-router-dom";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async (cmd: string) => cmd === "whisper_model_status" ? { exists: false } : null),
}));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async () => () => {}) }));
vi.mock("@tauri-apps/api/app", () => ({ getVersion: vi.fn(async () => "1.0.0") }));
vi.mock("../../services/tauriCommands", () => ({
  loadCredential: vi.fn(async () => null),
  storeCredential: vi.fn(async () => {}),
  deleteCredential: vi.fn(async () => {}),
}));

import { SettingsPage } from "../SettingsPage";

// One heading per tab; guards the per-tab split against dropped or miswired tabs.
const TABS: [string, string][] = [
  ["Algemeen", "Controleer op updates"],
  ["Verwerking", "Snelle setup"],
  ["Notulen", "Standaard notulentemplate"],
  ["Agenda", "Microsoft 365"],
  ["Obsidian", "Obsidian-koppeling"],
  ["Account", "Onboarding opnieuw doorlopen"],
  ["Geavanceerd", "Server URL"],
];

it("renders every settings tab with its own content", async () => {
  const container = document.createElement("div");
  document.body.appendChild(container);
  const root = createRoot(container);
  await act(async () => { root.render(<MemoryRouter><SettingsPage /></MemoryRouter>); });
  for (const [name, marker] of TABS) {
    const button = [...container.querySelectorAll<HTMLButtonElement>(".settings-tabs button")].find(b => b.textContent === name)!;
    await act(async () => { button.click(); });
    expect(container.innerHTML, name).toContain(marker);
  }
  await act(async () => { root.unmount(); });
  container.remove();
});
