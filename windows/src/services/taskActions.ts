import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useLocalTranscriptsStore } from "../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { processLocally } from "./localPipeline";
import { deleteRecording } from "./tauriCommands";
import { isModelAllowed, modelProvider, modelSettingKey } from "./suggestedModels";
import { isFinished, useTaskHistory, type TaskHistoryEntry } from "./taskHistory";

export function hasNotule(entry: TaskHistoryEntry): boolean {
  return useLocalTranscriptsStore.getState().items.some(item => item.id === entry.transcript_id);
}

export function hasRecording(entry: TaskHistoryEntry): boolean {
  return !!entry.audio_path && !entry.recording_deleted;
}

export function isRunning(entry: TaskHistoryEntry): boolean {
  const task = useRecordingStore.getState().backgroundTasks.find(t => t.task_id === entry.id);
  return !!task && !isFinished(task.status);
}

/** Local reprocessing needs the recording on this pc. */
export function canReprocess(entry: TaskHistoryEntry): boolean {
  return !isRunning(entry) && hasRecording(entry) && useSettingsStore.getState().processing_mode === "local";
}

/** Saves a new title on the history entry and on the notule, when there is one. */
export function renameTask(entry: TaskHistoryEntry, title: string): void {
  const trimmed = title.trim();
  if (!trimmed || trimmed === entry.title) return;
  useTaskHistory.getState().update(entry.id, { title: trimmed, title_edited: true });
  if (hasNotule(entry)) {
    void useLocalTranscriptsStore.getState().update(entry.transcript_id, { title: trimmed }).catch(() => {});
    useTranscriptsStore.getState().updateTranscript(entry.transcript_id, { title: trimmed });
  }
}

/**
 * Processes the recording again with the chosen title, profile and model. A task without an
 * approved notule retries under its own id, which reuses a saved transcription. A completed task
 * gets a new notule next to the existing one, so the existing notule is never emptied first.
 */
export function reprocessTask(entry: TaskHistoryEntry, title: string, profileId: string, model?: string): void {
  if (!canReprocess(entry) || !entry.audio_path) return;
  const settings = useSettingsStore.getState();
  const provider = modelProvider(settings);
  if (model && isModelAllowed(model, provider)) settings.updateSettings({ [modelSettingKey(provider)]: model });
  renameTask(entry, title);
  const recording = useRecordingStore.getState();
  recording.removeBackgroundTask(entry.id);
  const mode = entry.mode ?? "microphone";
  if (entry.status !== "completed") {
    void processLocally(entry.audio_path, profileId, mode, [], entry.recording_seconds ?? 0, entry.id);
    return;
  }
  const edited = useTaskHistory.getState().entries.find(e => e.id === entry.id);
  if (edited?.title_edited) useTaskHistory.getState().carryTitle(edited.title, entry.audio_path);
  void processLocally(entry.audio_path, profileId, mode, [], entry.recording_seconds ?? 0);
}

/** Deletes the audio file; the notule and transcription stay. Entries that share the file (a reprocess) are marked too. */
export async function deleteTaskRecording(entry: TaskHistoryEntry): Promise<void> {
  try {
    if (entry.audio_path && !entry.recording_deleted) await deleteRecording(entry.audio_path);
  } catch (error) {
    // A file that is already gone counts as deleted.
    if (!/os error 2|not found|cannot find/i.test(String(error))) throw error;
  }
  const history = useTaskHistory.getState();
  for (const other of history.entries) {
    if (other.id === entry.id || (entry.audio_path && other.audio_path === entry.audio_path)) history.update(other.id, { recording_deleted: true });
  }
}

/** Removes the task from Taken; the notule is only deleted when `includeNotule` is set. */
export async function deleteTask(entry: TaskHistoryEntry, includeNotule: boolean): Promise<void> {
  useRecordingStore.getState().removeBackgroundTask(entry.id);
  useTaskHistory.getState().remove(entry.id);
  if (includeNotule && hasNotule(entry)) {
    await useLocalTranscriptsStore.getState().remove(entry.transcript_id);
    useTranscriptsStore.getState().deleteTranscript(entry.transcript_id);
  }
}
