import * as audio from "./tauriCommands";
import { useRecordingStore } from "../stores/recordingStore";
import { openWidgetWindow, closeWidgetWindow } from "../hooks/useWidgetWindow";
import { emit } from "@tauri-apps/api/event";

let changing = false;
export type RecordingAction = "start" | "pause" | "resume" | "stop";

/** Page, widget and MCP all enter here. Processing stays in recording-stopped. */
export async function recordingAction(action: RecordingAction): Promise<audio.RecordingResult | string | void> {
  if (changing) throw Error("Een opnameactie is nog bezig.");
  const store = useRecordingStore.getState();
  if (store.updateInstalling) throw Error("De app wordt bijgewerkt. Wacht tot de herstart.");
  const phase = store.phase;
  const allowed = action === "start" ? phase === "idle" : action === "pause" ? phase === "recording" :
    action === "resume" ? phase === "paused" : phase === "recording" || phase === "paused";
  if (!allowed) throw Error("Deze actie past niet bij de huidige opnamefase.");
  changing = true;
  try {
    if (action === "start") {
      store.setPhase("preparing");
      const path = await audio.startRecording(null, store.mode, await audio.getRecordingsDir());
      store.setFilePath(path);
      store.startTimer();
      store.setPhase("recording");
      await openWidgetWindow().catch(() => {});
      return path;
    }
    if (action === "pause") {
      await audio.pauseRecording(); store.pauseTimer(); store.setPhase("paused");
    } else if (action === "resume") {
      await audio.resumeRecording(); store.resumeTimer(); store.setPhase("recording");
    } else {
      store.setPhase("stopping");
      const result = await audio.stopRecording();
      await closeWidgetWindow().catch(() => {});
      return result;
    }
  } catch (error) {
    store.setPhase(action === "start" ? "idle" : phase);
    throw error;
  } finally {
    changing = false;
    const current = useRecordingStore.getState();
    await emit("widget-recording-state", {
      phase: current.phase, recordingStartedAt: current.recordingStartedAt,
      pausedAt: current.pausedAt, pausedDuration: current.pausedDuration,
    }).catch(() => {});
  }
}
