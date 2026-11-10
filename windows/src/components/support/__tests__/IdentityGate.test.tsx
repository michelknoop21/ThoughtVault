import { PRIVACY_URL } from "../../../services/supportRelay";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { IdentityGate } from "../IdentityGate";
import { useSupportStore } from "../../../stores/supportStore";

const { open } = vi.hoisted(() => ({ open: vi.fn(async () => {}) }));
vi.mock("@tauri-apps/plugin-shell", () => ({ open }));
let root: Root;
let host: HTMLDivElement;
const originalSetAutoReport = useSupportStore.getState().setAutoReport;
const originalFlush = useSupportStore.getState().flushQueue;
const originalSetIdentity = useSupportStore.getState().setIdentity;
const flushQueue = vi.fn(async () => {});
beforeEach(async () => {
  open.mockReset().mockResolvedValue(undefined);
  flushQueue.mockReset().mockResolvedValue(undefined);
  useSupportStore.setState({ name: "", email: "", auto_report: true, setAutoReport: originalSetAutoReport, setIdentity: originalSetIdentity, flushQueue });
  host = document.createElement("div"); document.body.append(host);
  root = createRoot(host);
  await act(async () => root.render(<IdentityGate />));
});
afterEach(async () => {
  await act(async () => root.unmount()); host.remove();
  useSupportStore.setState({ setAutoReport: originalSetAutoReport, setIdentity: originalSetIdentity, flushQueue: originalFlush });
});
function fill(selector: string, value: string) {
  const input = host.querySelector<HTMLInputElement>(selector)!;
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
}
function submit() { host.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })); }

it("requires both a nonblank name and valid email, including on direct form submit", async () => {
  const button = host.querySelector<HTMLButtonElement>('button[type="submit"]')!;
  expect(button.disabled).toBe(true);
  await act(async () => { fill("#identity-name", "   "); fill("#identity-email", "jan@example.com"); submit(); });
  expect(button.disabled).toBe(true);
  await act(async () => { fill("#identity-name", "Jan"); fill("#identity-email", "jan@"); submit(); });
  expect(button.disabled).toBe(true);
  expect(flushQueue).not.toHaveBeenCalled();
  expect(useSupportStore.getState().name).toBe("");
});

it("shows an associated email error only after blur and clears it when corrected", async () => {
  const input = host.querySelector<HTMLInputElement>("#identity-email")!;
  await act(async () => fill("#identity-email", "jan@"));
  expect(host.querySelector('[role="alert"]')).toBeNull();
  await act(async () => input.dispatchEvent(new FocusEvent("focusout", { bubbles: true })));
  expect(input.getAttribute("aria-invalid")).toBe("true");
  expect(input.getAttribute("aria-describedby")).toBe("identity-email-error");
  expect(host.querySelector('[role="alert"]')?.textContent).toBe("Vul een geldig e-mailadres in.");
  await act(async () => fill("#identity-email", "jan@example.com"));
  expect(host.querySelector('[role="alert"]')).toBeNull();
  expect(input.getAttribute("aria-invalid")).toBe("false");
});

it("stores trimmed identity once and catches a rejected flush without blocking continuation", async () => {
  flushQueue.mockRejectedValueOnce(new Error("Offline"));
  const setIdentity = vi.fn(originalSetIdentity);
  useSupportStore.setState({ setIdentity });
  await act(async () => { fill("#identity-name", " Jan "); fill("#identity-email", " jan@example.com "); });
  expect(host.querySelector<HTMLButtonElement>('button[type="submit"]')!.disabled).toBe(false);
  await act(async () => { submit(); submit(); });
  expect(setIdentity).toHaveBeenCalledExactlyOnceWith("Jan", "jan@example.com");
  expect(useSupportStore.getState()).toMatchObject({ name: "Jan", email: "jan@example.com" });
  expect(flushQueue).toHaveBeenCalledTimes(1);
  expect(host.querySelector<HTMLButtonElement>('button[type="submit"]')!.disabled).toBe(true);
});

it("uses labels, email input hints, focus and the exact privacy explanation", () => {
  expect(host.textContent).toContain("Met je naam en e-mailadres kan de ontwikkelaar je meldingen beantwoorden.");
  expect(host.textContent).toContain("Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee.");
  expect(host.textContent).toContain("Automatisch versturen zet je uit bij Instellingen, Account.");
  const name = host.querySelector<HTMLInputElement>("#identity-name")!;
  const email = host.querySelector<HTMLInputElement>("#identity-email")!;
  expect(name.labels?.[0].textContent).toBe("Naam");
  expect(email.labels?.[0].textContent).toBe("E-mailadres");
  expect(name.autocomplete).toBe("name");
  expect(email.autocomplete).toBe("email");
  expect(email.type).toBe("email");
  expect(email.inputMode).toBe("email");
  expect(document.activeElement).toBe(name);
});

function privacyButton() { return [...host.querySelectorAll<HTMLButtonElement>("button")].find(button => button.textContent === "Privacyverklaring")!; }
it.each([true, false])("opens privacy for invalid and valid drafts without submitting identity (auto_report=%s)", async (autoReport) => {
  const setIdentity = vi.fn(originalSetIdentity);
  const setAutoReport = vi.fn(originalSetAutoReport);
  await act(async () => useSupportStore.setState({ setIdentity, setAutoReport, auto_report: autoReport }));
  const formSubmit = vi.fn();
  host.querySelector("form")!.addEventListener("submit", formSubmit);
  expect(privacyButton().type).toBe("button");
  expect(privacyButton().disabled).toBe(false);
  await act(async () => privacyButton().click());
  expect(open).toHaveBeenCalledExactlyOnceWith(PRIVACY_URL);
  await act(async () => { fill("#identity-name", "Jan"); fill("#identity-email", "jan@example.com"); });
  await act(async () => privacyButton().click());
  expect(open.mock.calls).toEqual([[PRIVACY_URL], [PRIVACY_URL]]);
  expect(formSubmit).not.toHaveBeenCalled();
  expect(setIdentity).not.toHaveBeenCalled();
  expect(flushQueue).not.toHaveBeenCalled();
  expect(useSupportStore.getState().auto_report).toBe(autoReport);
  expect(setAutoReport).not.toHaveBeenCalled();
});
it.each([true, false])("handles rejected privacy open and retry (auto_report=%s)", async (autoReport) => {
  const setAutoReport = vi.fn(originalSetAutoReport);
  await act(async () => useSupportStore.setState({ setAutoReport, auto_report: autoReport }));
  open.mockRejectedValueOnce(new Error("sensitive native details"));
  await act(async () => privacyButton().click());
  expect(open).toHaveBeenCalledExactlyOnceWith(PRIVACY_URL);
  expect(host.querySelector('[role="status"]')?.textContent).toBe("De privacyverklaring kon niet worden geopend. Probeer het opnieuw.");
  expect(host.textContent).not.toContain("sensitive native details");
  expect(useSupportStore.getState().auto_report).toBe(autoReport);
  await act(async () => privacyButton().click());
  expect(host.querySelector('[role="status"]')).toBeNull();
  expect(open).toHaveBeenCalledTimes(2);
  expect(useSupportStore.getState().auto_report).toBe(autoReport);
  expect(setAutoReport).not.toHaveBeenCalled();
  expect(flushQueue).not.toHaveBeenCalled();
});
