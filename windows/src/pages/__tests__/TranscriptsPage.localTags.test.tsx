import { act } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { TranscriptsPage } from "../TranscriptsPage";
import { api } from "../../services/api";
import { useSettingsStore } from "../../stores/settingsStore";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { LLMService } from "../../services/llm";
import * as obsidian from "../../services/obsidian";
import type { Transcript } from "../../types";

// React's input tracker needs the native setter before dispatching input.
function typeInto(input: HTMLInputElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
}

afterEach(() => {
  vi.restoreAllMocks();
  useSettingsStore.getState().updateSettings({ processing_mode: "cloud" });
  useLocalTranscriptsStore.setState({ items: [] });
  useTranscriptsStore.setState({ transcripts: [], selectedId: null });
  useRecordingStore.setState({ backgroundTasks: [] });
});

it("asks for a template before regeneration and shows the job on Taken", async () => {
  const note: Transcript = {
    id: "local-regenerate", title: "Overleg", raw_transcription: "We hebben de planning goedgekeurd.",
    notule_html: "<p>Oud</p>", duration_seconds: 12, profile_name: "Standaard", tags: [],
    created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  };
  useSettingsStore.getState().updateSettings({ processing_mode: "local" });
  useProfilesStore.setState({ profiles: [
    { id: "standard", name: "Standaard" }, { id: "decisions", name: "Besluiten" },
  ] });
  vi.spyOn(Store, "load").mockResolvedValue({
    get: vi.fn().mockResolvedValue([]), set: vi.fn(), save: vi.fn(),
  } as unknown as Store);
  await useLocalTranscriptsStore.getState().hydrate();
  await useLocalTranscriptsStore.getState().add(note);
  useTranscriptsStore.setState({ transcripts: [note], selectedId: note.id });
  const generate = vi.spyOn(LLMService, "generateNotulen").mockResolvedValue("<h1>Planning voor komend kwartaal</h1><p>De planning is door het team goedgekeurd.</p>");

  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<TranscriptsPage />); });
  await act(async () => { container.querySelector<HTMLButtonElement>('button[title="Notulen opnieuw genereren met AI"]')!.click(); });
  expect(generate).not.toHaveBeenCalled();
  const select = container.querySelector<HTMLSelectElement>(".td-overlay select")!;
  await act(async () => { select.value = "decisions"; select.dispatchEvent(new Event("change", { bubbles: true })); });
  await act(async () => { Array.from(container.querySelectorAll<HTMLButtonElement>(".td-overlay button"))
    .find((button) => button.textContent === "Regenereren")!.click(); });

  expect(generate).toHaveBeenCalledWith(note.raw_transcription, expect.objectContaining({ id: "decisions" }), expect.any(Function), [], undefined);
  expect(useRecordingStore.getState().backgroundTasks[0].status).toBe("completed");
  expect(useLocalTranscriptsStore.getState().items.find((item) => item.id === note.id)?.profile_name).toBe("Besluiten");
  await act(async () => { root.unmount(); });
});

it("acknowledges Obsidian metadata edits even when imported HTML is unchanged", async () => {
  const note: Transcript = {
    id: "local-obsidian", title: "Overleg", notule_html: "<p>Planning.</p>", duration_seconds: 12,
    tags: [], created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  };
  useSettingsStore.getState().updateSettings({ processing_mode: "local", obsidian_enabled: true });
  vi.spyOn(Store, "load").mockResolvedValue({
    get: vi.fn().mockResolvedValue([]), set: vi.fn(), save: vi.fn(),
  } as unknown as Store);
  await useLocalTranscriptsStore.getState().hydrate();
  await useLocalTranscriptsStore.getState().add(note);
  useTranscriptsStore.setState({ transcripts: [note], selectedId: note.id });
  vi.spyOn(obsidian, "importFromObsidian").mockResolvedValue({ html: note.notule_html!, markdown: "# Nieuwe metadata" });
  const acknowledge = vi.spyOn(obsidian, "acknowledgeObsidianImport");
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<TranscriptsPage />); });
  await act(async () => { container.querySelector<HTMLButtonElement>('button[title="Exporteren"]')!.click(); });
  await act(async () => { Array.from(container.querySelectorAll<HTMLButtonElement>(".td-export-item"))
    .find(button => button.textContent?.includes("Uit Obsidian"))!.click(); });
  expect(acknowledge).toHaveBeenCalledWith(note, "# Nieuwe metadata", note.notule_html);
  await act(async () => { root.unmount(); });
  useSettingsStore.getState().updateSettings({ obsidian_enabled: false });
});

it("adds a tag to a local note without a server request", async () => {
  const note: Transcript = {
    id: "local-note", title: "Overleg", raw_transcription: "We hebben een planning besproken.",
    notule_html: "<p>De planning is besproken.</p>", duration_seconds: 12,
    tags: [], created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  };
  useSettingsStore.getState().updateSettings({ processing_mode: "local" });
  vi.spyOn(Store, "load").mockResolvedValue({
    get: vi.fn().mockResolvedValue([]), set: vi.fn(), save: vi.fn(),
  } as unknown as Store);
  await useLocalTranscriptsStore.getState().hydrate();
  await useLocalTranscriptsStore.getState().add(note);
  useTranscriptsStore.setState({ transcripts: [note], selectedId: note.id });
  const serverTags = vi.spyOn(api, "updateTranscriptTags");
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<TranscriptsPage />); });
  await act(async () => { container.querySelector<HTMLButtonElement>('button[title="Tags beheren"]')!.click(); });
  const input = container.querySelector<HTMLInputElement>('input[placeholder="Nieuwe tag..."]')!;
  await act(async () => {
    typeInto(input, "prioriteit");
  });
  await act(async () => { container.querySelector<HTMLButtonElement>(".td-tags-add button")!.click(); });
  expect(useLocalTranscriptsStore.getState().items[0].tags).toContain("prioriteit");
  expect(serverTags).not.toHaveBeenCalled();
  await act(async () => { root.unmount(); });
});

it("prints a sanitized note inside the app without relying on a popup", async () => {
  const note: Transcript = { id: "local-print", title: "Overleg <test>", notule_html: '<p>Planning</p><script>alert(1)</script>',
    duration_seconds: 43.553, tags: [], created_at: new Date().toISOString(), updated_at: new Date().toISOString() };
  useSettingsStore.getState().updateSettings({ processing_mode: "local" });
  vi.spyOn(Store, "load").mockResolvedValue({ get: vi.fn().mockResolvedValue([]), set: vi.fn(), save: vi.fn() } as unknown as Store);
  await useLocalTranscriptsStore.getState().hydrate();
  await useLocalTranscriptsStore.getState().add(note);
  useTranscriptsStore.setState({ transcripts: [note], selectedId: note.id });
  const popup = vi.spyOn(window, "open");
  const container = document.createElement("div");
  const root = createRoot(container);
  await act(async () => { root.render(<TranscriptsPage />); });
  await act(async () => { container.querySelector<HTMLButtonElement>('button[title="Exporteren"]')!.click(); });
  await act(async () => { Array.from(container.querySelectorAll<HTMLButtonElement>(".td-export-item")).find(button => button.textContent?.includes("PDF"))!.click(); });
  const frame = document.querySelector<HTMLIFrameElement>('iframe[title="Notule afdrukken"]')!;
  expect(frame.srcdoc).toContain("Overleg &lt;test&gt;");
  expect(frame.srcdoc).toContain("43s");
  expect(frame.srcdoc).not.toContain("<script>");
  expect(popup).not.toHaveBeenCalled();
  const print = vi.spyOn(frame.contentWindow!, "print").mockImplementation(() => {});
  frame.dispatchEvent(new Event("load"));
  expect(print).toHaveBeenCalledOnce();
  vi.useFakeTimers();
  frame.contentWindow!.dispatchEvent(new Event("afterprint"));
  expect(frame.isConnected).toBe(true);
  vi.runOnlyPendingTimers();
  expect(frame.isConnected).toBe(false);
  vi.useRealTimers();
  await act(async () => { root.unmount(); });
});
