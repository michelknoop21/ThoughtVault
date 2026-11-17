import { create } from "zustand";
import { Store } from "@tauri-apps/plugin-store";
import {
  validateLibrary,
  type BrandingLibrary,
} from "../../../shared/document/dist/document.mjs";
const empty: BrandingLibrary = {
  schemaVersion: 1,
  defaultId: null,
  styles: [],
};
let disk: Store | undefined;
let loading: Promise<void> | undefined;
let queue: Promise<void> = Promise.resolve();
interface State {
  library: BrandingLibrary;
  hydrate: () => Promise<void>;
  save: (library: BrandingLibrary) => Promise<void>;
}
export const useBrandingStore = create<State>((set, get) => ({
  library: empty,
  hydrate: async () => {
    if (disk) return;
    if (!loading)
      loading = (async () => {
        const store = await Store.load("document-branding.json", {
          defaults: { library: empty },
          autoSave: false,
        });
        const library = validateLibrary((await store.get("library")) ?? empty);
        disk = store;
        set({ library });
      })().catch((e) => {
        loading = undefined;
        throw e;
      });
    await loading;
  },
  save: (value) => {
    const operation = queue.then(async () => {
      await get().hydrate();
      const library = validateLibrary(value);
      await disk!.set("library", library);
      await disk!.save();
      set({ library });
    });
    queue = operation.catch(() => {});
    return operation;
  },
}));
