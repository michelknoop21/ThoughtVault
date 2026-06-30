import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useLocalTranscriptsStore, newLocalId } from "../stores/localTranscriptsStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { LLMService } from "./llm";
import { extractTitle } from "./titleExtractor";
import type { Participant } from "./participants";
import type { RecordingMode, Transcript, TranscriptTask } from "../types";

interface WhisperModelStatus {
  exists: boolean;
  path: string;
  size_bytes: number;
}

/**
 * Fully on-device processing: Whisper transcription + Ollama/LM Studio notule
 * generation, persisted locally. The local-mode counterpart of uploadAndTrack,
 * mirroring the macOS RecordingViewModel.processLocally pipeline.
 */
export async function processLocally(
  filePath: string,
  profileId: string,
  mode: RecordingMode,
  participants: Participant[] = [],
  durationSeconds: number = 0,
): Promise<void> {
  const rec = useRecordingStore.getState();
  const { addBackgroundTask, updateBackgroundTask, removeBackgroundTask } = rec;
  const settings = useSettingsStore.getState();
  const profile =
    useProfilesStore.getState().getProfile(profileId) ??
    useProfilesStore.getState().profiles[0];

  const taskId = newLocalId();
  const task: TranscriptTask = {
    task_id: taskId,
    status: "transcribing",
    progress: 5,
    mode,
    created_at: new Date().toISOString(),
    profile_id: profileId,
  };
  addBackgroundTask(task);

  try {
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
    let transcription: string;
    try {
      transcription = await invoke<string>("transcribe_local", {
        filePath,
        modelId: model,
      });
    } finally {
      unlistenTr();
    }

    if (!transcription.trim()) {
      throw new Error("Geen spraak herkend in de opname");
    }

    // 3. Persist a partial record immediately so the transcription survives even
    // if notule generation fails.
    const now = new Date().toISOString();
    const record: Transcript = {
      id: taskId,
      title: "Transcriptie",
      raw_transcription: transcription,
      notule_html: "",
      duration_seconds: durationSeconds,
      profile_name: profile?.name,
      tags: [],
      has_transcription: true,
      has_notes: false,
      created_at: now,
      updated_at: now,
    };
    useLocalTranscriptsStore.getState().add(record);

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
    );

    const title = extractTitle(html) || profile?.name || "Notule";
    const finished: Partial<Transcript> = {
      title,
      notule_html: html,
      has_notes: true,
      updated_at: new Date().toISOString(),
    };
    useLocalTranscriptsStore.getState().update(taskId, finished);

    // Surface in the live transcripts list immediately.
    useTranscriptsStore.getState().addTranscript({ ...record, ...finished });

    updateBackgroundTask(taskId, { status: "completed", progress: 100 });
    setTimeout(() => removeBackgroundTask(taskId), 1500);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Lokale verwerking mislukt";
    console.error("[LocalPipeline] Failed:", msg);
    updateBackgroundTask(taskId, { status: "failed", error_message: msg });
  }
}
