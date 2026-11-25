import type { NotuleDetailLevel, Profile, Transcript } from "../types";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useLocalTranscriptsStore } from "../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { LLMService } from "./llm";
import { UsageMeter } from "./usageMeter";
import { stepLabel } from "./modelRequestLog";
import { NotuleReviewError } from "./notuleAudit";
import { hasUsableNotule, hasUsableTranscription } from "./notuleValidation";
import { extractTitle } from "./titleExtractor";
import { exportWithOwnNotes, getTranscriptQuickNote, getTranscriptIdentity } from "./quickNotes";
import { exportToObsidian, ObsidianBrokenError } from "./obsidian";
import { runInBackground } from "./contextSuggestions";
import { regenerateDetailLevel } from "./notuleDetailLevel";
import { enrichProfile } from "./profileTemplates";

type Notify = (message: string, severity: "success" | "error") => void;

export const regenerateTaskId = (transcriptId: string) => `regen-${transcriptId}`;

/** Shows the regeneration in the processing bar; returns its task id. */
export function addRegenerateTask(transcript: Transcript, profile: Profile): string {
  const tasks = useRecordingStore.getState();
  const taskId = regenerateTaskId(transcript.id);
  tasks.removeBackgroundTask(taskId);
  tasks.addBackgroundTask({ task_id: taskId, status: "generating", progress: 10,
    mode: "microphone", profile_id: profile.id, extracted_title: transcript.title,
    created_at: new Date().toISOString(), message: `Notulen met ${profile.name}` });
  return taskId;
}

/**
 * Local records: re-runs the on-device LLM over the stored transcription and saves the new notule.
 * `chosenLevel` undefined applies the regenerate rule (DEC-073). Failures end up in the task and in `notify`.
 */
export async function regenerateLocalNotule(transcript: Transcript, profile: Profile, chosenLevel?: NotuleDetailLevel, notify: Notify = () => {}): Promise<void> {
  const tasks = useRecordingStore.getState();
  const updateTranscript = useTranscriptsStore.getState().updateTranscript;
  const taskId = addRegenerateTask(transcript, profile);
  let transcription = transcript.raw_transcription ?? "";
  if (!hasUsableTranscription(transcription)) {
    tasks.updateBackgroundTask(taskId, { status: "failed", error_message: "Geen bruikbare transcriptie beschikbaar" });
    notify("Geen bruikbare transcriptie beschikbaar", "error");
    return;
  }
  const detailLevel = chosenLevel
    ?? regenerateDetailLevel(transcript, enrichProfile(profile), useSettingsStore.getState().profile_detail_levels);
  try {
    if (!transcript.merge_sources) transcription = await LLMService.correctTranscription(transcription, profile.id, transcript.id);
    if (transcription !== transcript.raw_transcription) {
      await useLocalTranscriptsStore.getState().update(transcript.id, { raw_transcription: transcription });
      updateTranscript(transcript.id, { raw_transcription: transcription });
    }
    const meter = new UsageMeter();
    const generatedHTML = await LLMService.generateNotulen(transcription, profile,
      () => tasks.updateBackgroundTask(taskId, { progress: 60 }), [], "",
      step => tasks.updateBackgroundTask(taskId, { message: stepLabel(step) }), meter, !!transcript.merge_sources, undefined, detailLevel);
    if (!hasUsableNotule(generatedHTML)) throw new Error("Geen bruikbare notule gegenereerd");
    const html = exportWithOwnNotes(generatedHTML, transcript.quick_note || getTranscriptQuickNote(transcript.id), true);
    const title = getTranscriptIdentity(transcript.id)?.title ? transcript.title : (extractTitle(html) || transcript.title);
    const finished = { notule_html: html, notule_usage: meter.usageFor(transcription, html), detail_level: detailLevel, has_notes: true, title, profile_name: profile.name, profile_id: profile.id,
      notule_draft_html: "", notule_review_reason: "", updated_at: new Date().toISOString() };
    await useLocalTranscriptsStore.getState().update(transcript.id, finished);
    updateTranscript(transcript.id, finished);
    runInBackground(transcript.id, transcription, [], profile.id, profile.name);
    tasks.updateBackgroundTask(taskId, { status: "completed", progress: 100 });
    const settings = useSettingsStore.getState();
    if (settings.obsidian_enabled) {
      const saved = useLocalTranscriptsStore.getState().items.find((item) => item.id === transcript.id);
      // A broken link has its own single notice in the notule view; only other errors are reported.
      if (saved) void exportToObsidian(saved, settings).catch((error) => {
        if (!(error instanceof ObsidianBrokenError)) notify(error instanceof Error ? error.message : "Obsidian-sync mislukt", "error");
      });
    }
    notify("Notule opnieuw gegenereerd", "success");
  } catch (error) {
    let message = error instanceof Error ? error.message : "Regenereren mislukt";
    if (error instanceof NotuleReviewError) {
      try {
        const patch = { notule_draft_html: error.draftHtml, notule_review_reason: message, updated_at: new Date().toISOString() };
        await useLocalTranscriptsStore.getState().update(transcript.id, patch);
        updateTranscript(transcript.id, patch);
        message += ". Het concept is apart bewaard voor beoordeling; de bestaande notule is behouden.";
      } catch {
        message += ". Het concept kon niet worden bewaard; de bestaande notule is behouden.";
      }
    }
    tasks.updateBackgroundTask(taskId, { status: "failed", error_message: message });
    notify("Regenereren mislukt", "error");
  }
}
