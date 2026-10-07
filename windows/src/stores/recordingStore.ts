import { persist } from "zustand/middleware";
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
  updateInstalling: boolean;
  regenerationCount: number;
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

  // Calendar event attendee emails set when recording starts from a calendar event.
  // Read and cleared on recording stop to drive SeedReviewSheet (D-07/D-10).
  pendingSeedAttendees: string[];

  // Directory person IDs manually selected for the current recording (ad-hoc meetings
  // with no calendar link). Folded into the participant list on upload (D-B).
  selectedParticipantIds: string[];

  // Profile selection — persisted in store so global recording handler can access it
  selectedProfileId: string;
  usePremium: boolean;

  // YouTube transcription
  isYouTubeEnabled: boolean;
  youtubeURL: string;
  isSubmittingYouTube: boolean;
  youtubeError: string | null;
  youtubeProfileId: string;

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
  setPendingSeedAttendees: (emails: string[]) => void;
  clearPendingSeedAttendees: () => void;
  setSelectedParticipantIds: (ids: string[]) => void;
  setSelectedProfileId: (id: string) => void;
  setUsePremium: (value: boolean) => void;
  setYouTubeEnabled: (enabled: boolean) => void;
  setYouTubeURL: (url: string) => void;
  setSubmittingYouTube: (submitting: boolean) => void;
  setYouTubeError: (error: string | null) => void;
  setYouTubeProfileId: (id: string) => void;
  reset: () => void;
}

export const useRecordingStore = create<RecordingState>()(persist((set) => ({
  phase: "idle",
  updateInstalling: false,
  regenerationCount: 0,
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
  pendingSeedAttendees: [],
  selectedParticipantIds: [],
  selectedProfileId: "",
  usePremium: false,
  backgroundTasks: [],
  isYouTubeEnabled: false,
  youtubeURL: "",
  isSubmittingYouTube: false,
  youtubeError: null,
  youtubeProfileId: "",
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
    set((state) => ({ backgroundTasks: [...state.backgroundTasks.filter(t => t.task_id !== task.task_id), task] })),
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
  setPendingSeedAttendees: (emails) => set({ pendingSeedAttendees: emails }),
  clearPendingSeedAttendees: () => set({ pendingSeedAttendees: [] }),
  setSelectedParticipantIds: (ids) => set({ selectedParticipantIds: ids }),
  setSelectedProfileId: (id) => set({ selectedProfileId: id }),
  setUsePremium: (value) => set({ usePremium: value }),
  setYouTubeEnabled: (enabled) => set({ isYouTubeEnabled: enabled }),
  setYouTubeURL: (url) => set({ youtubeURL: url }),
  setSubmittingYouTube: (submitting) => set({ isSubmittingYouTube: submitting }),
  setYouTubeError: (error) => set({ youtubeError: error }),
  setYouTubeProfileId: (id) => set({ youtubeProfileId: id }),
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
      pendingSeedAttendees: [],
      selectedParticipantIds: [],
    }),
}), {
  name: "processing-recovery",
  partialize: (state) => ({ backgroundTasks: state.backgroundTasks.filter(task => task.status !== "completed").map(({ raw_transcription: _text, notule_html: _html, ...task }) => task) }),
  merge: (saved, current) => ({ ...current, backgroundTasks: ((saved as { backgroundTasks?: TranscriptTask[] })?.backgroundTasks ?? []).map(task => task.status === "failed" ? task : { ...task, status: "failed" as const, error_message: "Verwerking is onderbroken door het sluiten van de app. Je opgeslagen transcriptie blijft bewaard; probeer opnieuw." }) }),
}));
