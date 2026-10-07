import { expect, it, vi } from "vitest";
import { Store } from "@tauri-apps/plugin-store";
import { useLocalTranscriptsStore } from "../localTranscriptsStore";

it("moves existing local notes to the durable store before clearing the old copy", async () => {
  const oldNote = {
    id: "local-old", title: "Bestaande notule", raw_transcription: "Gesprek over planning",
    notule_html: "<p>Planning besproken</p>", tags: [], duration_seconds: 10,
    created_at: "2026-09-29T10:00:00Z", updated_at: "2026-09-29T10:00:00Z",
  };
  localStorage.setItem("local-transcripts-store", JSON.stringify({ state: { items: [oldNote] } }));
  const save = vi.fn().mockResolvedValue(undefined);
  vi.spyOn(Store, "load").mockResolvedValue({
    get: vi.fn().mockResolvedValue([]), set: vi.fn(), save,
  } as unknown as Store);

  await useLocalTranscriptsStore.getState().hydrate();
  expect(useLocalTranscriptsStore.getState().items.map((item) => item.id)).toEqual(["local-old"]);
  expect(save).toHaveBeenCalledOnce();
  expect(localStorage.getItem("local-transcripts-store")).toBeNull();
});
