import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AccountTab } from "../AccountTab";
import { useSupportStore } from "../../../stores/supportStore";

vi.mock("../../FeedbackWidget", () => ({ default: () => <button>Feedback melden</button> }));
let host: HTMLDivElement;
let root: Root;
const initial = useSupportStore.getState();
beforeEach(async () => {
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
it("restores invalid drafts without changing stored identity", async () => {
  await fill("email", "jan@"); await blur("email");
  expect(field("email").value).toBe("jan@example.nl");
  await fill("name", "  "); await blur("name");
  expect(field("name").value).toBe("Jan");
  expect(useSupportStore.getState()).toMatchObject({ name: "Jan", email: "jan@example.nl" });
});
it("requires the whole identity to be valid and uses associated labels and email hints", async () => {
  await fill("name", "Nieuw"); await fill("email", "jan@"); await blur("name");
  expect(useSupportStore.getState()).toMatchObject({ name: "Jan", email: "jan@example.nl" });
  expect(field("name").value).toBe("Jan");
  expect(field("email").value).toBe("jan@example.nl");
  expect(field("name").labels?.[0].textContent).toBe("Naam");
  expect(field("email").labels?.[0].textContent).toBe("E-mailadres");
  expect(field("name").autocomplete).toBe("name");
  expect(field("email").autocomplete).toBe("email");
  expect(field("email").type).toBe("email");
  expect(field("email").inputMode).toBe("email");
  expect(host.querySelectorAll("button")).toHaveLength(1);
});
