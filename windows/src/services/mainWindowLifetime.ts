import { invoke } from "@tauri-apps/api/core";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { isBusy, useRecordingStore } from "../stores/recordingStore";

let widgetStarts = 0;
export function reserveWidgetStart(): () => void {
  widgetStarts++;
  let released = false;
  return () => { if (!released) { released = true; widgetStarts--; } };
}
export function hasMainWork(): boolean {
  return widgetStarts > 0 || isBusy(useRecordingStore.getState());
}
export async function mustKeepMain(): Promise<boolean> {
  const [widget, recording] = await Promise.all([
    WebviewWindow.getByLabel("recording-widget"), invoke<boolean>("recording_active"),
  ]);
  return widget !== null || recording || hasMainWork();
}

type CloseRegistration = { ready: Promise<void>; active: boolean };
let currentClose: CloseRegistration | null = null;
export function beginMainCloseHandler() {
  let resolve!: () => void;
  let reject!: (error: Error) => void;
  const ready = new Promise<void>((yes, no) => { resolve = yes; reject = no; });
  void ready.catch(() => {});
  const registration = { ready, active: false };
  currentClose = registration;
  return {
    activate: () => {
      if (currentClose !== registration) return false;
      registration.active = true; resolve(); return true;
    },
    dispose: () => {
      registration.active = false;
      if (currentClose === registration) currentClose = null;
      reject(new Error("Main close handler is unavailable"));
    },
  };
}
export async function requireMainCloseHandler(): Promise<() => boolean> {
  const registration = currentClose;
  if (!registration) throw new Error("Main close handler is unavailable");
  await registration.ready;
  const current = () => currentClose === registration && registration.active;
  if (!current()) throw new Error("Main close handler changed");
  return current;
}
