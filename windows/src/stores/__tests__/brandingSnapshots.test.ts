import { expect, it, vi } from "vitest";
import { Store } from "@tauri-apps/plugin-store";
import { blankBranding } from "../../../../shared/document/dist/document.mjs";
import { useBrandingStore } from "../brandingStore";
import { useLocalTranscriptsStore } from "../localTranscriptsStore";
import type { Transcript } from "../../types";

it("assigns only new notes the default and preserves snapshots across editing and library deletion", async () => {
  const files = new Map<string, Map<string, unknown>>();
  vi.spyOn(Store, "load").mockImplementation(async (file) => {
    const values = files.get(file) ?? new Map();
    files.set(file, values);
    return {
      get: async (key: string) => values.get(key),
      set: async (key: string, value: unknown) => {
        values.set(key, value);
      },
      save: async () => {},
    } as unknown as Store;
  });
  const note: Transcript = {
    id: "local-branded",
    title: "Test",
    notule_html: "<p>Besluit</p>",
    tags: [],
    duration_seconds: 0,
    created_at: "2026-11-17",
    updated_at: "2026-11-17",
  };
  const style = { ...blankBranding(), id: "company", name: "Company" };
  await useBrandingStore
    .getState()
    .save({ schemaVersion: 1, defaultId: style.id, styles: [style] });
  const saved = await useLocalTranscriptsStore.getState().add(note);
  const snapshot = saved.document_branding_json;
  expect(JSON.parse(snapshot!)).toMatchObject({ id: "company", revision: 1 });
  await useBrandingStore
    .getState()
    .save({ schemaVersion: 1, defaultId: null, styles: [] });
  await useLocalTranscriptsStore
    .getState()
    .update(note.id, { notule_html: "<p>Gewijzigd</p>" });
  await useLocalTranscriptsStore
    .getState()
    .add({ ...note, notule_html: "<p>Opnieuw gegenereerd</p>" });
  expect(
    useLocalTranscriptsStore.getState().items[0].document_branding_json,
  ).toBe(snapshot);
  const standard = await useLocalTranscriptsStore
    .getState()
    .add({ ...note, id: "local-default" });
  expect(JSON.parse(standard.document_branding_json!)).toMatchObject({
    id: "thoughtvault",
    revision: 1,
  });
  const legacy = await useLocalTranscriptsStore
    .getState()
    .add({ ...note, id: "local-old", document_branding_json: null });
  expect(legacy.document_branding_json).toBeNull();
});
