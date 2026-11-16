import { create } from "zustand";
import { persist } from "zustand/middleware";
import { TaskStatusLabels } from "../types";
import type { RecordingMode, TaskStatus, TranscriptTask } from "../types";
import { useSettingsStore } from "../stores/settingsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useLocalTranscriptsStore } from "../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { modelProvider, modelSettingKey } from "./suggestedModels";

export interface TaskHistoryStep { label: string; started_at: string; finished_at?: string }

export interface TaskHistoryEntry {
  id: string;
  title: string;
  title_edited?: boolean;
  filename?: string;
  profile_id?: string;
  profile_name?: string;
  mode?: RecordingMode;
  created_at: string;
  finished_at?: string;
  status: TaskStatus;
  error_message?: string;
  recording_seconds?: number;
  audio_path?: string;
  recording_deleted?: boolean;
  /** Id of the stored notule (a regeneration task points at the notule it rewrites). */
  transcript_id: string;
  transcription_engine?: string;
  notule_provider?: string;
  notule_model?: string;
  steps: TaskHistoryStep[];
}

/** Settings in force when a task started. */
export interface TaskHistoryContext {
  transcription_engine?: string;
  notule_provider?: string;
  notule_model?: string;
  profile_name?: string;
}

const LIMIT = 200;
const FINISHED: TaskStatus[] = ["completed", "failed", "cancelled", "error"];

export function isFinished(status: TaskStatus): boolean {
  return FINISHED.includes(status);
}

export function outcomeLabel(entry: TaskHistoryEntry, running: boolean): string {
  if (!isFinished(entry.status)) return running ? "Bezig" : "Onderbroken";
  return entry.status === "completed" ? "Voltooid" : entry.status === "cancelled" ? "Geannuleerd" : "Mislukt";
}

export function durationLabel(seconds: number): string {
  const total = Math.max(0, Math.round(seconds));
  if (total < 60) return `${total} s`;
  if (total < 3600) return `${Math.floor(total / 60)} min ${total % 60} s`;
  return `${Math.floor(total / 3600)} u ${String(Math.floor(total % 3600 / 60)).padStart(2, "0")} min`;
}

export function secondsBetween(start: string, end?: string): number | undefined {
  return end ? (new Date(end).getTime() - new Date(start).getTime()) / 1000 : undefined;
}

function stepLabel(task: TranscriptTask): string {
  return task.message || (TaskStatusLabels[task.status] ?? task.status).replace(/\.+$/, "");
}

/**
 * Pure update of the history list for one task change. A new task becomes an entry (taking a
 * carried title), a status or step change closes the previous step, a finished status sets the end time.
 */
export function applyTaskUpdate(entries: TaskHistoryEntry[], task: TranscriptTask, context: TaskHistoryContext,
  now: string, carried?: string): TaskHistoryEntry[] {
  const label = stepLabel(task);
  const current = entries.find(entry => entry.id === task.task_id);
  if (!current) {
    const finished = isFinished(task.status);
    const entry: TaskHistoryEntry = {
      id: task.task_id,
      title: carried || task.extracted_title || task.filename || "Naamloze taak",
      title_edited: !!carried,
      filename: task.filename,
      profile_id: task.profile_id,
      mode: task.mode,
      created_at: task.created_at || now,
      finished_at: finished ? now : undefined,
      status: task.status,
      error_message: task.error_message,
      recording_seconds: task.duration_seconds,
      audio_path: task.local_audio_path,
      transcript_id: task.task_id.replace(/^regen-/, ""),
      steps: finished ? [] : [{ label, started_at: now }],
      ...context,
    };
    return [entry, ...entries].slice(0, LIMIT);
  }
  const next: TaskHistoryEntry = { ...current, steps: [...current.steps], status: task.status };
  if (isFinished(current.status) && !isFinished(task.status)) {
    next.finished_at = undefined;  // a retry under the same id
    next.error_message = undefined;
  }
  if (task.error_message) next.error_message = task.error_message;
  if (task.duration_seconds) next.recording_seconds = task.duration_seconds;
  if (!current.title_edited && task.extracted_title) next.title = task.extracted_title;
  const last = next.steps[next.steps.length - 1];
  if (!isFinished(task.status)) {
    if (!last || last.label !== label || last.finished_at) {
      if (last && !last.finished_at) next.steps[next.steps.length - 1] = { ...last, finished_at: now };
      next.steps.push({ label, started_at: now });
    }
  } else if (!next.finished_at) {
    if (last && !last.finished_at) next.steps[next.steps.length - 1] = { ...last, finished_at: now };
    next.finished_at = now;
  }
  if (JSON.stringify(next) === JSON.stringify(current)) return entries;
  return entries.map(entry => entry.id === next.id ? next : entry);
}

/** The settings that will process a task started now. */
export function currentContext(profileId?: string): TaskHistoryContext {
  const settings = useSettingsStore.getState();
  const profile = useProfilesStore.getState().profiles.find(p => p.id === profileId);
  if (settings.processing_mode !== "local") {
    return { transcription_engine: "ThoughtVault-server", notule_provider: "ThoughtVault-server", profile_name: profile?.name };
  }
  const provider = modelProvider(settings);
  const names: Record<string, string> = { openrouter: "OpenRouter", openai: "OpenAI", anthropic: "Claude", ollama: "Ollama", "ollama-cloud": "Ollama Cloud", "lm-studio": "LM Studio" };
  return {
    transcription_engine: `Whisper · ${settings.whisper_model || "medium"}`,
    notule_provider: names[provider] ?? provider,
    notule_model: settings[modelSettingKey(provider)] || undefined,
    profile_name: profile?.name,
  };
}

interface TaskHistoryState {
  entries: TaskHistoryEntry[];
  /** Titles chosen for a reprocess, keyed by audio path or notule id; not persisted. */
  pendingTitles: Record<string, string>;
  track: (task: TranscriptTask) => void;
  update: (id: string, patch: Partial<TaskHistoryEntry>) => void;
  remove: (id: string) => void;
  carryTitle: (title: string, key: string) => void;
}

export const useTaskHistory = create<TaskHistoryState>()(persist((set, get) => ({
  entries: [],
  pendingTitles: {},
  track: (task) => {
    if (!task.task_id) return;
    const { entries, pendingTitles } = get();
    const isNew = !entries.some(entry => entry.id === task.task_id);
    const key = [task.local_audio_path, task.task_id.replace(/^regen-/, "")].find(k => k && pendingTitles[k]);
    const carried = isNew && key ? pendingTitles[key] : undefined;
    const next = applyTaskUpdate(entries, task, isNew ? currentContext(task.profile_id) : {}, new Date().toISOString(), carried);
    if (next === entries) return;
    const rest = { ...pendingTitles };
    if (carried && key) delete rest[key];
    set({ entries: next, pendingTitles: rest });
    if (task.status === "completed") applyEditedTitle(next.find(entry => entry.id === task.task_id));
  },
  update: (id, patch) => set(state => ({ entries: state.entries.map(entry => entry.id === id ? { ...entry, ...patch } : entry) })),
  remove: (id) => set(state => ({ entries: state.entries.filter(entry => entry.id !== id) })),
  carryTitle: (title, key) => set(state => ({ pendingTitles: { ...state.pendingTitles, [key]: title } })),
}), { name: "task-history", partialize: state => ({ entries: state.entries }) }));

/** A title the user chose replaces the generated one once the notule is saved. */
function applyEditedTitle(entry?: TaskHistoryEntry) {
  if (!entry?.title_edited) return;
  const id = entry.transcript_id;
  if (!useLocalTranscriptsStore.getState().items.some(item => item.id === id)) return;
  void useLocalTranscriptsStore.getState().update(id, { title: entry.title }).catch(() => {});
  useTranscriptsStore.getState().updateTranscript(id, { title: entry.title });
}
