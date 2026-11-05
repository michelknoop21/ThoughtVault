import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import { validateCorrections, upsertCorrection, type CorrectionDocument, type PersonalCorrection } from "../services/personalCorrections";
interface State {
  entries: PersonalCorrection[];
  hydrate: () => Promise<void>;
  save: (entry: PersonalCorrection) => Promise<void>;
  remove: (id: string) => Promise<void>;
}
let loaded = false;
let loading: Promise<void> | undefined;
let queue = Promise.resolve();
export const usePersonalCorrectionsStore = create<State>((set,get) => {
  async function hydrate() {
    if (loaded) return;
    if (!loading) loading = (async () => {
      const document = await invoke<CorrectionDocument | null>("load_personal_corrections") ?? { version: 1, entries: [] };
      validateCorrections(document);
      set({ entries: document.entries }); loaded = true;
    })().catch(error => { loading = undefined; throw error; });
    await loading;
  }
  function change(update: (entries: PersonalCorrection[]) => PersonalCorrection[]) {
    const operation = queue.then(async () => {
      await hydrate();
      const document: CorrectionDocument = { version: 1, entries: update(get().entries) };
      validateCorrections(document);
      await invoke("save_personal_corrections", { document });
      set({ entries: document.entries });
    });
    queue = operation.catch(() => {}); return operation;
  }
  return { entries: [], hydrate, save: entry => change(entries => upsertCorrection(entries,entry)), remove: id => change(entries => entries.filter(e => e.id !== id)) };
});
