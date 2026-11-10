import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import { validateCorrections, upsertCorrection, type CorrectionDocument, type PersonalCorrection } from "../services/personalCorrections";
import { record, type HistoryEntry } from "../services/contextHistory";
interface State {
  entries: PersonalCorrection[];
  /** Rejected suggestion keys (CorrectionDocument.dismissed). */
  dismissed: string[];
  hydrate: () => Promise<void>;
  /** Upserts and saves; the stored version it replaces is kept in ContextHistory under `source`. */
  save: (entry: PersonalCorrection, source?: string) => Promise<PersonalCorrection[]>;
  /** Removes an entry; its last state is kept in ContextHistory so `restore` can bring it back. */
  remove: (id: string, source?: string) => Promise<void>;
  /** Puts an earlier version of an entry back as a new version. */
  restore: (entry: HistoryEntry) => Promise<void>;
  /** Remembers a rejected suggestion so it is not offered again. Entries are kept. */
  addDismissed: (key: string) => Promise<void>;
}
type Change = { entries: PersonalCorrection[]; dismissed?: string[]; history?: PersonalCorrection[] };
const comparable = (e: PersonalCorrection) => JSON.stringify([e.id, e.canonical, e.variants, e.scope, e.enabled, e.note ?? null]);
let loaded = false;
let loading: Promise<void> | undefined;
let queue: Promise<unknown> = Promise.resolve();
export const usePersonalCorrectionsStore = create<State>((set,get) => {
  async function hydrate() {
    if (loaded) return;
    if (!loading) loading = (async () => {
      const document = await invoke<CorrectionDocument | null>("load_personal_corrections") ?? { version: 2, entries: [] };
      validateCorrections(document);
      set({ entries: document.entries, dismissed: document.dismissed ?? [] }); loaded = true;
    })().catch(error => { loading = undefined; throw error; });
    await loading;
  }
  /** Serial read-modify-write; `history` lists old versions recorded before the file is written. */
  function change(update: (state: State) => Change, source = "handmatig") {
    const operation = queue.then(async () => {
      await hydrate();
      const next = update(get());
      const document: CorrectionDocument = { version: 2, entries: next.entries, dismissed: next.dismissed ?? get().dismissed };
      validateCorrections(document);
      for (const old of next.history ?? []) await record("term", old.id, source, old);
      await invoke("save_personal_corrections", { document });
      set({ entries: document.entries, dismissed: document.dismissed });
      return document.entries;
    });
    queue = operation.catch(() => {}); return operation;
  }
  const save = (entry: PersonalCorrection, source = "handmatig") => change(({ entries }) => {
    const next = upsertCorrection(entries, entry);
    // upsert appends the saved entry last and may merge into an existing entry with the same term; record both old versions.
    const saved = next[next.length - 1];
    return { entries: next, history: entries.filter(old => (old.id === entry.id || old.id === saved.id) && comparable(old) !== comparable(saved)) };
  }, source);
  return {
    entries: [], dismissed: [], hydrate, save,
    remove: async (id, source = "handmatig") => {
      await change(({ entries }) => ({ entries: entries.filter(e => e.id !== id), history: entries.filter(e => e.id === id) }), source);
    },
    restore: async entry => { await save(JSON.parse(entry.snapshotJSON) as PersonalCorrection, "herstel"); },
    addDismissed: async key => {
      await change(({ entries, dismissed }) => ({ entries, dismissed: dismissed.includes(key) ? dismissed : [...dismissed, key] }));
    },
  };
});

/** For the minutes path: an unreadable glossary (e.g. a newer file version) must not block the minutes. */
export async function loadCorrectionsOrEmpty(): Promise<PersonalCorrection[]> {
  try {
    await usePersonalCorrectionsStore.getState().hydrate();
    return usePersonalCorrectionsStore.getState().entries;
  } catch (error) {
    console.warn("[PersonalCorrections] Woordenlijst onleesbaar, notule gaat verder zonder:", error instanceof Error ? error.message : String(error));
    return [];
  }
}
