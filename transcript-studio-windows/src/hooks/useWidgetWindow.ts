import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { availableMonitors } from "@tauri-apps/api/window";

/**
 * Opens the floating recording widget window.
 * The widget is a separate Tauri WebviewWindow at /widget.html,
 * positioned bottom-right of the primary monitor (matching macOS behavior).
 */
export async function openWidgetWindow(): Promise<void> {
  console.log("[Widget] Opening widget window");
  const existing = await WebviewWindow.getByLabel("recording-widget");
  if (existing) {
    console.log("[Widget] Existing widget found — showing and focusing");
    await existing.show();
    await existing.setFocus();
    return;
  }

  // Position bottom-right of primary monitor with margin
  const width = 380;
  const height = 56;
  const margin = 20;
  let x = margin;
  let y = margin;

  try {
    const monitors = await availableMonitors();
    const primary = monitors.find((m) => m.name === "") || monitors[0];
    if (primary) {
      x = Math.round(primary.position.x + primary.size.width / primary.scaleFactor - width - margin);
      y = Math.round(primary.position.y + primary.size.height / primary.scaleFactor - height - margin - 48); // 48px above taskbar
    }
  } catch (e) {
    console.warn("[Widget] Could not get monitor info:", e);
  }

  console.log("[Widget] Creating widget window at", x, y);
  try {
    new WebviewWindow("recording-widget", {
      url: "widget.html",
      title: "Opname",
      width,
      height,
      minWidth: 300,
      minHeight: 56,
      maxHeight: 56,
      decorations: false,
      transparent: true,
      resizable: false,
      alwaysOnTop: true,
      skipTaskbar: true,
      center: false,
      x,
      y,
    });
    console.log("[Widget] Widget window created");
  } catch (err) {
    console.error("[Widget] Failed to create window:", err);
    throw err;
  }
}

export async function closeWidgetWindow(): Promise<void> {
  console.log("[Widget] Closing widget window");
  const widget = await WebviewWindow.getByLabel("recording-widget");
  if (widget) {
    await widget.close();
    console.log("[Widget] Widget closed");
  } else {
    console.log("[Widget] No widget found to close");
  }
}
