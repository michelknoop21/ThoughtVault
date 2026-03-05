import { WebviewWindow } from "@tauri-apps/api/webviewWindow";

/**
 * Opens the floating recording widget window.
 * The widget is a separate Tauri WebviewWindow at /widget.html.
 */
export async function openWidgetWindow(): Promise<void> {
  const existing = await WebviewWindow.getByLabel("recording-widget");
  if (existing) {
    await existing.show();
    await existing.setFocus();
    return;
  }

  new WebviewWindow("recording-widget", {
    url: "widget.html",
    title: "Opname widget",
    width: 240,
    height: 140,
    minWidth: 200,
    minHeight: 100,
    decorations: false,
    transparent: true,
    resizable: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    center: false,
    x: 20,
    y: 20,
  });
}

export async function closeWidgetWindow(): Promise<void> {
  const widget = await WebviewWindow.getByLabel("recording-widget");
  if (widget) {
    await widget.close();
  }
}
