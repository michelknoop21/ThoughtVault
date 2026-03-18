import { create } from "zustand";
import type { QueuedUpload } from "../types";

interface PermanentlyFailedItem {
  id: string;
  fileName: string;
}

interface UploadQueueState {
  currentItem: QueuedUpload | null;
  progress: number; // 0-100
  uploadSpeed: number; // bytes/sec
  items: QueuedUpload[];
  permanentlyFailed: PermanentlyFailedItem[];
  startItem: (item: QueuedUpload) => void;
  updateProgress: (fraction: number) => void;
  finishItem: () => void;
  setItems: (items: QueuedUpload[]) => void;
  addPermanentlyFailed: (item: PermanentlyFailedItem) => void;
  clearPermanentlyFailed: () => void;
  reset: () => void;
}

export const useUploadQueueStore = create<UploadQueueState>()((set, get) => {
  let lastProgressTime = 0;
  let lastProgressBytes = 0;

  return {
    currentItem: null,
    progress: 0,
    uploadSpeed: 0,
    items: [],
    permanentlyFailed: [],
    startItem: (item) => {
      lastProgressTime = Date.now();
      lastProgressBytes = 0;
      set({ currentItem: item, progress: 0, uploadSpeed: 0 });
    },
    updateProgress: (fraction) => {
      const item = get().currentItem;
      const now = Date.now();
      const elapsed = (now - lastProgressTime) / 1000;

      let speed = get().uploadSpeed;
      if (elapsed > 0.5 && item?.file_size_bytes) {
        const currentBytes = fraction * item.file_size_bytes;
        const deltaBytes = currentBytes - lastProgressBytes;
        speed = deltaBytes / elapsed;
        lastProgressTime = now;
        lastProgressBytes = currentBytes;
      }

      set({ progress: Math.round(fraction * 100), uploadSpeed: speed });
    },
    finishItem: () => {
      set({ currentItem: null, progress: 0, uploadSpeed: 0 });
    },
    setItems: (items) => set({ items }),
    addPermanentlyFailed: (item) =>
      set((state) => ({ permanentlyFailed: [...state.permanentlyFailed, item] })),
    clearPermanentlyFailed: () => set({ permanentlyFailed: [] }),
    reset: () => set({ currentItem: null, progress: 0, uploadSpeed: 0, items: [], permanentlyFailed: [] }),
  };
});
