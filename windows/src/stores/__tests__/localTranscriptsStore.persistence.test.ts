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
