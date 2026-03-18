import { useEffect, useRef } from "react";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore, registerAbortController, unregisterAbortController } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { api } from "../services/api";
import { createSSEClient } from "../services/sse";
import { enqueue } from "../services/offlineQueue";
import { closeWidgetWindow } from "./useWidgetWindow";
import type { TranscriptTask } from "../types";

/**
 * Global handler for recording-stopped and recording-error events.
 * Must be mounted in a component that is ALWAYS active when authenticated
 * (e.g. ProtectedRoutes), NOT in RecordingPage which unmounts on navigation.
 *
 * This ensures uploads trigger even when the user stops recording via the
 * floating widget while on a different page.
 */
export function useGlobalRecordingHandler() {
  const isUploadingRef = useRef(false);

  useEffect(() => {
    let unlistenStopped: (() => void) | undefined;
    let unlistenError: (() => void) | undefined;

    listen<{ file_path: string; duration_seconds: number }>(
      "recording-stopped",
      (event) => {
        const store = useRecordingStore.getState();
        const phase = store.phase;

        // Only handle if we were actually recording
        if (phase !== "recording" && phase !== "paused" && phase !== "stopping") {
          return;
        }

        const filePath = event.payload.file_path || store.filePath || "";
        handleUpload(filePath, isUploadingRef);
      }
    ).then((fn) => { unlistenStopped = fn; }).catch(console.error);

    listen<string>("recording-error", (event) => {
      console.error("[Recording] Event: recording-error:", event.payload);
      useRecordingStore.getState().setPhase("idle");
      closeWidgetWindow().catch((e) => console.error("[Recording] Widget close on error failed:", e));
    }).then((fn) => { unlistenError = fn; }).catch(console.error);

    return () => {
      unlistenStopped?.();
      unlistenError?.();
    };
  }, []);
}

async function handleUpload(
  filePath: string,
  isUploadingRef: React.RefObject<boolean>,
) {
  if (isUploadingRef.current) return;
  isUploadingRef.current = true;

  const store = useRecordingStore.getState();
  const { mode, selectedProfileId } = store;
  const { addBackgroundTask, updateBackgroundTask, removeBackgroundTask, reset } = store;
  const { addTranscript } = useTranscriptsStore.getState();

  try {
    const tempId = `pending-${Date.now()}`;
    const bgTask: TranscriptTask = {
      task_id: tempId,
      status: "uploading",
      progress: 0,
      mode,
      created_at: new Date().toISOString(),
    };
    addBackgroundTask(bgTask);
    reset();

    const abortController = new AbortController();
    registerAbortController(tempId, abortController);
    try {
      const { task_id } = await api.uploadRecordingWithProgress(
        filePath, selectedProfileId, mode,
        (fraction) => updateBackgroundTask(tempId, { progress: Math.round(fraction * 100) }),
        abortController.signal
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
          updateBackgroundTask(task_id, { status: "failed", error_message: "Verbinding verloren" });
        },
        async () => {
          const transcripts = await api.getTranscripts();
          if (transcripts[0]) addTranscript(transcripts[0]);
          removeBackgroundTask(task_id);
        }
      );
    } catch (err) {
      unregisterAbortController(tempId);
      if (err instanceof DOMException && err.name === "AbortError") {
        removeBackgroundTask(tempId);
        return;
      }
      const msg = err instanceof Error ? err.message : "Upload mislukt";
      console.error("[Recording] Upload failed:", msg);
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
          profile_id: selectedProfileId,
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
  } finally {
    isUploadingRef.current = false;
  }
}
