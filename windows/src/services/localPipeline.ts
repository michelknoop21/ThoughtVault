import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore, registerAbortController, unregisterAbortController } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useLocalTranscriptsStore, newLocalId } from "../stores/localTranscriptsStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { LLMService } from "./llm";
import { UsageMeter } from "./usageMeter";
import { stepLabel } from "./modelRequestLog";
import { NotuleReviewError } from "./notuleAudit";
import { exportToObsidian, ObsidianBrokenError } from "./obsidian";
import { extractTitle } from "./titleExtractor";
import { getQuickNote, exportWithOwnNotes, getRecordingIdentity, linkRecordingIdentity } from "./quickNotes";
import { hasUsableNotule, hasUsableTranscription } from "./notuleValidation";
import { useTaskHistory } from "./taskHistory";
import { mask } from "./appLog";
import { runInBackground } from "./contextSuggestions";
import type { Participant } from "./participants";
import type { RecordingMode, Transcript, TranscriptTask } from "../types";

interface WhisperModelStatus {
  exists: boolean;
  path: string;
  size_bytes: number;
}

/**
 * Local Whisper transcription + the selected LLM (local or hosted API),
 * persisted locally. The local-transcription counterpart of uploadAndTrack,
 * mirroring the macOS RecordingViewModel.processLocally pipeline.
 */
export async function processLocally(
  filePath: string,
  profileId: string,
  mode: RecordingMode,
  participants: Participant[] = [],
  durationSeconds: number = 0,
  retryTaskId?: string,
  optimizeAudio: boolean = false,
  reuseTranscriptId?: string,
): Promise<void> {
  const rec = useRecordingStore.getState();
  const { addBackgroundTask, updateBackgroundTask, removeBackgroundTask } = rec;
  const settings = useSettingsStore.getState();
  const profile =
    useProfilesStore.getState().getProfile(profileId) ??
    useProfilesStore.getState().profiles[0];

  const taskId = optimizeAudio ? newLocalId() : retryTaskId ?? newLocalId();
  const reused = !optimizeAudio && reuseTranscriptId ? useLocalTranscriptsStore.getState().items.find(item => item.id === reuseTranscriptId && hasUsableTranscription(item.raw_transcription ?? "")) : undefined;
  const existingPartial = reused ?? (!optimizeAudio && retryTaskId
    ? useLocalTranscriptsStore.getState().items.find((item) => item.id === retryTaskId && !item.has_notes && hasUsableTranscription(item.raw_transcription ?? ""))
    : undefined);
  const task: TranscriptTask = {
    task_id: taskId,
    status: "transcribing",
    progress: 5,
    mode,
    created_at: new Date().toISOString(),
    profile_id: profileId,
    local_audio_path: filePath,
    filename: filePath.split(/[\\/]/).pop(),
  };
  const identity = getRecordingIdentity(filePath);
  if (identity?.title && !useTaskHistory.getState().pendingTitles[filePath]) useTaskHistory.getState().carryTitle(identity.title, filePath);
  linkRecordingIdentity(taskId, filePath);
  addBackgroundTask(task);
  const controller = new AbortController();
  registerAbortController(taskId, controller);
  controller.signal.addEventListener("abort", () => {
    if (optimizeAudio) void invoke("cancel_audio_optimization", { requestId: taskId }).catch(() => {});
  }, { once: true });
  const checkCancelled = () => { if (controller.signal.aborted) throw new DOMException("Geannuleerd", "AbortError"); };

  try {
    if (reused) {
      const now = new Date().toISOString();
      const copy = { ...reused, id: taskId, task_id: taskId, notule_html: "", has_notes: false, notule_draft_html: "", notule_review_reason: "", created_at: now, updated_at: now };
      await useLocalTranscriptsStore.getState().add(copy);
      useTranscriptsStore.getState().addTranscript(copy);
    }
    let transcription = existingPartial?.raw_transcription;
    if (!transcription) {
      if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) {
        durationSeconds = await invoke<number>("audio_duration", { filePath });
      }
      updateBackgroundTask(taskId, { duration_seconds: durationSeconds });
      const model = settings.whisper_model || "medium";

      // Model setup is explicit; leave the recording available for a deliberate retry.
      const status = await invoke<WhisperModelStatus>("whisper_model_status", {
        modelId: model,
      });
      if (!status.exists) {
        throw new Error("Transcriptiemodel ontbreekt. Download het gekozen model bij Instellingen → Verwerking en verwerk daarna deze opname opnieuw. De opname wordt niet gewijzigd.");
      }

      // 2. Transcribe on-device. Map whisper progress (0-100) → 10..50.
      updateBackgroundTask(taskId, { status: "transcribing", progress: 10 });
      const unlistenTr = await listen<{ request_id: string; progress: number }>("transcribe-progress", (e) => {
        if (e.payload.request_id !== taskId || controller.signal.aborted) return;
        const frac = Math.max(0, Math.min(100, e.payload.progress)) / 100;
        updateBackgroundTask(taskId, { progress: Math.round(10 + frac * 40), message: "Transcriberen" });
      });
      const unlistenOptimization = optimizeAudio ? await listen<{ request_id: string; progress: number }>("audio-optimization-progress", e => {
        if (e.payload.request_id === taskId && !controller.signal.aborted) updateBackgroundTask(taskId, { progress: Math.round(e.payload.progress * 10), message: "Audio optimaliseren" });
      }) : () => {};
      try {
        checkCancelled();
        // No glossary as Whisper prompt: it silently drops speech. Names are
        // corrected afterwards in LLMService (correctText/correctHTML).
        transcription = await invoke<string>("transcribe_local", {
          filePath,
          modelId: model,
          requestId: taskId,
          ...(optimizeAudio ? { optimizeAudio: true } : {}),
        });
        checkCancelled();
      } finally {
        unlistenTr();
        unlistenOptimization();
      }

      if (!hasUsableTranscription(transcription)) {
        throw new Error("Geen bruikbare spraak herkend. Controleer de opname en probeer opnieuw.");
      }

      // 3. Persist a partial record immediately so the transcription survives even
      // if notule generation fails.
      const now = new Date().toISOString();
      const record: Transcript = {
        id: taskId,
        title: identity?.title ?? "Transcriptie",
        raw_transcription: transcription,
        quick_note: getQuickNote(filePath),
        notule_html: "",
        duration_seconds: durationSeconds,
        profile_name: profile?.name,
        profile_id: profile?.id,
        tags: [],
        has_transcription: true,
        has_notes: false,
        created_at: now,
        updated_at: now,
      };
      checkCancelled();
      await useLocalTranscriptsStore.getState().add(record);
      useTranscriptsStore.getState().addTranscript(record);
    }

    // 4. Generate the notule via the configured local LLM. Stream progress.
    updateBackgroundTask(taskId, { status: "generating", progress: 55, message: "Notulen genereren" });
    const names = participants.map((p) => p.name).filter(Boolean);
    let streamed = 0;
    const meter = new UsageMeter();
    const generatedHTML = await LLMService.generateNotulen(
      transcription,
      profile,
      () => {
        // Coarse progress: creep 55 → 95 as chunks arrive.
        streamed += 1;
        const pct = Math.min(95, 55 + Math.round(streamed / 8));
        updateBackgroundTask(taskId, { progress: pct });
      },
      names,
      "",
      step => updateBackgroundTask(taskId, { message: stepLabel(step) }),
      meter,
    );

    const html = exportWithOwnNotes(generatedHTML, getQuickNote(filePath), true);
    checkCancelled();
    if (!hasUsableNotule(generatedHTML)) {
      throw new Error("De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw.");
    }

    const historyEntry = useTaskHistory.getState().entries.find(entry => entry.id === taskId);
    const chosenTitle = historyEntry?.title_edited ? historyEntry.title : identity?.title;
    const title = chosenTitle ?? (extractTitle(html) || profile?.name || "Notule");
    const finished: Partial<Transcript> = {
      notule_draft_html: "",
      notule_review_reason: "",
      title,
      notule_html: html,
      notule_usage: meter.usageFor(transcription, html),
      has_notes: true,
      updated_at: new Date().toISOString(),
    };
    checkCancelled();
    await useLocalTranscriptsStore.getState().update(taskId, finished);

    useTranscriptsStore.getState().updateTranscript(taskId, finished);
    // Background term and people suggestions; never blocks or fails the saved notule.
    runInBackground(taskId, transcription, participants, profile?.id, profile?.name ?? "");

    if (settings.obsidian_enabled) {
      const saved = useLocalTranscriptsStore.getState().items.find((item) => item.id === taskId);
      if (saved) void exportToObsidian(saved, settings).catch((error) => {
        if (!(error instanceof ObsidianBrokenError)) console.warn("Obsidian auto-export mislukt:", error instanceof Error ? error.message : String(error));
      });
    }

    checkCancelled();
    updateBackgroundTask(taskId, { status: "completed", progress: 100, message: undefined });
    setTimeout(() => removeBackgroundTask(taskId), 1500);
  } catch (err) {
    if (controller.signal.aborted) return;
    let msg = err instanceof Error ? err.message : typeof err === "string" && err.trim() ? err : "Lokale verwerking mislukt";
    if (err instanceof NotuleReviewError) {
      try {
        const patch = { notule_draft_html: err.draftHtml, notule_review_reason: msg, updated_at: new Date().toISOString() };
        await useLocalTranscriptsStore.getState().update(taskId, patch);
        useTranscriptsStore.getState().updateTranscript(taskId, patch);
        msg += ". Het concept is apart bewaard voor beoordeling; er is geen nieuwe goedgekeurde notule opgeslagen.";
      } catch {
        msg += ". Het concept kon niet worden bewaard. De transcriptie en opname zijn niet vervangen.";
      }
    }
    console.error("[LocalPipeline] Failed:", mask(msg));
    updateBackgroundTask(taskId, { status: "failed", error_message: msg });
  } finally {
    unregisterAbortController(taskId);
  }
}
