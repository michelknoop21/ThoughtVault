vi.mock("../../../services/customerSuggestion", async () => ({ ...await vi.importActual("../../../services/customerSuggestion"), suggestCustomer: vi.fn(async () => null) }));
import { act } from "react";
import { createRoot } from "react-dom/client";
import { beforeEach, expect, it, vi } from "vitest";
import { suggestCustomer } from "../../../services/customerSuggestion";
import { ProspectFlowDialog } from "../ProspectFlowDialog";

const api = vi.hoisted(() => ({ match: vi.fn(), loadOfferRef: vi.fn(() => null), createOffer: vi.fn(), openOffer: vi.fn(), searchCustomers: vi.fn() }));
vi.mock("../../../services/prospectFlow", () => api);

beforeEach(() => vi.clearAllMocks());

it("shows an opening error after the offer has been created", async () => {
  api.match.mockResolvedValue([{ id: 1, naam: "Voorbeeld" }]);
  api.createOffer.mockResolvedValue({ number: "20261110-1", url: "/offers/1/build", instanceBaseUrl: "https://first.test", klant: { naam: "Voorbeeld", nieuw: false }, regels: 2, te_controleren: 1 });
  api.openOffer.mockRejectedValue(new Error("Browser niet beschikbaar"));
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(async () => { root.render(<ProspectFlowDialog transcript={{ id: "test", title: "Gesprek", notule_html: "<p>Voorbeeld</p>", created_at: "2026-11-10", updated_at: "2026-11-10", duration_seconds: 0, tags: [] }} onClose={() => {}} />); });
    expect([...container.querySelectorAll("button")].find(b => b.textContent === "Maak conceptofferte")!.disabled).toBe(true);
    await act(async () => { container.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click(); });
    await act(async () => { [...container.querySelectorAll("button")].find(b => b.textContent === "Maak conceptofferte")!.click(); });
    expect(container.textContent).toContain("20261110-1");
    await act(async () => { [...container.querySelectorAll("button")].find(b => b.textContent === "Open offerte")!.click(); });
    expect(container.querySelector('[role="alert"]')?.textContent).toContain("Browser niet beschikbaar");
    expect(api.openOffer).toHaveBeenCalledWith("/offers/1/build", "https://first.test");
    expect(api.createOffer).toHaveBeenCalledOnce();
  } finally {
    await act(async () => { root.unmount(); });
    container.remove();
  }
});

it("prefills the grounded organisation and sends the approved saved minutes", async () => {
  vi.mocked(suggestCustomer).mockResolvedValueOnce({ name: "Friese Installatietechniek", source: "notes", quote: "Offerte voor Friese Installatietechniek" });
  api.match.mockResolvedValueOnce([]);
  const host = document.createElement("div"); document.body.append(host);
  const root = createRoot(host);
  const transcript = { id: "customer-test", title: "Offerte", notule_html: "<p>Offerte voor Friese Installatietechniek</p>", raw_transcription: "Sanne is contactpersoon", created_at: "2026-11-17", updated_at: "2026-11-17", duration_seconds: 0, tags: [] };
  try {
    await act(async () => { root.render(<ProspectFlowDialog transcript={transcript} onClose={() => {}} />); });
    expect(host.querySelector<HTMLInputElement>('[aria-label="Naam nieuwe klant"]')?.value).toBe("Friese Installatietechniek");
    expect(api.match).toHaveBeenCalledWith(expect.stringContaining("Sanne is contactpersoon"));
    const create = [...host.querySelectorAll("button")].find(b => b.textContent === "Maak conceptofferte")!;
    expect(create.disabled).toBe(true);
    await act(async () => { host.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click(); });
    await act(async () => { create.click(); });
    expect(api.createOffer).toHaveBeenCalledWith(expect.objectContaining({ newCustomerName: "Friese Installatietechniek", notuleHtml: transcript.notule_html }));
  } finally { await act(async () => root.unmount()); host.remove(); }
});
