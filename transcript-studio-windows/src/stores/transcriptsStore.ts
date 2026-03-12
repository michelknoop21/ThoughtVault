import { create } from "zustand";
import type { Transcript, TranscriptTask } from "../types";

interface TranscriptsState {
  transcripts: Transcript[];
  activeTasks: TranscriptTask[];
  selectedId: string | null;
  searchQuery: string;
  selectedTags: string[];
  isLoading: boolean;
  setTranscripts: (transcripts: Transcript[]) => void;
  addTranscript: (transcript: Transcript) => void;
  updateTranscript: (id: string, updates: Partial<Transcript>) => void;
  deleteTranscript: (id: string) => void;
  setActiveTasks: (tasks: TranscriptTask[]) => void;
  updateTask: (taskId: string, updates: Partial<TranscriptTask>) => void;
  removeTask: (taskId: string) => void;
  setSelectedId: (id: string | null) => void;
  setSearchQuery: (query: string) => void;
  setSelectedTags: (tags: string[]) => void;
  setIsLoading: (loading: boolean) => void;
}

export const useTranscriptsStore = create<TranscriptsState>()((set) => ({
  transcripts: [],
  activeTasks: [],
  selectedId: null,
  searchQuery: "",
  selectedTags: [],
  isLoading: false,
  setTranscripts: (transcripts) => set({ transcripts }),
  addTranscript: (transcript) =>
    set((state) => ({
      transcripts: state.transcripts.some((t) => t.id === transcript.id)
        ? state.transcripts
        : [transcript, ...state.transcripts],
    })),
  updateTranscript: (id, updates) =>
    set((state) => ({
      transcripts: state.transcripts.map((t) =>
        t.id === id ? { ...t, ...updates } : t
      ),
    })),
  deleteTranscript: (id) =>
    set((state) => ({
      transcripts: state.transcripts.filter((t) => t.id !== id),
      selectedId: state.selectedId === id ? null : state.selectedId,
    })),
  setActiveTasks: (tasks) => set({ activeTasks: tasks }),
  updateTask: (taskId, updates) =>
    set((state) => ({
      activeTasks: state.activeTasks.map((t) =>
        t.task_id === taskId ? { ...t, ...updates } : t
      ),
    })),
  removeTask: (taskId) =>
    set((state) => ({
      activeTasks: state.activeTasks.filter((t) => t.task_id !== taskId),
    })),
  setSelectedId: (id) => set({ selectedId: id }),
  setSearchQuery: (query) => set({ searchQuery: query }),
  setSelectedTags: (tags) => set({ selectedTags: tags }),
  setIsLoading: (loading) => set({ isLoading: loading }),
}));
