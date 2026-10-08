import { act } from "react";
import { Store } from "@tauri-apps/plugin-store";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { TranscriptsPage } from "../TranscriptsPage";
import { api } from "../../services/api";
import { useSettingsStore } from "../../stores/settingsStore";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
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
