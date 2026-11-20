import {standardBranding} from "../../../shared/document/dist/document.mjs";
import {useBrandingStore} from "./brandingStore";
import { create } from "zustand";
import { Store } from "@tauri-apps/plugin-store";
import type { Transcript } from "../types";

import { manualTags, metadata, applyLabels, validateLibrary, type LibraryEntry } from "../services/libraryOrganization";

const LOCAL_PREFIX = "local-";
const LEGACY_KEY = "local-transcripts-store";
const STORE_FILE = "local-transcripts.json";

export function isLocalId(id: string): boolean {
  return id.startsWith(LOCAL_PREFIX);
}

export function newLocalId(): string {
  return `${LOCAL_PREFIX}${crypto.randomUUID()}`;
}

interface LocalTranscriptsState {
  items: Transcript[];
  library: LibraryEntry[];
  saveEntry: (entry: LibraryEntry) => Promise<void>;
  removeEntry: (id: string) => Promise<void>;
  move: (ids: string[], folderID?: string) => Promise<void>;
  applyLabels: (id: string, html: string, title: string, chosen: string[], eligible: LibraryEntry[]) => Promise<void>;
  hydrate: () => Promise<void>;
  add: (t: Transcript) => Promise<Transcript>;
  update: (id: string, patch: Partial<Transcript>) => Promise<void>;
  remove: (id: string) => Promise<void>;
}

let diskStore: Store | null = null;
let loadPromise: Promise<void> | null = null;
let writeQueue: Promise<void> = Promise.resolve();

export const useLocalTranscriptsStore = create<LocalTranscriptsState>()((set, get) => {
  async function hydrate() {
    if (diskStore) return;
    if (!loadPromise) {
      loadPromise = (async () => {
        const store = await Store.load(STORE_FILE, { defaults: { items: [] }, autoSave: false });
        let items = await store.get<Transcript[]>("items") ?? [];
        const library = validateLibrary(await store.get<unknown>("library") ?? []);
        const legacy = localStorage.getItem(LEGACY_KEY);
        let migrated = false;
        if (legacy) {
          const oldItems = (JSON.parse(legacy) as { state?: { items?: Transcript[] } }).state?.items ?? [];
          if (oldItems.length > 0) {
            const ids = new Set(items.map((item) => item.id));
            items = [...items, ...oldItems.filter((item) => !ids.has(item.id))];
            migrated = true;
          }
        }
        // Older regenerate/edit paths saved HTML without updating the presence flag.
        const repaired = items.map((item) => typeof item.notule_html === "string"
          && item.has_notes !== !!item.notule_html.trim()
          ? { ...item, has_notes: !!item.notule_html.trim() } : item);
        if (migrated || repaired.some((item, index) => item !== items[index])) {
          await store.set("items", repaired);
          await store.save();
          items = repaired;
        }
        if (legacy) localStorage.removeItem(LEGACY_KEY);
        diskStore = store;
        set({ items, library });
      })().catch((error) => {
        loadPromise = null;
        throw error;
      });
    }
    await loadPromise;
  }

  function persist(change: (items: Transcript[]) => Transcript[], libraryChange?: (entries: LibraryEntry[]) => LibraryEntry[]): Promise<void> {
    const operation = writeQueue.then(async () => {
      await hydrate();
      const items = change(get().items);
      const library = libraryChange ? libraryChange(get().library) : get().library;
      try {
        await diskStore!.set("items", items);
        await diskStore!.set("library", library);
        await diskStore!.save();
      } catch (error) {
        await diskStore!.set("items", get().items);
        await diskStore!.set("library", get().library);
        throw error;
      }
      set({ items, library });
    });
    writeQueue = operation.catch(() => {});
    return operation;
  }

  return {
    items: [],
    library: [],
    hydrate,
    saveEntry: (entry) => {
      if (!entry.name.trim() || (entry.kind === "smart" && !entry.labelIDs.length)) return Promise.reject(new Error("Vul een naam en minstens één label voor een slimme map in."));
      return persist(items => items, entries => {
        if (entry.kind === "label" && entries.some(e => e.kind === "label" && e.id !== entry.id && e.name === entry.name.trim())) throw new Error("Dit label bestaat al.");
        return validateLibrary([...entries.filter(e => e.id !== entry.id), { ...entry, name: entry.name.trim() }]);
      });
    },
    removeEntry: id => persist(items => items, entries => entries.filter(e => e.id !== id)),
    move: (ids, folderID) => persist(items => {
      if (folderID && !get().library.some(e => e.kind === "folder" && e.id === folderID)) throw new Error("Map niet gevonden.");
      if (ids.some(id => !items.some(t => t.id === id))) throw new Error("Notule niet gevonden in lokale opslag.");
      return items.map(t => ids.includes(t.id) ? { ...t, organization: { ...metadata(t), folderID } } : t);
    }),
    applyLabels: (id, html, title, chosen, eligible) => persist(items => items.map(t =>
      t.id === id && t.notule_html === html && t.title === title ? applyLabels(t, chosen, eligible, get().library) : t)),
    add: async (t) => {
      await useBrandingStore.getState().hydrate();
      const {library}=useBrandingStore.getState();
      const style=library.styles.find(b=>b.id===library.defaultId);
      await persist((items) => {
        const existing=items.find(item=>item.id===t.id);
        const snapshot=existing ? existing.document_branding_json : JSON.stringify(style ?? standardBranding());
        return [{...existing,...t,organization:t.organization ?? existing?.organization,document_branding_json:t.document_branding_json===undefined?snapshot:t.document_branding_json},...items.filter(item=>item.id!==t.id)];
      });
      if (t.notule_html && !t.notule_draft_html && get().library.some(e => e.automatic)) {
        void import("../services/automaticLabels").then(m => m.labelAutomatically([t.id]));
      }
      return get().items.find(item => item.id === t.id)!;
    },
    update: async (id, patch) => {
      let shouldLabel = false;
      await persist((items) => items.map((item) => {
        if (item.id !== id) return item;
        const updated = { ...item, ...patch };
        if (patch.tags) updated.organization = manualTags(item, patch.tags, get().library);
        shouldLabel = !!patch.notule_html && patch.notule_html !== item.notule_html && !updated.notule_draft_html
          && (!item.notule_html || patch.notule_draft_html === "");
        return updated;
      }));
      if (shouldLabel && get().library.some(e => e.automatic)) void import("../services/automaticLabels").then(m => m.labelAutomatically([id]));
    },
    remove: (id) => persist((items) => items.filter((item) => item.id !== id)),
  };
});
