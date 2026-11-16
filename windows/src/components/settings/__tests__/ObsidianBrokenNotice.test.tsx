import { act } from "react";
import { createRoot } from "react-dom/client";
import { beforeEach, expect, it, vi } from "vitest";
import { ObsidianBrokenNotice } from "../ObsidianBrokenNotice";
import { TranscriptDetail } from "../../transcripts/TranscriptDetail";
import { useObsidianLinkStore } from "../../../stores/obsidianStore";
import { useSettingsStore } from "../../../stores/settingsStore";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn().mockResolvedValue(undefined) }));
vi.mock("../../../services/prospectFlow", () => ({ isConfigured: vi.fn().mockResolvedValue(false), loadOfferRef: vi.fn(), openOffer: vi.fn() }));

beforeEach(() => {
  useSettingsStore.setState({ obsidian_enabled: true });
  useObsidianLinkStore.getState().setBroken(true);
});

async function mount(node: React.ReactElement) {
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(node); });
  return { container, unmount: () => act(async () => { root.unmount(); }) };
}

it("shows one message with both buttons and turns Obsidian off", async () => {
  const choose = vi.fn();
  const { container, unmount } = await mount(<ObsidianBrokenNotice onChooseVault={choose} />);
  expect(container.textContent).toContain("De koppeling met Obsidian werkt niet meer. Je notules staan wel in ThoughtVault.");
  const buttons = [...container.querySelectorAll("button")];
  expect(buttons.map(b => b.textContent)).toEqual(["Vault opnieuw kiezen", "Obsidian uitzetten"]);
  await act(async () => { buttons[0].click(); });
  expect(choose).toHaveBeenCalled();
  await act(async () => { buttons[1].click(); });
  expect(useSettingsStore.getState().obsidian_enabled).toBe(false);
  expect(useObsidianLinkStore.getState().broken).toBe(false);
  expect(container.textContent).toBe("");
  await unmount();
});

it("renders nothing while the switch is off or the link works", async () => {
  useSettingsStore.setState({ obsidian_enabled: false });
  const { container, unmount } = await mount(<ObsidianBrokenNotice />);
  expect(container.textContent).toBe("");
  await unmount();
});

it("hides the manual Obsidian buttons when the switch is off", async () => {
  const noop = vi.fn();
  for (const enabled of [false, true]) {
    useSettingsStore.setState({ obsidian_enabled: enabled });
    const { container, unmount } = await mount(<TranscriptDetail transcript={{ id: "n1", title: "Gesprek", notule_html: "<p>Notule</p>", created_at: "2026-11-10", updated_at: "2026-11-10", duration_seconds: 0, tags: [] }}
      regeneratingId={null} onBack={noop} onRegenerate={noop} onDelete={noop} onUpdateTitle={async () => {}}
      onSaveNotule={async () => {}} onCopy={noop} onExportPDF={noop} onExportTXT={noop} onExportMarkdown={noop}
      onExportHTML={noop} onExportObsidian={noop} onImportObsidian={noop} onOpenTags={noop} onGenerateTitle={noop} />);
    await act(async () => { container.querySelector<HTMLButtonElement>('[title="Exporteren"]')!.click(); });
    expect(container.textContent?.includes("Naar Obsidian")).toBe(enabled);
    expect(container.textContent?.includes("De koppeling met Obsidian werkt niet meer")).toBe(enabled);
    await unmount();
  }
});
