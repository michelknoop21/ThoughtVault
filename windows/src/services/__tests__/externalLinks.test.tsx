import { afterEach, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { open } from "@tauri-apps/plugin-shell";
import { externalLinkUrl, openNoteLink } from "../externalLinks";
import { useToast } from "../../components/ui/InfoBar";
vi.mock("@tauri-apps/plugin-shell", () => ({ open: vi.fn(async () => {}) }));
vi.mock("../../components/ui/InfoBar", () => ({ useToast: { getState: () => ({ show: mocks.show }) } }));
const mocks = vi.hoisted(() => ({ show: vi.fn() }));
afterEach(() => { vi.clearAllMocks(); });

it.each(["https://example.com/note?q=1#part", "http://example.com/", "mailto:support@prezent.nl?subject=Account%20verwijderen%20ThoughtVault"])("allows the explicit external scheme for %s", href => {
  expect(externalLinkUrl(href)).toBe(href);
});
it.each(["javascript:alert(1)", "data:text/html,private", "file:///secret", "transcript-studio://callback", "//example.com", "/notes", "#part", "https://user:password@example.com/", "https://example.com/\nprivate", "invalid"])("rejects untrusted external href %s", href => {
  expect(externalLinkUrl(href)).toBeNull();
});
it.each([0, 1])("opens nested anchor activation for button %s exactly once", async button => {
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<div onClick={openNoteLink} onAuxClick={openNoteLink}><a href="https://example.com/"><span>Link</span></a></div>));
  const event = new MouseEvent(button ? "auxclick" : "click", { bubbles: true, cancelable: true, button, detail: 0 });
  await act(async () => { host.querySelector("span")!.dispatchEvent(event); });
  expect(event.defaultPrevented).toBe(true);
  expect(open).toHaveBeenCalledExactlyOnceWith("https://example.com/");
  await act(async () => root.unmount());
});
it.each(["#section", "javascript:alert(1)"])("keeps fragment defaults and blocks unsafe schemes: %s", async href => {
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<div onClick={openNoteLink}><a href={href}>Link</a></div>));
  const event = new MouseEvent("click", { bubbles: true, cancelable: true });
  await act(async () => { host.querySelector("a")!.dispatchEvent(event); });
  expect(event.defaultPrevented).toBe(!href.startsWith("#"));
  expect(open).not.toHaveBeenCalled();
  await act(async () => root.unmount());
});
it("reports a fixed message when shell opening fails, without exposing the URL", async () => {
  vi.mocked(open).mockRejectedValueOnce(new Error("PRIVATE_SHELL_BODY"));
  const host = document.createElement("div");
  const root = createRoot(host);
  await act(async () => root.render(<a href="mailto:support@prezent.nl" onClick={openNoteLink}>Mail</a>));
  await act(async () => { host.querySelector("a")!.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true })); });
  expect(useToast.getState().show).toHaveBeenCalledExactlyOnceWith("Link openen mislukt", "error");
  await act(async () => root.unmount());
});
