import { requireMainRecordingHandler } from "../services/mainRecordingLifetime";
import { requireMainCloseHandler, reserveWidgetStart } from "../services/mainWindowLifetime";
import { requireSupportOwner } from "../services/supportOwner";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { availableMonitors } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";

/**
 * Opens the floating recording widget window.
 * The widget is a separate Tauri WebviewWindow at /widget.html,
 * positioned bottom-right of the primary monitor (matching macOS behavior).
 */
export async function openWidgetWindow(): Promise<void> {
  const release = reserveWidgetStart();
  let releaseWhenDone = true;
  try {
    const [ownerCurrent, closeCurrent, recordingCurrent] = await Promise.all([requireSupportOwner(), requireMainCloseHandler(), requireMainRecordingHandler()]);
    const checkCurrent = () => {
      if (!ownerCurrent() || !closeCurrent() || !recordingCurrent()) throw new Error("Widget owner changed");
    };
    checkCurrent();
    const existing = await WebviewWindow.getByLabel("recording-widget");
    checkCurrent();
    if (existing) {
      await existing.show();
      await existing.setFocus();
      return;
    }

    // Position bottom-right of primary monitor with margin
    const width = 470;
    const height = 60;
    const margin = 20;
    let x = margin;
    let y = margin;

    try {
      const monitors = await availableMonitors();
      const primary = monitors.find((m) => m.name === "") || monitors[0];
      if (primary) {
        x = Math.round((primary.position.x + primary.size.width) / primary.scaleFactor - width - margin);
        y = Math.round((primary.position.y + primary.size.height) / primary.scaleFactor - height - margin - 48); // 48px above taskbar
      }
    } catch (e) {
      console.warn("[Widget] Could not get monitor info:", e);
    }

    try {
      checkCurrent();
      const widget = new WebviewWindow("recording-widget", {
        url: "widget.html",
        title: "Opname",
        width,
        height,
        minWidth: 470,
        minHeight: 60,
        maxHeight: 60,
        decorations: false,
        transparent: true,
        shadow: false,
        resizable: false,
        alwaysOnTop: true,
        skipTaskbar: true,
        center: false,
        visible: false, // start hidden, show after creation completes
        x,
        y,
      });

      // Keep the reservation until native creation settles, not merely until listeners register.
      const listeners: (() => void)[] = [];
      let nativeSettled = false;
      let created = false;
      try {
        await new Promise<void>((resolve, reject) => {
          void widget.once("tauri://created", () => { created = true; nativeSettled = true; release(); resolve(); }).then(stop => listeners.push(stop), reject);
          void widget.once("tauri://error", () => { nativeSettled = true; release(); reject(new Error("Widget creation failed")); }).then(stop => listeners.push(stop), reject);
        });
        checkCurrent();
        await widget.show();
        await widget.setFocus();
        const { useRecordingStore } = await import("../stores/recordingStore");
        const { phase, recordingStartedAt, pausedAt, pausedDuration } = useRecordingStore.getState();
        await emit("widget-sync-timer", { phase, recordingStartedAt, pausedAt, pausedDuration });
      } catch (error) {
        if (!nativeSettled || created) {
          // A failed listener does not prove that the pending native create failed.
          try { await widget.destroy(); }
          catch { if (!nativeSettled) releaseWhenDone = false; }
        }
        throw error;
      } finally { if (releaseWhenDone) listeners.forEach(stop => stop()); }

    } catch (err) {
      console.error("[Widget] Failed to create window:", err);
      throw err;
    }
  } finally { if (releaseWhenDone) release(); }
}

export async function closeWidgetWindow(): Promise<void> {
  const widget = await WebviewWindow.getByLabel("recording-widget");
  if (widget) {
    await widget.close();
  }
}
