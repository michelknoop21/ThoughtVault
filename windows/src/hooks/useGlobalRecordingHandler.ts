import { useEffect, useRef } from "react";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { uploadAndTrack } from "../services/uploadAndTrack";
import { closeWidgetWindow } from "./useWidgetWindow";

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

  try {
    const store = useRecordingStore.getState();
    const { mode, selectedProfileId } = store;
    store.reset();
    await uploadAndTrack(filePath, selectedProfileId, mode);
  } finally {
    isUploadingRef.current = false;
  }
}
