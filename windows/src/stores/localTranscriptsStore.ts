import { create } from "zustand";
import { Store } from "@tauri-apps/plugin-store";
import type { Transcript } from "../types";

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
  hydrate: () => Promise<void>;
  add: (t: Transcript) => Promise<void>;
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
        set({ items });
      })().catch((error) => {
        loadPromise = null;
        throw error;
      });
    }
    await loadPromise;
  }

  function persist(change: (items: Transcript[]) => Transcript[]): Promise<void> {
    const operation = writeQueue.then(async () => {
      await hydrate();
      const items = change(get().items);
      await diskStore!.set("items", items);
      await diskStore!.save();
      set({ items });
    });
    writeQueue = operation.catch(() => {});
    return operation;
  }

  return {
    items: [],
    hydrate,
    add: (t) => persist((items) => [t, ...items.filter((item) => item.id !== t.id)]),
    update: (id, patch) => persist((items) => items.map((item) => item.id === id ? { ...item, ...patch } : item)),
    remove: (id) => persist((items) => items.filter((item) => item.id !== id)),
  };
});
