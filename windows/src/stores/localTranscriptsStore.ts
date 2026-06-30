import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Transcript } from "../types";

// Persisted store of transcripts generated fully on-device (local mode). The
// macOS app uses SwiftData for this; on Windows we persist to localStorage.
// ponytail: localStorage (~5-10MB quota). Fine for a personal note archive;
// move to tauri-plugin-store (JSON file, no quota) if users hit the ceiling.

const LOCAL_PREFIX = "local-";

export function isLocalId(id: string): boolean {
  return id.startsWith(LOCAL_PREFIX);
}

export function newLocalId(): string {
  return `${LOCAL_PREFIX}${Date.now()}`;
}

interface LocalTranscriptsState {
  items: Transcript[];
  add: (t: Transcript) => void;
  update: (id: string, patch: Partial<Transcript>) => void;
  remove: (id: string) => void;
}

export const useLocalTranscriptsStore = create<LocalTranscriptsState>()(
  persist(
    (set) => ({
      items: [],
      add: (t) => set((s) => ({ items: [t, ...s.items.filter((x) => x.id !== t.id)] })),
      update: (id, patch) =>
        set((s) => ({ items: s.items.map((t) => (t.id === id ? { ...t, ...patch } : t)) })),
      remove: (id) => set((s) => ({ items: s.items.filter((t) => t.id !== id) })),
    }),
    { name: "local-transcripts-store" }
  )
);
