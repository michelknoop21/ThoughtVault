import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { ProspectFlowDialog } from "../ProspectFlowDialog";

const api = vi.hoisted(() => ({ match: vi.fn(), createOffer: vi.fn(), openOffer: vi.fn(), searchCustomers: vi.fn() }));
vi.mock("../../../services/prospectFlow", () => api);

it("shows an opening error after the offer has been created", async () => {
  api.match.mockResolvedValue([{ id: 1, naam: "Voorbeeld" }]);
  api.createOffer.mockResolvedValue({ number: "20261110-1", url: "/offers/1/build", klant: { naam: "Voorbeeld", nieuw: false }, regels: 2, te_controleren: 1 });
  api.openOffer.mockRejectedValue(new Error("Browser niet beschikbaar"));
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(async () => { root.render(<ProspectFlowDialog transcript={{ id: "test", title: "Gesprek", notule_html: "<p>Voorbeeld</p>", created_at: "2026-11-10", updated_at: "2026-11-10", duration_seconds: 0, tags: [] }} onClose={() => {}} />); });
    await act(async () => { [...container.querySelectorAll("button")].find(b => b.textContent === "Maak conceptofferte")!.click(); });
    expect(container.textContent).toContain("20261110-1");
    await act(async () => { [...container.querySelectorAll("button")].find(b => b.textContent === "Open offerte")!.click(); });
    expect(container.querySelector('[role="alert"]')?.textContent).toContain("Browser niet beschikbaar");
    expect(api.createOffer).toHaveBeenCalledOnce();
  } finally {
    await act(async () => { root.unmount(); });
    container.remove();
  }
});
