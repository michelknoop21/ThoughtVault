import { create } from "zustand";
import { persist, type PersistStorage, type StorageValue } from "zustand/middleware";
import { log } from "./appLog";
import { TaskStatusLabels } from "../types";
import type { RecordingMode, TaskStatus, TranscriptTask } from "../types";
import { useSettingsStore } from "../stores/settingsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { isLocalId, useLocalTranscriptsStore } from "../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { capNotice, isMetered, modelRefusal, modelProvider, modelSettingKey, usableModel } from "./suggestedModels";

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
  /** Set when the stored model was above the price cap and another model was used. */
  notule_notice?: string;
  steps: TaskHistoryStep[];
}

/** Settings in force when a task started. */
export interface TaskHistoryContext {
  transcription_engine?: string;
  notule_provider?: string;
  notule_model?: string;
  notule_notice?: string;
  profile_name?: string;
}

const LIMIT = 200;
const FINISHED: TaskStatus[] = ["completed", "failed", "cancelled", "error"];

export function isFinished(status: TaskStatus): boolean {
  return FINISHED.includes(status);
}

/** Set on a local run that was still going when the app quit. */
export const INTERRUPTED_MESSAGE = "Onderbroken: de app werd afgesloten tijdens de verwerking.";

export function outcomeLabel(entry: TaskHistoryEntry, running: boolean): string {
  if (!isFinished(entry.status)) return running ? "Bezig" : "Onderbroken";
  if (entry.error_message === INTERRUPTED_MESSAGE) return "Onderbroken";
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
    // A new run under the same id starts clean; only a title carried for this run names it.
    Object.assign(next, context, { created_at: now, finished_at: undefined, error_message: undefined, steps: [],
      title_edited: !!carried, ...(carried ? { title: carried } : {}) });
  }
  if (task.error_message) next.error_message = task.error_message;
  if (task.duration_seconds) next.recording_seconds = task.duration_seconds;
  if (!next.title_edited && task.extracted_title) next.title = task.extracted_title;
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
  const model = settings[modelSettingKey(provider)];
  const names: Record<string, string> = { openrouter: "OpenRouter", openai: "OpenAI", anthropic: "Claude", ollama: "Ollama", "ollama-cloud": "Ollama Cloud", "lm-studio": "LM Studio" };
  return {
    transcription_engine: `Whisper · ${settings.whisper_model || "medium"}`,
    notule_provider: names[provider] ?? provider,
    notule_model: model ? usableModel(model, provider) : undefined,
    notule_notice: !model ? undefined : isMetered(provider) ? capNotice(model, provider) : modelRefusal(model),
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
  /** An upload gets its server id once the upload finishes; the entry moves along. */
  rekey: (from: string, to: string) => void;
  carryTitle: (title: string, key: string) => void;
}

type Persisted = { entries: TaskHistoryEntry[] };

const isStep = (value: unknown): value is TaskHistoryStep =>
  !!value && typeof (value as TaskHistoryStep).label === "string" && typeof (value as TaskHistoryStep).started_at === "string";

/**
 * A stored entry as the screens need it: required fields present, invalid steps dropped. A local run
 * that was still going cannot survive a restart and becomes interrupted; a server run may still be going.
 */
function repairEntry(value: unknown): TaskHistoryEntry | undefined {
  const entry = value as TaskHistoryEntry;
  const strings = [entry?.id, entry?.title, entry?.created_at, entry?.status, entry?.transcript_id];
  if (!strings.every(field => typeof field === "string")) return undefined;
  const steps = Array.isArray(entry.steps) ? entry.steps.filter(isStep) : [];
  const interrupted = !isFinished(entry.status) && isLocalId(entry.transcript_id);
  return { ...entry, steps, ...(interrupted ? { status: "error" as const, error_message: INTERRUPTED_MESSAGE } : {}) };
}

/**
 * The history never blocks processing: read and write errors are logged (no content), and an
 * unreadable value is kept aside under a timestamped key while the history starts empty.
 */
function historyStorage(): PersistStorage<Persisted> {
  const warn = (what: string, error: unknown) => log.warn("TaskHistory", `${what}: ${error instanceof Error ? error.name : "invalid"}`);
  return {
    getItem: (name) => {
      let raw: string | null = null;
      try {
        raw = localStorage.getItem(name);
        if (raw == null) return null;
        const value = JSON.parse(raw) as StorageValue<Persisted>;
        if (!Array.isArray(value?.state?.entries)) throw new TypeError("invalid task history");
        const entries = value.state.entries.map(repairEntry).filter((entry): entry is TaskHistoryEntry => !!entry);
        return { ...value, state: { ...value.state, entries } };
      } catch (error) {
        warn("Task history unreadable, moved aside", error);
        try {
          if (raw != null) localStorage.setItem(`${name}.corrupt-${Date.now()}`, raw);
          localStorage.removeItem(name);
        } catch { /* keeping it aside is best effort */ }
        return null;
      }
    },
    setItem: (name, value) => {
      try { localStorage.setItem(name, JSON.stringify(value)); } catch (error) { warn("Task history not saved", error); }
    },
    removeItem: (name) => { try { localStorage.removeItem(name); } catch { /* nothing to keep */ } },
  };
}

export const useTaskHistory = create<TaskHistoryState>()(persist((set, get) => ({
  entries: [],
  pendingTitles: {},
  track: (task) => {
    if (!task.task_id) return;
    const { entries, pendingTitles } = get();
    const current = entries.find(entry => entry.id === task.task_id);
    const startsRun = !current || (isFinished(current.status) && !isFinished(task.status));
    const key = [task.local_audio_path, task.task_id.replace(/^regen-/, "")].find(k => k && pendingTitles[k]);
    const carried = startsRun && key ? pendingTitles[key] : undefined;
    const next = applyTaskUpdate(entries, task, startsRun ? currentContext(task.profile_id) : {}, new Date().toISOString(), carried);
    if (next === entries) return;
    const rest = { ...pendingTitles };
    if (carried && key) delete rest[key];
    set({ entries: next, pendingTitles: rest });
    if (task.status === "completed") applyEditedTitle(next.find(entry => entry.id === task.task_id));
  },
  update: (id, patch) => set(state => ({ entries: state.entries.map(entry => entry.id === id ? { ...entry, ...patch } : entry) })),
  remove: (id) => set(state => ({ entries: state.entries.filter(entry => entry.id !== id) })),
  rekey: (from, to) => set(state => ({
    entries: state.entries.filter(entry => entry.id !== to).map(entry => entry.id === from ? { ...entry, id: to, transcript_id: to } : entry),
  })),
  carryTitle: (title, key) => set(state => ({ pendingTitles: { ...state.pendingTitles, [key]: title } })),
}), { name: "task-history", storage: historyStorage(), partialize: state => ({ entries: state.entries }) }));

/** A title the user chose replaces the generated one once the notule is saved. */
function applyEditedTitle(entry?: TaskHistoryEntry) {
  if (!entry?.title_edited) return;
  const id = entry.transcript_id;
  if (!useLocalTranscriptsStore.getState().items.some(item => item.id === id)) return;
  void useLocalTranscriptsStore.getState().update(id, { title: entry.title }).catch(() => {});
  useTranscriptsStore.getState().updateTranscript(id, { title: entry.title });
}
