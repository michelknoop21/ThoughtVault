import { create } from "zustand";
import type { RecordingMode, TranscriptTask } from "../types";

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

  // Background processing: tasks that are uploading/processing while user can start new recordings
  backgroundTasks: TranscriptTask[];

  setMode: (mode: RecordingMode) => void;
  setPhase: (phase: RecordingPhase) => void;
  setCurrentTask: (task: TranscriptTask | null) => void;
  setAudioLevel: (level: number) => void;
  setElapsedSeconds: (seconds: number) => void;
  setFilePath: (path: string | null) => void;
  setAutoStart: (value: boolean) => void;
  addBackgroundTask: (task: TranscriptTask) => void;
  updateBackgroundTask: (taskId: string, update: Partial<TranscriptTask>) => void;
  removeBackgroundTask: (taskId: string) => void;
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
  backgroundTasks: [],
  setMode: (mode) => set({ mode }),
  setPhase: (phase) => set({ phase }),
  setCurrentTask: (task) => set({ currentTask: task }),
  setAudioLevel: (level) => set({ audioLevel: level }),
  setElapsedSeconds: (seconds) => set({ elapsedSeconds: seconds }),
  setFilePath: (path) => set({ filePath: path }),
  setAutoStart: (value) => set({ autoStart: value }),
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
  reset: () =>
    set({
      phase: "idle",
      currentTask: null,
      audioLevel: 0,
      elapsedSeconds: 0,
      filePath: null,
      autoStart: false,
    }),
}));
