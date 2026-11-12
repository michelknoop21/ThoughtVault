import { PRIVACY_URL } from "../../../services/supportRelay";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AccountTab } from "../AccountTab";
import { useSupportStore } from "../../../stores/supportStore";

const { open } = vi.hoisted(() => ({ open: vi.fn(async () => {}) }));
vi.mock("@tauri-apps/plugin-shell", () => ({ open }));
vi.mock("../../FeedbackWidget", () => ({ default: () => <button>Feedback melden</button> }));
let host: HTMLDivElement;
let root: Root;
const initial = useSupportStore.getState();
beforeEach(async () => {
  open.mockReset().mockResolvedValue(undefined);
  useSupportStore.setState({ ...initial, auto_report: true, name: "Jan", email: "jan@example.nl", queue: [] });
  host = document.createElement("div"); document.body.append(host);
  root = createRoot(host);
  await act(async () => root.render(<AccountTab />));
});
afterEach(async () => {
  await act(async () => root.unmount()); host.remove();
  useSupportStore.setState(initial);
});
function field(id: string) { return host.querySelector<HTMLInputElement>(`#support-contact-${id}`)!; }
async function fill(id: string, value: string) {
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(field(id), value);
    field(id).dispatchEvent(new Event("input", { bubbles: true }));
  });
}
async function blur(id: string) {
  await act(async () => field(id).dispatchEvent(new FocusEvent("focusout", { bubbles: true })));
}
it("uses the existing switch action while keeping manual reports and feedback available", async () => {
  const manual = { id: "manual", kind: "manual" as const, category: "BUG" as const, stage: "" as const,
    shownMessage: "Test", errorText: "", clickPath: [], occurredAt: "2026-11-10T10:00:00Z" };
  useSupportStore.setState({ queue: [manual, { ...manual, id: "auto", kind: "auto" }] });
  const toggle = host.querySelector<HTMLInputElement>('[aria-label="Foutrapporten automatisch versturen"]')!;
  expect(toggle.getAttribute("role")).toBe("switch");
  expect(host.querySelector(`#${toggle.getAttribute("aria-describedby")}`)?.textContent).toContain("Zelf melden werkt altijd.");
  await act(async () => toggle.click());
  expect(useSupportStore.getState().auto_report).toBe(false);
  expect(useSupportStore.getState().queue).toEqual([manual]);
  expect(host.textContent).toContain("Feedback melden");
  await act(async () => toggle.click());
  expect(useSupportStore.getState().auto_report).toBe(true);
});
it("keeps edits in draft until blur, then saves and displays a trimmed valid identity", async () => {
  await fill("name", "  Jan Nieuw  ");
  expect(useSupportStore.getState().name).toBe("Jan");
  await blur("name");
  expect(useSupportStore.getState().name).toBe("Jan Nieuw");
  expect(field("name").value).toBe("Jan Nieuw");
  await fill("email", "  jan@prezent.nl  ");
  expect(useSupportStore.getState().email).toBe("jan@example.nl");
  await blur("email");
  expect(useSupportStore.getState()).toMatchObject({ name: "Jan Nieuw", email: "jan@prezent.nl" });
  expect(field("email").value).toBe("jan@prezent.nl");
});
it("keeps invalid drafts editable without changing stored identity", async () => {
  await fill("email", "jan@"); await blur("email");
  expect(field("email").value).toBe("jan@");
  expect(host.querySelector('[role="alert"]')?.textContent).toContain("320");
  await fill("name", "  "); await blur("name");
  expect(field("name").value).toBe("  ");
  expect(useSupportStore.getState()).toMatchObject({ name: "Jan", email: "jan@example.nl" });
});
it("requires the whole identity to be valid and uses associated labels and email hints", async () => {
  await fill("name", "Nieuw"); await fill("email", "jan@"); await blur("name");
  expect(useSupportStore.getState()).toMatchObject({ name: "Jan", email: "jan@example.nl" });
  expect(field("name").value).toBe("Nieuw");
  expect(field("email").value).toBe("jan@");
  expect(field("name").labels?.[0].textContent).toBe("Naam");
  expect(field("email").labels?.[0].textContent).toBe("E-mailadres");
  expect(field("name").autocomplete).toBe("name");
  expect(field("email").autocomplete).toBe("email");
  expect(field("email").type).toBe("email");
  expect(field("email").inputMode).toBe("email");
  expect([...host.querySelectorAll("button")].some(button => button.textContent === "Feedback melden")).toBe(true);
});

function privacyButton() { return [...host.querySelectorAll<HTMLButtonElement>("button")].find(button => button.textContent === "Privacyverklaring")!; }
it.each([true, false])("opens privacy outside the switch label preserving invalid drafts (auto_report=%s)", async (autoReport) => {
  const setAutoReport = vi.fn(initial.setAutoReport);
  const setIdentity = vi.fn(initial.setIdentity);
  await act(async () => useSupportStore.setState({ setAutoReport, setIdentity, auto_report: autoReport }));
  await fill("email", "jan@");
  expect(privacyButton().type).toBe("button");
  expect(privacyButton().closest("label")).toBeNull();
  expect(privacyButton().disabled).toBe(false);
  await act(async () => privacyButton().click());
  expect(open).toHaveBeenCalledExactlyOnceWith(PRIVACY_URL);
  expect(setAutoReport).not.toHaveBeenCalled();
  expect(setIdentity).not.toHaveBeenCalled();
  expect(useSupportStore.getState()).toMatchObject({ auto_report: autoReport, name: "Jan", email: "jan@example.nl" });
  expect(field("email").value).toBe("jan@");
});
it("preserves contact blur saving when focus moves to the privacy button", async () => {
  await fill("name", "  Jan Nieuw  ");
  await act(async () => field("name").focus());
  await act(async () => privacyButton().focus());
  await act(async () => privacyButton().click());
  expect(open).toHaveBeenCalledExactlyOnceWith(PRIVACY_URL);
  expect(useSupportStore.getState()).toMatchObject({ auto_report: true, name: "Jan Nieuw", email: "jan@example.nl" });
  expect(field("name").value).toBe("Jan Nieuw");
});
it.each([true, false])("handles rejected privacy open and retry (auto_report=%s)", async (autoReport) => {
  const setAutoReport = vi.fn(initial.setAutoReport);
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
});

it("holds oversized drafts and saves once both contacts are corrected", async () => {
  await fill("name", "n".repeat(201)); await blur("name");
  expect(field("name").value).toHaveLength(201);
  expect(useSupportStore.getState().name).toBe("Jan");
  await fill("email", "a".repeat(315) + "@b.com"); await blur("email");
  expect(useSupportStore.getState().email).toBe("jan@example.nl");
  await fill("name", "n".repeat(200)); await blur("name");
  expect(useSupportStore.getState().name).toBe("Jan");
  await fill("email", "a".repeat(314) + "@b.com"); await blur("email");
  expect(useSupportStore.getState().name).toHaveLength(200);
  expect(useSupportStore.getState().email).toHaveLength(320);
});
