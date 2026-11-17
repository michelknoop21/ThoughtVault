import { api } from "./api";
import { LLMService } from "./llm";
import { prepareMerge } from "./notuleMergeSource";
import { UsageMeter } from "./usageMeter";
import { stepLabel } from "./modelRequestLog";
import { extractTitle } from "./titleExtractor";
import { hasUsableNotule } from "./notuleValidation";
import { useLocalTranscriptsStore, isLocalId, newLocalId } from "../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useRecordingStore, registerAbortController, unregisterAbortController } from "../stores/recordingStore";
import { useProfilesStore } from "../stores/profilesStore";
import type { Transcript } from "../types";

let merging = false;

export async function mergeNotulen(sourceIDs: string[], profileId: string): Promise<Transcript> {
  if (merging) throw new Error("Samenvoegen is al bezig.");
  const profile = useProfilesStore.getState().getProfile(profileId);
  if (!profile) throw new Error("Kies een notulenprofiel.");
  merging = true;
  const id = newLocalId();
  const controller = new AbortController();
  const tasks = useRecordingStore.getState();
  registerAbortController(id, controller);
  const checkCancelled = () => { if (controller.signal.aborted) throw new DOMException("Samenvoegen geannuleerd.", "AbortError"); };
  tasks.addBackgroundTask({ task_id: id, status: "generating", progress: 10, mode: "microphone", profile_id: profileId,
    created_at: new Date().toISOString(), message: "Notulen samenvoegen" });
  try {
    await useLocalTranscriptsStore.getState().hydrate();
    const notes: Transcript[] = [];
    for (const sourceID of new Set(sourceIDs)) {
      checkCancelled();
      const local = useLocalTranscriptsStore.getState().items.find(item => item.id === sourceID || item.task_id === sourceID);
      if (local) notes.push(local);
      else if (isLocalId(sourceID)) throw new Error("Een bronnotule is niet meer beschikbaar.");
      else {
        const source = await api.getTranscript(sourceID);
        const html = source.notule_html?.trim() ? source.notule_html : await api.getTranscriptNotes(sourceID);
        notes.push({ ...source, notule_html: html });
      }
    }
    const snapshot = prepareMerge(notes);
    checkCancelled();
    const meter = new UsageMeter();
    // shortcut: provider requests have no abort signal; discard cancelled output until transport supports abort.
    const html = await LLMService.generateNotulen(snapshot.text, profile, undefined, [], "",
      step => { if (!controller.signal.aborted) tasks.updateBackgroundTask(id, { message: stepLabel(step), progress: 60 }); }, meter, true);
    checkCancelled();
    if (!hasUsableNotule(html)) throw new Error("Geen bruikbare notule gegenereerd.");
    const now = new Date().toISOString();
    const result: Transcript = { id, title: extractTitle(html) || "Samengevoegde notule", raw_transcription: snapshot.text,
      merge_sources: snapshot.sources, notule_html: html, notule_usage: meter.usageFor(snapshot.text, html),
      profile_id: profile.id, profile_name: profile.name, tags: [], has_notes: true, has_transcription: true,
      duration_seconds: 0, created_at: now, updated_at: now };
    await useLocalTranscriptsStore.getState().add(result);
    useTranscriptsStore.getState().addTranscript(result);
    tasks.updateBackgroundTask(id, { status: "completed", progress: 100, message: undefined });
    return result;
  } catch (error) {
    tasks.updateBackgroundTask(id, { status: "failed", error_message: error instanceof Error ? error.message : "Samenvoegen mislukt" });
    throw error;
  } finally {
    unregisterAbortController(id);
    merging = false;
  }
}
