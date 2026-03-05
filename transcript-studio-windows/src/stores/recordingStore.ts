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
  setMode: (mode: RecordingMode) => void;
  setPhase: (phase: RecordingPhase) => void;
  setCurrentTask: (task: TranscriptTask | null) => void;
  setAudioLevel: (level: number) => void;
  setElapsedSeconds: (seconds: number) => void;
  setFilePath: (path: string | null) => void;
  setAutoStart: (value: boolean) => void;
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
  setMode: (mode) => set({ mode }),
  setPhase: (phase) => set({ phase }),
  setCurrentTask: (task) => set({ currentTask: task }),
  setAudioLevel: (level) => set({ audioLevel: level }),
  setElapsedSeconds: (seconds) => set({ elapsedSeconds: seconds }),
  setFilePath: (path) => set({ filePath: path }),
  setAutoStart: (value) => set({ autoStart: value }),
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
