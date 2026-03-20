import { useRecordingStore, registerAbortController, unregisterAbortController } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { api } from "./api";
import { createSSEClient } from "./sse";
import { enqueue } from "./offlineQueue";
import type { RecordingMode, TranscriptTask } from "../types";

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
): Promise<void> {
  const store = useRecordingStore.getState();
  const { addBackgroundTask, updateBackgroundTask, removeBackgroundTask } = store;
  const { addTranscript } = useTranscriptsStore.getState();

  const tempId = `pending-${Date.now()}`;
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
    );

    unregisterAbortController(tempId);
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
          error_message: "Verbinding met de server verloren. De verwerking gaat door op de achtergrond — bekijk de status in Opnames.",
        });
      },
      async () => {
        const transcripts = await api.getTranscripts();
        if (transcripts[0]) addTranscript(transcripts[0]);
        removeBackgroundTask(task_id);
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
    if (!isClientError) {
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
