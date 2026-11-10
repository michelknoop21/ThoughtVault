import { beginMainRecordingHandler } from "../services/mainRecordingLifetime";
import { useLayoutEffect } from "react";
import { emit, listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { uploadAndTrack } from "../services/uploadAndTrack";
import { processLocally } from "../services/localPipeline";
import { resolveParticipants } from "../services/participants";
import { closeWidgetWindow } from "./useWidgetWindow";
import { useToast } from "../components/ui/InfoBar";
import { saveQuickNote } from "../services/quickNotes";
import { reportFailure } from "../services/crashReporter";

/**
 * Global handler for recording-stopped and recording-error events.
 * Must be mounted in a component that is ALWAYS active when authenticated
 * (e.g. ProtectedRoutes), NOT in RecordingPage which unmounts on navigation.
 *
 * This ensures uploads trigger even when the user stops recording via the
 * floating widget while on a different page.
 */
export function useGlobalRecordingHandler() {
  useLayoutEffect(() => {
    const registration = beginMainRecordingHandler();
    let disposed = false;
    const listeners: (() => void)[] = [];
    const retain = (stop: () => void) => { if (disposed) stop(); else listeners.push(stop); };
    const syncWidget = () => {
      if (disposed) return;
      const { phase, recordingStartedAt, pausedAt, pausedDuration } = useRecordingStore.getState();
      void emit("widget-sync-timer", { phase, recordingStartedAt, pausedAt, pausedDuration }).catch(console.error);
    };
    const unsubscribe = useRecordingStore.subscribe((state, previous) => {
      if (state.phase !== previous.phase || state.pausedAt !== previous.pausedAt || state.pausedDuration !== previous.pausedDuration) syncWidget();
    });
    const ready = listen("widget-ready", syncWidget);
    const paused = listen("recording-paused", () => {
      if (disposed) return;
      const store = useRecordingStore.getState();
      if (store.phase !== "recording") return;
      store.pauseTimer();
      store.setPhase("paused");
    });
    const stopping = listen("recording-stopping", () => {
      if (disposed) return;
      const store = useRecordingStore.getState();
      if (store.phase === "recording" || store.phase === "paused") {
        if (store.pausedAt === null) store.pauseTimer();
        store.setPhase("stopping");
      }
    });
    const resumed = listen("recording-resumed", () => {
      if (disposed) return;
      const store = useRecordingStore.getState();
      if (store.phase !== "paused") return;
      store.resumeTimer();
      store.setPhase("recording");
    });

    const stopped = listen<{ file_path: string; duration_seconds: number }>(
      "recording-stopped",
      (event) => {
        if (disposed) return;
        const store = useRecordingStore.getState();
        const phase = store.phase;

        // Only handle if we were actually recording
        if (phase !== "recording" && phase !== "paused" && phase !== "stopping") {
          return;
        }

        const filePath = event.payload.file_path || store.filePath || "";
        if (!filePath || (store.filePath && filePath !== store.filePath)) return;
        if (!store.processOnStop) return;
        void handleUpload(filePath, event.payload.duration_seconds || 0).catch(console.error);
      }
    );

    const error = listen<string>("recording-error", (event) => {
      if (disposed) return;
      console.error("[Recording] Event: recording-error:", event.payload);
      useRecordingStore.getState().setPhase("idle");
      useToast.getState().show(event.payload, "error");
      closeWidgetWindow().catch((e) => console.error("[Recording] Widget close on error failed:", e));
    });
    const diagnostics = {
      start_failed: ["Opname starten mislukt", "recording_start_failed"],
      capture_failed: ["Opnemen mislukt", "native_recording_failed"],
      stop_failed: ["Opname stoppen mislukt", "recording_stop_failed"],
      pause_failed: ["Pauzeren mislukt", "pause_failed"],
      resume_failed: ["Hervatten mislukt", "resume_failed"],
    } as const;
    const diagnostic = listen<unknown>("recording-diagnostic", ({ payload }) => {
      if (disposed || typeof payload !== "string" || !Object.prototype.hasOwnProperty.call(diagnostics, payload)) return;
      const [shown, code] = diagnostics[payload as keyof typeof diagnostics];
      void reportFailure("opnemen", shown, code);
    });
    // Register every handler before native recording or widget creation can begin.
    void Promise.all([ready, paused, resumed, stopping, stopped, error, diagnostic].map(listener => listener.then(retain)))
      .then(() => { if (!disposed) registration.activate(); })
      .catch(error => { dispose(); console.error(error); });

    function dispose() {
      disposed = true;
      registration.dispose();
      unsubscribe();
      listeners.splice(0).forEach(stop => stop());
    }
    return dispose;
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
