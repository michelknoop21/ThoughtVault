import { useRecordingStore, registerAbortController, unregisterAbortController } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useSettingsStore } from "../stores/settingsStore";
import { api } from "./api";
import { createSSEClient } from "./sse";
import { exportToObsidian } from "./obsidian";
import { enqueue } from "./offlineQueue";
import { linkQuickNote, getTranscriptQuickNote, ensureNotesSection } from "./quickNotes";
import { usePersonalCorrectionsStore } from "../stores/personalCorrectionsStore";
import { correctHTML } from "./personalCorrections";
import type { Participant } from "./participants";
import type { RecordingMode, TranscriptTask } from "../types";

/**
 * The server never sees the quick note: a finished cloud notule gets its Notities section
 * on the client and is written back. Correction write failures must reach the caller.
 */
export async function persistNotesSection(taskId: string, html: string, profileId?: string): Promise<string> {
  await usePersonalCorrectionsStore.getState().hydrate();
  const withNotes = ensureNotesSection(html, getTranscriptQuickNote(taskId));
  const fixed = correctHTML(withNotes, usePersonalCorrectionsStore.getState().entries, profileId);
  if (fixed !== html) await api.updateNotuleHTML(taskId, fixed).catch((e) => {
    if (fixed !== withNotes) throw e;
    console.warn("Notities-sectie terugschrijven mislukt:", e);
  });
  return fixed;
}

/**
 * Upload a recording file to the server with progress tracking, SSE monitoring,
 * and automatic offline queue fallback on failure.
 *
 * Used by both useGlobalRecordingHandler (after recording stops) and
 * SavedRecordings (manual reprocess).
 */
export async function uploadAndTrack(
  filePath: string,
  profileId: string,
  mode: RecordingMode,
  usePremium: boolean = false,
  participants: Participant[] = [],
): Promise<void> {
  const store = useRecordingStore.getState();
  const { addBackgroundTask, updateBackgroundTask, removeBackgroundTask } = store;
  const { addTranscript } = useTranscriptsStore.getState();

  const tempId = `pending-${crypto.randomUUID()}`;
  const bgTask: TranscriptTask = {
    task_id: tempId,
    status: "uploading",
    progress: 0,
    mode,
    created_at: new Date().toISOString(),
  };
  addBackgroundTask(bgTask);

  const abortController = new AbortController();
  registerAbortController(tempId, abortController);

  try {
    const { task_id } = await api.uploadRecordingWithProgress(
      filePath, profileId, mode,
      (fraction) => updateBackgroundTask(tempId, { progress: Math.round(fraction * 100) }),
      abortController.signal,
      usePremium,
      participants,
    );

    unregisterAbortController(tempId);
    linkQuickNote(task_id, filePath);
    updateBackgroundTask(tempId, { task_id, status: "uploading", progress: 10 });

    const sseClient = createSSEClient(api.getStreamUrl(task_id));
    sseClient.connect(
      (update) => {
        updateBackgroundTask(task_id, update);
      },
      (err) => {
        console.error("[SSE] Error:", err);
        updateBackgroundTask(task_id, {
          status: "failed",
          error_message: "Verbinding met de server verloren. De verwerking gaat door op de achtergrond; bekijk de status in Opnames.",
        });
      },
      async (status) => {
        if (status === "failed" || status === "cancelled" || status === "error") return;
        try {
        const transcripts = await api.getTranscripts();
        const completed = transcripts.find(transcript => transcript.task_id === task_id || transcript.id === task_id);
        if (!completed) throw new Error("Het resultaat is nog niet beschikbaar. Vernieuw Opnames om het op te halen.");
        {
          if (completed.notule_html) completed.notule_html = await persistNotesSection(task_id, completed.notule_html, profileId);
          addTranscript(completed);
          // Auto-export the freshly completed notule to Obsidian (fire-and-forget).
          const settings = useSettingsStore.getState();
          if (settings.obsidian_enabled) {
            exportToObsidian(completed, settings).catch((e) =>
              console.warn("Obsidian auto-export mislukt:", e),
            );
          }
        }
        removeBackgroundTask(task_id);
        } catch (err) {
          updateBackgroundTask(task_id, { status: "failed", error_message: err instanceof Error ? err.message : String(err) });
        }
      },
    );
  } catch (err) {
    unregisterAbortController(tempId);
    if (err instanceof DOMException && err.name === "AbortError") {
      removeBackgroundTask(tempId);
      return;
    }
    const msg = err instanceof Error ? err.message : "Upload mislukt";
    console.error("[Upload] Failed:", msg);

    const isAuthError = msg.includes("HTTP 401");
    const isClientError = msg.includes("HTTP 4") && !isAuthError;
    // Never enqueue in local mode — there is no server to drain the queue.
    const isLocal = useSettingsStore.getState().processing_mode === "local";
    if (!isClientError && !isLocal) {
      let fileSizeBytes: number | undefined;
      let fileName: string | undefined;
      try {
        const { stat } = await import("@tauri-apps/plugin-fs");
        const info = await stat(filePath);
        fileSizeBytes = info.size;
      } catch { /* best-effort */ }
      fileName = filePath.split(/[\\/]/).pop() || undefined;
      await enqueue({
        file_path: filePath,
        profile_id: profileId,
        mode,
        file_size_bytes: fileSizeBytes,
        file_name: fileName,
      }).catch(() => {});
    }

    updateBackgroundTask(tempId, {
      status: "failed",
      error_message: msg,
    });
  }
}
