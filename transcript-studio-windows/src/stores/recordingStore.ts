import { create } from "zustand";
import type { RecordingMode, TranscriptTask } from "../types";

// AbortController registry — lives outside Zustand (not serializable)
const abortControllers = new Map<string, AbortController>();

export function registerAbortController(taskId: string, controller: AbortController) {
  abortControllers.set(taskId, controller);
}

export function unregisterAbortController(taskId: string) {
  abortControllers.delete(taskId);
}

type RecordingPhase =
  | "idle"
  | "preparing"
  | "recording"
  | "paused"
  | "stopping"
  | "uploading";

interface RecordingState {
  phase: RecordingPhase;
  mode: RecordingMode;
  currentTask: TranscriptTask | null;
  audioLevel: number; // 0-100
  elapsedSeconds: number;
  filePath: string | null;
  autoStart: boolean;
  minimizeOnAutoStart: boolean;

  // Timestamp-based timer: survives navigation between pages
  recordingStartedAt: number | null; // Date.now() when recording started
  pausedAt: number | null; // Date.now() when paused
  pausedDuration: number; // accumulated ms spent paused

  // Background processing: tasks that are uploading/processing while user can start new recordings
  backgroundTasks: TranscriptTask[];

  setMode: (mode: RecordingMode) => void;
  setPhase: (phase: RecordingPhase) => void;
  setCurrentTask: (task: TranscriptTask | null) => void;
  setAudioLevel: (level: number) => void;
  setElapsedSeconds: (seconds: number) => void;
  setFilePath: (path: string | null) => void;
  setAutoStart: (value: boolean) => void;
  setMinimizeOnAutoStart: (value: boolean) => void;
  startTimer: () => void;
  pauseTimer: () => void;
  resumeTimer: () => void;
  addBackgroundTask: (task: TranscriptTask) => void;
  updateBackgroundTask: (taskId: string, update: Partial<TranscriptTask>) => void;
  removeBackgroundTask: (taskId: string) => void;
  cancelBackgroundTask: (taskId: string) => void;
  reset: () => void;
}

export const useRecordingStore = create<RecordingState>()((set) => ({
  phase: "idle",
  mode: "combined",
  currentTask: null,
  audioLevel: 0,
  elapsedSeconds: 0,
  filePath: null,
  autoStart: false,
  minimizeOnAutoStart: false,
  recordingStartedAt: null,
  pausedAt: null,
  pausedDuration: 0,
  backgroundTasks: [],
  setMode: (mode) => set({ mode }),
  setPhase: (phase) => set({ phase }),
  setCurrentTask: (task) => set({ currentTask: task }),
  setAudioLevel: (level) => set({ audioLevel: level }),
  setElapsedSeconds: (seconds) => set({ elapsedSeconds: seconds }),
  setFilePath: (path) => set({ filePath: path }),
  setAutoStart: (value) => set({ autoStart: value }),
  setMinimizeOnAutoStart: (value) => set({ minimizeOnAutoStart: value }),
  startTimer: () =>
    set({ recordingStartedAt: Date.now(), pausedAt: null, pausedDuration: 0 }),
  pauseTimer: () =>
    set({ pausedAt: Date.now() }),
  resumeTimer: () =>
    set((state) => ({
      pausedAt: null,
      pausedDuration:
        state.pausedDuration + (state.pausedAt ? Date.now() - state.pausedAt : 0),
    })),
  addBackgroundTask: (task) =>
    set((state) => ({ backgroundTasks: [...state.backgroundTasks, task] })),
  updateBackgroundTask: (taskId, update) =>
    set((state) => ({
      backgroundTasks: state.backgroundTasks.map((t) =>
        t.task_id === taskId ? { ...t, ...update } : t
      ),
    })),
  removeBackgroundTask: (taskId) =>
    set((state) => ({
      backgroundTasks: state.backgroundTasks.filter((t) => t.task_id !== taskId),
    })),
  cancelBackgroundTask: (taskId) => {
    const controller = abortControllers.get(taskId);
    if (controller) {
      controller.abort();
      abortControllers.delete(taskId);
    }
    set((state) => ({
      backgroundTasks: state.backgroundTasks.filter((t) => t.task_id !== taskId),
    }));
  },
  reset: () =>
    set({
      phase: "idle",
      currentTask: null,
      audioLevel: 0,
      elapsedSeconds: 0,
      filePath: null,
      autoStart: false,
      minimizeOnAutoStart: false,
      recordingStartedAt: null,
      pausedAt: null,
      pausedDuration: 0,
    }),
}));
