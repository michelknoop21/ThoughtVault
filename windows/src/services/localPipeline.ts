import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useLocalTranscriptsStore, newLocalId } from "../stores/localTranscriptsStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { LLMService } from "./llm";
import { exportToObsidian } from "./obsidian";
import { extractTitle } from "./titleExtractor";
import { getQuickNote } from "./quickNotes";
import { hasUsableNotule, hasUsableTranscription } from "./notuleValidation";
import { usePersonalCorrectionsStore } from "../stores/personalCorrectionsStore";
import { activeCorrections } from "./personalCorrections";
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
): Promise<void> {
  const rec = useRecordingStore.getState();
  const { addBackgroundTask, updateBackgroundTask, removeBackgroundTask } = rec;
  const settings = useSettingsStore.getState();
  const profile =
    useProfilesStore.getState().getProfile(profileId) ??
    useProfilesStore.getState().profiles[0];

  const taskId = retryTaskId ?? newLocalId();
  const existingPartial = retryTaskId
    ? useLocalTranscriptsStore.getState().items.find((item) => item.id === retryTaskId && !item.has_notes && hasUsableTranscription(item.raw_transcription ?? ""))
    : undefined;
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
  addBackgroundTask(task);

  try {
    let transcription = existingPartial?.raw_transcription;
    if (!transcription) {
      const model = settings.whisper_model || "medium";

      // 1. Ensure the Whisper model is present (download on first use).
      const status = await invoke<WhisperModelStatus>("whisper_model_status", {
        modelId: model,
      });
      if (!status.exists) {
        updateBackgroundTask(taskId, { status: "downloading", progress: 0 });
        const unlistenDl = await listen<{ pct: number }>(
          "whisper-download-progress",
          (e) => updateBackgroundTask(taskId, { progress: e.payload.pct ?? 0 }),
        );
        try {
          await invoke("download_whisper_model", { modelId: model });
        } finally {
          unlistenDl();
        }
      }

      // 2. Transcribe on-device. Map whisper progress (0-100) → 10..50.
      updateBackgroundTask(taskId, { status: "transcribing", progress: 10 });
      const unlistenTr = await listen<number>("transcribe-progress", (e) => {
        const frac = Math.max(0, Math.min(100, e.payload)) / 100;
        updateBackgroundTask(taskId, { progress: Math.round(10 + frac * 40) });
      });
      try {
        await usePersonalCorrectionsStore.getState().hydrate();
        const vocabulary = activeCorrections(usePersonalCorrectionsStore.getState().entries, profile.id).slice(0,30).map(e => e.canonical).join(", ");
        transcription = await invoke<string>("transcribe_local", {
          filePath,
          modelId: model,
          vocabulary,
        });
      } finally {
        unlistenTr();
      }

      if (!hasUsableTranscription(transcription)) {
        throw new Error("Geen bruikbare spraak herkend. Controleer de opname en probeer opnieuw.");
      }

      // 3. Persist a partial record immediately so the transcription survives even
      // if notule generation fails.
      const now = new Date().toISOString();
      const record: Transcript = {
        id: taskId,
        title: "Transcriptie",
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
      await useLocalTranscriptsStore.getState().add(record);
      useTranscriptsStore.getState().addTranscript(record);
    }

    // 4. Generate the notule via the configured local LLM. Stream progress.
    updateBackgroundTask(taskId, { status: "generating", progress: 55 });
    const names = participants.map((p) => p.name).filter(Boolean);
    let streamed = 0;
    const html = await LLMService.generateNotulen(
      transcription,
      profile,
      () => {
        // Coarse progress: creep 55 → 95 as chunks arrive.
        streamed += 1;
        const pct = Math.min(95, 55 + Math.round(streamed / 8));
        updateBackgroundTask(taskId, { progress: pct });
      },
      names,
      getQuickNote(filePath),
    );

    if (!hasUsableNotule(html)) {
      throw new Error("De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw.");
    }

    const title = extractTitle(html) || profile?.name || "Notule";
    const finished: Partial<Transcript> = {
      title,
      notule_html: html,
      has_notes: true,
      updated_at: new Date().toISOString(),
    };
    await useLocalTranscriptsStore.getState().update(taskId, finished);

    useTranscriptsStore.getState().updateTranscript(taskId, finished);

    if (settings.obsidian_enabled) {
      const saved = useLocalTranscriptsStore.getState().items.find((item) => item.id === taskId);
      if (saved) void exportToObsidian(saved, settings).catch((error) =>
        console.warn("Obsidian auto-export mislukt:", error instanceof Error ? error.message : String(error)));
    }

    updateBackgroundTask(taskId, { status: "completed", progress: 100 });
    setTimeout(() => removeBackgroundTask(taskId), 1500);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Lokale verwerking mislukt";
    console.error("[LocalPipeline] Failed:", msg);
    updateBackgroundTask(taskId, { status: "failed", error_message: msg });
  }
}
