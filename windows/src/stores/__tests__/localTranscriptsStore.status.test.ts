import { expect, it, vi } from "vitest";
import { Store } from "@tauri-apps/plugin-store";
import { useLocalTranscriptsStore } from "../localTranscriptsStore";

it("repairs persisted note status before exposing a regenerated local record", async () => {
  const existing = { id: "local-partial", title: "Test", notule_html: "<p>Eigen opgeslagen notulen.</p>",
    raw_transcription: "Eigen transcriptie", has_notes: false, tags: [], duration_seconds: 9.7598125,
    created_at: "2026-10-14T10:25:42.360Z", updated_at: "2026-10-15T08:07:00Z" };
  const set = vi.fn(), save = vi.fn();
  vi.spyOn(Store, "load").mockResolvedValue({ get: vi.fn().mockResolvedValue([existing]), set, save } as unknown as Store);
  await useLocalTranscriptsStore.getState().hydrate();
  expect(useLocalTranscriptsStore.getState().items).toEqual([{ ...existing, has_notes: true }]);
  expect(set).toHaveBeenCalledWith("items", [{ ...existing, has_notes: true }]);
  expect(save).toHaveBeenCalledOnce();
});
