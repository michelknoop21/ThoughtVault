import { expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import FeedbackWidget from "../FeedbackWidget";
import { useSettingsStore } from "../../stores/settingsStore";
import { api } from "../../services/api";
vi.mock("../../services/api", () => ({ api: { getUnreadFeedbackCount: vi.fn(), submitFeedback: vi.fn() } }));
it("copies local feedback without a server call and preserves the draft after clipboard failure", async () => {
  useSettingsStore.setState({ processing_mode: "local" });
  const writeText = vi.fn().mockRejectedValueOnce(new Error("Clipboard unavailable")).mockResolvedValue(undefined);
  Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
  const container = document.createElement("div"); document.body.append(container);
  const root = createRoot(container);
  await act(async () => root.render(<FeedbackWidget />));
  await act(async () => container.querySelector<HTMLButtonElement>('[aria-label="Feedback openen"]')!.click());
  function fill(element: HTMLInputElement | HTMLTextAreaElement, value: string) {
    const prototype = element instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
    Object.getOwnPropertyDescriptor(prototype, "value")!.set!.call(element, value);
    element.dispatchEvent(new Event("input", { bubbles: true }));
  }
  await act(async () => {
    fill(container.querySelector("input")!, " Test ");
    fill(container.querySelector("textarea")!, " Synthetic feedback ");
  });
  const copy = [...container.querySelectorAll("button")].find(b => b.textContent === "Kopieer feedback")!;
  await act(async () => copy.click());
  expect(container.querySelector("textarea")?.value).toBe(" Synthetic feedback ");
  await act(async () => copy.click());
  expect(writeText).toHaveBeenLastCalledWith("ThoughtVault feedback\nTest\n\nSynthetic feedback");
  expect(api.submitFeedback).not.toHaveBeenCalled();
  expect(api.getUnreadFeedbackCount).not.toHaveBeenCalled();
  expect(container.querySelector("dialog")).toBeNull();
  await act(async () => root.unmount()); container.remove();
});
