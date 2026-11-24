import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import FeedbackWidget from "../FeedbackWidget";
import { useSupportStore } from "../../stores/supportStore";
import { listTickets, markAllRead, postMessage, ticketMessages } from "../../services/supportRelay";
const { show } = vi.hoisted(() => ({ show: vi.fn() }));
vi.mock("../ui/InfoBar", () => ({ useToast: () => ({ show }) }));
vi.mock("../../services/supportRelay", async orig => ({ ...(await orig<object>()), listTickets: vi.fn(), markAllRead: vi.fn(), ticketMessages: vi.fn(), postMessage: vi.fn() }));
vi.mock("../../stores/supportStore", async orig => ({ ...(await orig<object>()), withInstallation: (fn: (inst: { id: string; secret: string }) => Promise<unknown>) => fn({ id: "i", secret: "s" }) }));
const ticket = { id: "a", ref: "TV-2", status: "WAITING_FOR_USER" as const, category: "BUG" as const, description: "Notule mislukt", createdAt: "2026-11-10T10:00:00Z", unread: true, lastMessage: null };
let host: HTMLDivElement; let root: Root;
const button = (text: string) => [...host.querySelectorAll("button")].find(item => item.textContent === text)!;
async function fill(value: string) {
  await act(async () => { const field = host.querySelector("textarea")!; Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(field, value); field.dispatchEvent(new Event("input", { bubbles: true })); });
}
beforeEach(async () => {
  vi.clearAllMocks();
  vi.mocked(markAllRead).mockResolvedValue(undefined);
  vi.mocked(listTickets).mockResolvedValue([ticket]); vi.mocked(ticketMessages).mockResolvedValue([]);
  useSupportStore.setState({ unread_count: 2, auto_report: false, submitManual: vi.fn().mockResolvedValue("sent"), refreshUnread: vi.fn().mockResolvedValue(undefined) });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  await act(async () => root.render(<FeedbackWidget initialOpen />));
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); });
it("submits trimmed manual feedback with automatic reports off, without a title or clipboard", async () => {
  expect(host.querySelector('input[type="text"]')).toBeNull();
  expect(host.textContent).toContain("2");
  await act(async () => { const select = host.querySelector("select")!; select.value = "FEATURE_REQUEST"; select.dispatchEvent(new Event("change", { bubbles: true })); });
  await fill(" Synthetic feedback "); await act(async () => button("Versturen").click());
  expect(useSupportStore.getState().submitManual).toHaveBeenCalledWith("FEATURE_REQUEST", "Synthetic feedback");
  expect(host.querySelector("textarea")?.value).toBe(""); expect(show).toHaveBeenCalledWith("Melding verstuurd.", "success");
});
it.each(["sent", "queued", "failed"] as const)("clears only an acknowledged or durable %s submission", async outcome => {
  useSupportStore.setState({ submitManual: vi.fn().mockResolvedValue(outcome) });
  await fill("Bewaar dit"); await act(async () => button("Versturen").click());
  expect(host.querySelector("textarea")?.value).toBe(outcome === "failed" ? "Bewaar dit" : "");
});
it("rejects whitespace and locks fields, close, Escape and tabs during a single pending submission", async () => {
  let resolve!: (value: "sent") => void;
  const submitManual = vi.fn(() => new Promise<"sent">(done => { resolve = done; })); useSupportStore.setState({ submitManual });
  await fill("   "); expect(button("Versturen").disabled).toBe(true);
  await fill("Bewaar dit");
  await act(async () => { button("Versturen").click(); button("Versturen").click(); });
  expect(submitManual).toHaveBeenCalledTimes(1); expect(host.querySelector("textarea")?.disabled).toBe(true);
  expect(button("Mijn meldingen").disabled).toBe(true); expect(host.querySelector<HTMLButtonElement>('[aria-label="Feedback sluiten"]')?.disabled).toBe(true);
  await act(async () => host.querySelector("dialog")!.dispatchEvent(new Event("cancel", { bubbles: true, cancelable: true })));
  expect(host.querySelector("dialog")).not.toBeNull();
  await act(async () => resolve("sent")); expect(host.querySelector("textarea")?.value).toBe("");
});
it("limits input to 5000 and preserves the draft after an exception", async () => {
  expect(host.querySelector("textarea")?.maxLength).toBe(5000);
  useSupportStore.setState({ submitManual: vi.fn().mockRejectedValue(new Error("private body")) });
  await fill("Concept"); await act(async () => button("Versturen").click());
  expect(host.querySelector("textarea")?.value).toBe("Concept"); expect(JSON.stringify(show.mock.calls)).not.toContain("private body");
});
it("lists statuses, opens a thread and preserves its draft on back", async () => {
  await act(async () => button("Mijn meldingen").click()); expect(host.textContent).toContain("Wacht op jou");
  await act(async () => [...host.querySelectorAll("button")].find(item => item.textContent?.includes("TV-2"))!.click());
  await fill("Antwoordconcept");
  await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="Terug naar mijn meldingen"]')!.click());
  await act(async () => [...host.querySelectorAll("button")].find(item => item.textContent?.includes("TV-2"))!.click());
  expect(host.querySelector("textarea")?.value).toBe("Antwoordconcept");
  let reject!: (error: Error) => void; vi.mocked(postMessage).mockImplementation(() => new Promise((_done, fail) => { reject = fail; }));
  await act(async () => button("Antwoord versturen").click());
  expect(button("Nieuw").disabled).toBe(true); expect(host.querySelector<HTMLButtonElement>('[aria-label="Feedback sluiten"]')!.disabled).toBe(true);
  await act(async () => reject(new Error("private reply"))); expect(host.querySelector("textarea")?.value).toBe("Antwoordconcept");
});
it("shows the empty state and a neutral failure without leaking response text", async () => {
  vi.mocked(listTickets).mockRejectedValue(new Error("private server response"));
  await act(async () => button("Mijn meldingen").click());
  expect(host.textContent).toContain("Nog geen meldingen verstuurd."); expect(show).toHaveBeenCalledWith("Meldingen ophalen lukt nu niet.", "error");
  expect(JSON.stringify(show.mock.calls)).not.toContain("private server response");
});

it("marks all reports once, refreshes dots and badge, and retains the reports", async () => {
  await act(async () => button("Mijn meldingen").click());
  let finish!: () => void;
  vi.mocked(markAllRead).mockImplementationOnce(() => new Promise<void>(resolve => { finish = resolve; }));
  vi.mocked(listTickets).mockResolvedValue([{ ...ticket, unread: false }]);
  useSupportStore.setState({ refreshUnread: vi.fn(async () => { useSupportStore.setState({ unread_count: 0 }); }) });
  const read = button("Alles als gelezen markeren");
  await act(async () => { read.click(); read.click(); });
  expect(markAllRead).toHaveBeenCalledTimes(1);
  expect(read.disabled).toBe(true);
  await act(async () => finish());
  expect(host.textContent).toContain("Notule mislukt");
  expect(host.querySelector('[aria-label="Ongelezen"]')).toBeNull();
  expect(useSupportStore.getState().unread_count).toBe(0);
});

it("keeps unread reports and offers retry after mark-all fails", async () => {
  await act(async () => button("Mijn meldingen").click());
  vi.mocked(markAllRead).mockRejectedValueOnce(new Error("private server body"));
  await act(async () => button("Alles als gelezen markeren").click());
  expect(useSupportStore.getState().unread_count).toBe(2);
  expect(host.querySelector('[aria-label="Ongelezen"]')).not.toBeNull();
  expect(button("Alles als gelezen markeren").disabled).toBe(false);
  expect(show).toHaveBeenCalledWith("Als gelezen markeren lukt nu niet. Probeer het opnieuw.", "error");
});
