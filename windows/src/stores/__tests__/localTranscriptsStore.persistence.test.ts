import { beforeEach, expect, it, vi } from "vitest";
import { Store } from "@tauri-apps/plugin-store";
import { useLocalTranscriptsStore } from "../localTranscriptsStore";
import type { Transcript } from "../../types";

const note: Transcript = {
  id: "local-persist", title: "Oorspronkelijk", raw_transcription: "Besproken planning",
  notule_html: "<p>Planning besproken</p>", duration_seconds: 12, tags: [],
  created_at: "2026-09-29T10:00:00Z", updated_at: "2026-09-29T10:00:00Z",
};

beforeEach(() => {
  localStorage.clear();
  useLocalTranscriptsStore.setState({ items: [] });
});

it("keeps the edited note and reports failure when disk save fails", async () => {
  const save = vi.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("disk full"));
  vi.spyOn(Store, "load").mockResolvedValue({
    get: vi.fn().mockResolvedValue([]), set: vi.fn(), save,
  } as unknown as Store);

  await useLocalTranscriptsStore.getState().hydrate();
  await useLocalTranscriptsStore.getState().add(note);
  await expect(useLocalTranscriptsStore.getState().update(note.id, { title: "Gewijzigd" }))
    .rejects.toThrow("disk full");
  expect(useLocalTranscriptsStore.getState().items[0].title).toBe("Oorspronkelijk");
});

it("reopens the same corrected title, note and transcript", async () => {
  const { correctRecording } = await import("../../services/personalCorrections");
  const original = { ...note, title: "A-E-oplossingen", notule_html: "<p>A–E werkt.</p>", raw_transcription: "A-E modellen." };
  let disk = [original];
  vi.spyOn(Store, "load").mockImplementation(async () => ({
    get: vi.fn(async () => structuredClone(disk)),
    set: vi.fn(async (_key, value) => { disk = structuredClone(value); }), save: vi.fn(),
  } as unknown as Store));
  vi.resetModules();
  const first = (await import("../localTranscriptsStore")).useLocalTranscriptsStore;
  await first.getState().hydrate();
  const corrected = correctRecording({ id: "ai", canonical: "AI", variants: ["A-E"], enabled: true, scope: null }, original.notule_html, original.raw_transcription, original.title);
  await first.getState().update(original.id, { title: corrected.title, notule_html: corrected.notule, raw_transcription: corrected.transcript });
  vi.resetModules();
  const reopened = (await import("../localTranscriptsStore")).useLocalTranscriptsStore;
  await reopened.getState().hydrate();
  expect(reopened.getState().items[0]).toMatchObject({ title: "AI-oplossingen", notule_html: "<p>AI werkt.</p>", raw_transcription: "AI modellen." });
});
