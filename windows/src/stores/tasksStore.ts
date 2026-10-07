import { create } from "zustand";
import type { TranscriptTask } from "../types";
import { api } from "../services/api";
import { useSettingsStore } from "./settingsStore";

interface TasksState {
  activeTasks: TranscriptTask[];
  isLoading: boolean;
  error: string | null;

  loadActiveTasks: () => Promise<void>;
  cancelTask: (taskId: string) => Promise<void>;
  deleteTask: (taskId: string) => Promise<void>;
  startAutoRefresh: () => void;
  stopAutoRefresh: () => void;
}

// Internal timer ref — lives outside Zustand (not serializable)
let refreshInterval: ReturnType<typeof setInterval> | null = null;

export const useTasksStore = create<TasksState>()((set, get) => ({
  activeTasks: [],
  isLoading: false,
  error: null,

  loadActiveTasks: async () => {
    // Local mode has no server-side tasks — never call the backend.
    if (useSettingsStore.getState().processing_mode === "local") {
      set({ activeTasks: [], isLoading: false, error: null });
      return;
    }
    set({ isLoading: true, error: null });
    try {
      const tasks = await api.getActiveTasks();
      set({ activeTasks: tasks, isLoading: false });
    } catch (err) {
      set({
        error: err instanceof Error ? err.message : "Onbekende fout",
        isLoading: false,
      });
    }
  },

  cancelTask: async (taskId) => {
    try {
      await api.cancelTask(taskId);
      await get().loadActiveTasks();
    } catch (err) {
      set({
        error: err instanceof Error ? err.message : "Annuleren mislukt",
      });
    }
  },

  deleteTask: async (taskId) => {
    try {
      await api.deleteTask(taskId);
      set((state) => ({
        activeTasks: state.activeTasks.filter((t) => t.task_id !== taskId),
      }));
    } catch (err) {
      set({
        error: err instanceof Error ? err.message : "Verwijderen mislukt",
      });
    }
  },

  startAutoRefresh: () => {
    get().stopAutoRefresh();
    // No polling in local mode — there are no server tasks to refresh.
    if (useSettingsStore.getState().processing_mode === "local") {
      get().loadActiveTasks();
      return;
    }
    get().loadActiveTasks();
    refreshInterval = setInterval(() => get().loadActiveTasks(), 10_000);
  },

  stopAutoRefresh: () => {
    if (refreshInterval) {
      clearInterval(refreshInterval);
      refreshInterval = null;
    }
  },
}));
