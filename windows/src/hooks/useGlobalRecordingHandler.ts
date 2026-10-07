import { useEffect } from "react";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { uploadAndTrack } from "../services/uploadAndTrack";
import { processLocally } from "../services/localPipeline";
import { resolveParticipants } from "../services/participants";
import { closeWidgetWindow } from "./useWidgetWindow";
import { useToast } from "../components/ui/InfoBar";
import { saveQuickNote } from "../services/quickNotes";

/**
 * Global handler for recording-stopped and recording-error events.
 * Must be mounted in a component that is ALWAYS active when authenticated
 * (e.g. ProtectedRoutes), NOT in RecordingPage which unmounts on navigation.
 *
 * This ensures uploads trigger even when the user stops recording via the
 * floating widget while on a different page.
 */
export function useGlobalRecordingHandler() {
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
        if (!filePath || (store.filePath && filePath !== store.filePath)) return;
        void handleUpload(filePath, event.payload.duration_seconds || 0).catch(console.error);
      }
    ).then((fn) => { unlistenStopped = fn; }).catch(console.error);

    listen<string>("recording-error", (event) => {
      console.error("[Recording] Event: recording-error:", event.payload);
      useRecordingStore.getState().setPhase("idle");
      useToast.getState().show(event.payload, "error");
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
  durationSeconds: number,
) {
  const store = useRecordingStore.getState();
  const { mode, selectedProfileId, usePremium } = store;
  // Resolve participants (self + calendar attendees + manual picks) BEFORE
  // reset() clears the attendee/selection state (D-B).
  const participants = resolveParticipants(
    store.pendingSeedAttendees,
    store.selectedParticipantIds,
  );
  saveQuickNote(filePath, store.quickNote);
  store.reset();
  if (useSettingsStore.getState().processing_mode === "local") {
    await processLocally(filePath, selectedProfileId, mode, participants, durationSeconds);
  } else {
    await uploadAndTrack(filePath, selectedProfileId, mode, usePremium, participants);
  }
}
