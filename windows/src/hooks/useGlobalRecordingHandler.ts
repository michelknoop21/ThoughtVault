import { useEffect, useRef } from "react";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { uploadAndTrack } from "../services/uploadAndTrack";
import { processLocally } from "../services/localPipeline";
import { resolveParticipants } from "../services/participants";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { openWidgetWindow, closeWidgetWindow } from "./useWidgetWindow";
import { recordingAction, type RecordingAction } from "../services/recordingActions";

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
    let unlistenControl: (() => void) | undefined;
    let disposed = false;
    let unlistenFocus: (() => void) | undefined;
    const mainWindow = getCurrentWindow();
    mainWindow.onFocusChanged(async ({ payload: focused }) => {
      const phase = useRecordingStore.getState().phase;
      if (focused) await closeWidgetWindow().catch(() => {});
      else if (["recording", "paused"].includes(phase) && await mainWindow.isMinimized()) {
        await openWidgetWindow().catch(() => {});
      }
    }).then(fn => { if (disposed) fn(); else unlistenFocus = fn; });
    listen<RecordingAction>("widget-recording-action", (event) => {
      if (["pause", "resume", "stop"].includes(event.payload)) {
        void recordingAction(event.payload).catch(() => {});
      }
    }).then((fn) => { if (disposed) fn(); else unlistenControl = fn; });

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
        handleUpload(filePath, event.payload.duration_seconds || 0, isUploadingRef);
      }
    ).then((fn) => { if (disposed) fn(); else unlistenStopped = fn; }).catch(console.error);

    listen<string>("recording-error", (event) => {
      console.error("[Recording] Event: recording-error:", event.payload);
      useRecordingStore.getState().setPhase("idle");
      closeWidgetWindow().catch((e) => console.error("[Recording] Widget close on error failed:", e));
    }).then((fn) => { if (disposed) fn(); else unlistenError = fn; }).catch(console.error);

    return () => {
      disposed = true;
      unlistenControl?.();
      unlistenFocus?.();
      unlistenStopped?.();
      unlistenError?.();
    };
  }, []);
}

async function handleUpload(
  filePath: string,
  durationSeconds: number,
  isUploadingRef: React.RefObject<boolean>,
) {
  if (isUploadingRef.current) return;
  isUploadingRef.current = true;

  try {
    const store = useRecordingStore.getState();
    const { mode, selectedProfileId, usePremium } = store;
    // Resolve participants (self + calendar attendees + manual picks) BEFORE
    // reset() clears the attendee/selection state (D-B).
    const participants = resolveParticipants(
      store.pendingSeedAttendees,
      store.selectedParticipantIds,
    );
    store.reset();
    if (useSettingsStore.getState().processing_mode === "local") {
      await processLocally(filePath, selectedProfileId, mode, participants, durationSeconds);
    } else {
      await uploadAndTrack(filePath, selectedProfileId, mode, usePremium, participants);
    }
  } finally {
    isUploadingRef.current = false;
  }
}
