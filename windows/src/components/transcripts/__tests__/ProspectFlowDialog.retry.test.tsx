import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ProspectFlowDialog } from "../ProspectFlowDialog";
import { loadOfferRef } from "../../../services/prospectFlow";
import { useSettingsStore } from "../../../stores/settingsStore";

const { invoke, loadCredential } = vi.hoisted(() => ({ invoke: vi.fn(), loadCredential: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../../../services/tauriCommands", () => ({ loadCredential }));

const transcript = { id: "lost-reply", title: "Gesprek", notule_html: "<p>Voorbeeld</p>", created_at: "2026-11-10", updated_at: "2026-11-10", duration_seconds: 0, tags: [] };
let host: HTMLDivElement;
let root: Root;
let offerIds: Set<string>;
let posts: { request_id: string; customer_id?: number; new_customer_name?: string }[];

async function mount() {
  root = createRoot(host);
  await act(async () => { root.render(<ProspectFlowDialog transcript={transcript} onClose={() => {}} />); });
}
async function click(label: string) {
  await act(async () => { [...host.querySelectorAll("button")].find(b => b.textContent === label)!.click(); });
}
async function loseReplyAndReopen() {
  await mount();
  await act(async () => { host.querySelector<HTMLInputElement>('input[type="radio"]')!.click(); });
  await act(async () => {
    const field = host.querySelector<HTMLInputElement>('[aria-label="Naam nieuwe klant"]')!;
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(field, "Nieuw BV");
    field.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await click("Maak conceptofferte");
  expect(posts).toHaveLength(1);
  expect(host.querySelector('[role="alert"]')).not.toBeNull();
  await act(async () => { root.unmount(); });
  await mount();
}

beforeEach(() => {
  vi.resetAllMocks();
  localStorage.clear();
  useSettingsStore.setState({ prospectflow_base_url: "https://pf.test" });
  loadCredential.mockResolvedValue("fixture-key");
  host = document.createElement("div"); document.body.append(host); posts = []; offerIds = new Set();
  invoke.mockImplementation(async (_command: string, { request }: { request: { url: string; body: string } }) => {
    if (request.url.endsWith("/match")) return { status: 200, body: JSON.stringify({ kandidaten: posts.length ? [{ id: 12, naam: "Nieuw BV" }, { id: 99, naam: "Andere BV" }] : [] }) };
    const post = JSON.parse(request.body);
    posts.push(post);
    const bestaand = offerIds.has(post.request_id);
    offerIds.add(post.request_id);
    if (posts.length === 1) throw new Error("Reply lost after server commit");
    return { status: 200, body: JSON.stringify({ offer_id: 431, number: "20261110-1", url: "/offers/431/build", klant: { id: post.customer_id ?? 12, naam: post.customer_id === 99 ? "Andere BV" : "Nieuw BV", nieuw: false }, regels: 1, te_controleren: 0, bestaand, terugval_gebruikt: false }) };
  });
});
afterEach(async () => { await act(async () => { root?.unmount(); }); host.remove(); });

it("reopens a lost new-customer reply with the same choice and request id, despite an existing-customer match", async () => {
  await loseReplyAndReopen();
  expect(host.querySelector<HTMLInputElement>('[aria-label="Naam nieuwe klant"]')?.value).toBe("Nieuw BV");
  await click("Maak conceptofferte");
  expect(posts).toHaveLength(2);
  expect(posts[1]).toMatchObject({ request_id: posts[0].request_id, new_customer_name: "Nieuw BV" });
  expect(posts[1]).not.toHaveProperty("customer_id");
  expect(host.textContent).toContain("al eerder gemaakt");
});

it("does not change an unresolved new-customer request into an existing-customer request for the same customer", async () => {
  await loseReplyAndReopen();
  await act(async () => { host.querySelector<HTMLInputElement>('input[type="radio"]')!.click(); });
  await click("Maak conceptofferte");
  expect(posts).toHaveLength(1);
  expect(offerIds.size).toBe(1);
  expect(loadOfferRef(transcript.id)?.pendingRequestId).toBe(posts[0].request_id);
  expect(host.querySelector('[role="alert"]')?.textContent).toContain("onbevestigde offerteaanvraag");
  await act(async () => { root.unmount(); });
  await mount();
  await click("Maak conceptofferte");
  expect(posts).toHaveLength(2);
  expect(posts[1].request_id).toBe(posts[0].request_id);
  expect(offerIds.size).toBe(1);
});

it("requires recovery before a genuinely different customer can receive a new request id", async () => {
  await loseReplyAndReopen();
  const chooseOther = async () => {
    await act(async () => {
      [...host.querySelectorAll("label")].find(label => label.textContent?.includes("Andere BV"))!.querySelector<HTMLInputElement>("input")!.click();
    });
  };
  await chooseOther();
  await click("Maak conceptofferte");
  expect(posts).toHaveLength(1);
  expect(loadOfferRef(transcript.id)?.pendingRequestId).toBe(posts[0].request_id);
  await act(async () => { root.unmount(); });
  await mount();
  await click("Maak conceptofferte");
  expect(posts[1].request_id).toBe(posts[0].request_id);
  expect(offerIds.size).toBe(1);
  await act(async () => { root.unmount(); });
  await mount();
  await chooseOther();
  await click("Maak conceptofferte");
  expect(posts[2]).toMatchObject({ customer_id: 99 });
  expect(posts[2].request_id).not.toBe(posts[0].request_id);
  expect(posts[2]).not.toHaveProperty("new_customer_name");
  expect(offerIds.size).toBe(2);
});
