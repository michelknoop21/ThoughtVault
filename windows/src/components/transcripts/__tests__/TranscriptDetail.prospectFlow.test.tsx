import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { TranscriptDetail } from "../TranscriptDetail";

const api = vi.hoisted(() => ({ isConfigured: vi.fn(), loadOfferRef: vi.fn(), openOffer: vi.fn() }));
const toast = vi.hoisted(() => ({ show: vi.fn() }));
vi.mock("../../../services/prospectFlow", () => api);
vi.mock("../../ui/InfoBar", () => ({ useToast: () => toast }));

it.each([false, true])("handles saved-offer opening (browser failure: %s)", async (fails) => {
  vi.clearAllMocks();
  api.isConfigured.mockResolvedValue(true);
  api.loadOfferRef.mockReturnValue({ number: "20261110-1", url: "/offers/431/build" });
  api.openOffer.mockImplementation(async () => { if (fails) throw new Error("Browser niet beschikbaar"); });
  const container = document.createElement("div");
  const root = createRoot(container);
  const noop = vi.fn();
  try {
    await act(async () => { root.render(<TranscriptDetail transcript={{ id: "offer-note", title: "Gesprek", notule_html: "<p>Notule</p>", created_at: "2026-11-10", updated_at: "2026-11-10", duration_seconds: 0, tags: [] }}
      regeneratingId={null} onBack={noop} onRegenerate={noop} onDelete={noop} onUpdateTitle={async () => {}}
      onSaveNotule={async () => {}} onCopy={noop} onExportPDF={noop} onExportTXT={noop} onExportMarkdown={noop}
      onExportHTML={noop} onExportObsidian={noop} onImportObsidian={noop} onOpenTags={noop} onGenerateTitle={noop} />); });
    await act(async () => { container.querySelector<HTMLButtonElement>('[title="Exporteren"]')!.click(); });
    await act(async () => { [...container.querySelectorAll("button")].find(b => b.textContent?.includes("Open offerte 20261110-1"))!.click(); });
    expect(api.openOffer).toHaveBeenCalledWith("/offers/431/build");
    if (fails) expect(toast.show).toHaveBeenCalledWith("Browser niet beschikbaar", "error");
    else expect(toast.show).not.toHaveBeenCalled();
  } finally {
    await act(async () => { root.unmount(); });
  }
});
