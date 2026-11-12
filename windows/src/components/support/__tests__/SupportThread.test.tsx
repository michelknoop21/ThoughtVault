import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { SupportThread, TicketRow } from "../SupportThread";
import { postMessage, ticketMessages } from "../../../services/supportRelay";
import type { SupportMessage, SupportTicket } from "../../../services/supportRelay";
import { useSupportStore } from "../../../stores/supportStore";
const { show } = vi.hoisted(() => ({ show: vi.fn() }));
vi.mock("../../ui/InfoBar", () => ({ useToast: () => ({ show }) }));
vi.mock("../../../services/supportRelay", async orig => ({ ...(await orig<object>()), ticketMessages: vi.fn(), postMessage: vi.fn() }));
vi.mock("../../../stores/supportStore", async orig => ({ ...(await orig<object>()), withInstallation: (fn: (inst: { id: string; secret: string }) => Promise<unknown>) => fn({ id: "i", secret: "s" }) }));
const a: SupportTicket = { id: "a", ref: "TV-2", status: "WAITING_FOR_USER", category: "BUG", description: "Notule mislukt", createdAt: "2026-11-10T10:00:00Z", unread: true };
const b: SupportTicket = { ...a, id: "b", ref: "TV-3", description: "Andere melding" };
const message = (id: string, body: string, hour = 10, senderRole = "USER"): SupportMessage => ({ id, body, senderRole, createdAt: `2026-11-10T${hour}:00:00Z` });
function deferred<T>() { let resolve!: (value: T) => void; let reject!: (error: Error) => void; const promise = new Promise<T>((done, fail) => { resolve = done; reject = fail; }); return { promise, resolve, reject }; }
let host: HTMLDivElement; let root: Root; let mounted: boolean;
async function render(ticket = a) { await act(async () => root.render(<SupportThread ticket={ticket} onBack={vi.fn()} />)); }
async function fill(value: string) { await act(async () => { const field = host.querySelector("textarea")!; Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(field, value); field.dispatchEvent(new Event("input", { bubbles: true })); }); }
const send = () => [...host.querySelectorAll("button")].find(item => item.textContent === "Antwoord versturen")!;
beforeEach(() => {
  vi.clearAllMocks(); vi.mocked(ticketMessages).mockResolvedValue([]);
  useSupportStore.setState({ refreshUnread: vi.fn().mockResolvedValue(undefined) });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host); mounted = true;
});
afterEach(async () => { if (mounted) await act(async () => root.unmount()); host.remove(); });
it("sorts plain-text messages, attributes case-insensitive users and refreshes unread only after read", async () => {
  const read = deferred<SupportMessage[]>(); vi.mocked(ticketMessages).mockReturnValue(read.promise);
  await render(); expect(useSupportStore.getState().refreshUnread).not.toHaveBeenCalled();
  await act(async () => read.resolve([message("2", "<img src=x onerror=alert(1)>", 11, "ADMIN"), message("1", "Eerste bericht", 10, "uSeR")]));
  expect(host.textContent).toMatch(/Jij.*Eerste bericht.*ThoughtVault.*<img/s); expect(host.querySelector("img")).toBeNull();
  expect(useSupportStore.getState().refreshUnread).toHaveBeenCalledTimes(1);
  vi.mocked(postMessage).mockResolvedValue(message("3", "Dank je", 12));
  await fill(" Dank je "); await act(async () => send().click());
  expect(postMessage).toHaveBeenCalledWith({ id: "i", secret: "s" }, "a", "Dank je");
  expect(host.querySelectorAll("article")).toHaveLength(3); expect(host.querySelector("textarea")?.value).toBe("");
});
it("binds a delayed read to the visible ticket", async () => {
  const late = deferred<SupportMessage[]>(); vi.mocked(ticketMessages).mockImplementation((_inst, id) => id === "a" ? late.promise : Promise.resolve([message("b1", "B body")]));
  await render(a); await render(b); await act(async () => late.resolve([message("a1", "A private body")]));
  expect(host.textContent).toContain("B body"); expect(host.textContent).not.toContain("A private body"); expect(host.textContent).not.toContain("Notule mislukt");
});
it("isolates two simultaneous thread components", async () => {
  const lateA = deferred<SupportMessage[]>(); const lateB = deferred<SupportMessage[]>();
  vi.mocked(ticketMessages).mockImplementation((_inst, id) => id === "a" ? lateA.promise : lateB.promise);
  await act(async () => root.render(<><SupportThread ticket={a} onBack={vi.fn()} /><SupportThread ticket={b} onBack={vi.fn()} /></>));
  await act(async () => { lateB.resolve([message("b1", "B only")]); lateA.resolve([message("a1", "A only")]); });
  const sections = host.querySelectorAll("section"); expect(sections[0].textContent).toContain("A only"); expect(sections[0].textContent).not.toContain("B only");
  expect(sections[1].textContent).toContain("B only"); expect(sections[1].textContent).not.toContain("A only");
});
it("ignores an obsolete same-ticket read failure without clobbering the current reply", async () => {
  const stale = deferred<SupportMessage[]>(); vi.mocked(ticketMessages).mockReturnValueOnce(stale.promise).mockResolvedValue([message("new", "Actueel bericht")]);
  await render(a); await render(b); await render(a);
  vi.mocked(postMessage).mockResolvedValue(message("reply", "Actueel antwoord", 12));
  await fill("Actueel antwoord"); await act(async () => send().click());
  await act(async () => stale.reject(new Error("old private response")));
  expect(host.textContent).toContain("Actueel bericht"); expect(host.textContent).toContain("Actueel antwoord"); expect(host.textContent).not.toContain("Berichten ophalen lukt nu niet.");
});
it("preserves drafts after rejected or malformed POST and blocks duplicate replies/navigation", async () => {
  await render(); await fill("Concept"); expect(host.querySelector("textarea")?.maxLength).toBe(5000);
  const pending = deferred<SupportMessage>(); vi.mocked(postMessage).mockReturnValue(pending.promise);
  await act(async () => { send().click(); send().click(); });
  expect(postMessage).toHaveBeenCalledTimes(1); expect(host.querySelector("textarea")?.disabled).toBe(true);
  expect(host.querySelector<HTMLButtonElement>('[aria-label="Terug naar mijn meldingen"]')?.disabled).toBe(true);
  // The real relay rejects malformed acknowledgements before returning a message.
  await act(async () => pending.reject(new Error("Ongeldig antwoord private payload")));
  expect(host.querySelector("textarea")?.value).toBe("Concept"); expect(JSON.stringify(show.mock.calls)).not.toContain("private payload");
  expect(useSupportStore.getState().refreshUnread).toHaveBeenCalledTimes(1);
});
it("does not refresh unread for a failed or closed late read", async () => {
  const late = deferred<SupportMessage[]>(); vi.mocked(ticketMessages).mockReturnValue(late.promise); await render();
  await act(async () => root.unmount()); mounted = false;
  await act(async () => late.reject(new Error("private closed read")));
  expect(useSupportStore.getState().refreshUnread).not.toHaveBeenCalled(); expect(show).not.toHaveBeenCalled();
});
it("does not show previous ticket messages when the next read fails", async () => {
  vi.mocked(ticketMessages).mockResolvedValueOnce([message("a1", "A only")]).mockRejectedValueOnce(new Error("private malformed read"));
  await render(a); await render(b); expect(host.textContent).not.toContain("A only"); expect(host.textContent).toContain("Berichten ophalen lukt nu niet.");
  expect(useSupportStore.getState().refreshUnread).toHaveBeenCalledTimes(1);
});
it.each(["<svg onload=alert(1)>", "constructor", "__proto__"])("renders unknown status %s as safe text and accepts null lastMessage and missing updatedAt", async status => {
  await act(async () => root.render(<TicketRow ticket={{ ...a, status: status as SupportTicket["status"], lastMessage: null }} onOpen={vi.fn()} />));
  expect(host.textContent).toContain(status); expect(host.querySelector("svg")).toBeNull(); expect(host.textContent).toContain("TV-2");
});
