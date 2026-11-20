import { beforeEach, expect, it, vi } from "vitest";
import { Store } from "@tauri-apps/plugin-store";
import { LLMService } from "../llm";
import { cancelLabeling, labelAutomatically, useLabelingProgress } from "../automaticLabels";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import type { Transcript } from "../../types";
const label = { id: "a", name: "Project", kind: "label" as const, description: "Projectwerk", automatic: true, labelIDs: [] };
const note = { id: "local-a", title: "Besluit", notule_html: "<p>Inhoud</p>", tags: ["Handmatig"] } as Transcript;
beforeEach(async () => {
  vi.restoreAllMocks();
  vi.spyOn(Store, "load").mockResolvedValue({ get: vi.fn().mockResolvedValue([]), set: vi.fn(), save: vi.fn() } as unknown as Store);
  await useLocalTranscriptsStore.getState().hydrate();
  useLocalTranscriptsStore.setState({ items: [note, { ...note, id: "local-b" }], library: [label] });
});
it("leaves the note intact on provider failure and retries", async () => {
  vi.spyOn(LLMService, "complete").mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce('["a"]');
  await labelAutomatically([note.id]);
  const failed = useLocalTranscriptsStore.getState().items[0];
  expect(failed.tags).toEqual(note.tags);
  expect(failed.notule_html).toBe(note.notule_html);
  expect(failed.auto_label_error).toBe("offline");
  await labelAutomatically([note.id]);
  expect(useLocalTranscriptsStore.getState().items[0].tags).toEqual(["Handmatig", "Project"]);
  expect(useLocalTranscriptsStore.getState().items[0].auto_label_error).toBeUndefined();
});
it("cancels between notes, retaining committed results and ignoring an in-flight result", async () => {
  let release!: (value: string) => void;
  let started!: () => void;
  const waiting = new Promise<void>(resolve => { started = resolve; });
  vi.spyOn(LLMService, "complete").mockResolvedValueOnce('["a"]').mockImplementationOnce(() => { started(); return new Promise(resolve => { release = resolve; }); });
  const run = labelAutomatically(["local-a", "local-b"]);
  await waiting;
  cancelLabeling(); release('["a"]'); await run;
  expect(useLocalTranscriptsStore.getState().items[0].tags).toContain("Project");
  expect(useLocalTranscriptsStore.getState().items[1].tags).toEqual(["Handmatig"]);
  expect(useLabelingProgress.getState().busy).toBe(false);
});
it("does not apply a result to edited or deleted content", async () => {
  vi.spyOn(LLMService, "complete").mockImplementation(async () => {
    await useLocalTranscriptsStore.getState().update(note.id, { title: "Gewijzigd" });
    return '["a"]';
  });
  await labelAutomatically([note.id]);
  expect(useLocalTranscriptsStore.getState().items[0].tags).toEqual(["Handmatig"]);
});
it("rejects invented labels and skips drafts", async () => {
  const call = vi.spyOn(LLMService, "complete").mockResolvedValue('["invented"]');
  await labelAutomatically([note.id]);
  expect(useLocalTranscriptsStore.getState().items[0].tags).toEqual(note.tags);
  expect(useLocalTranscriptsStore.getState().items[0].auto_label_error).toContain("ongeldige");
  useLocalTranscriptsStore.setState({ items: [{ ...note, notule_draft_html: "Draft" }] });
  await labelAutomatically([note.id]);
  expect(call).toHaveBeenCalledTimes(1);
});
