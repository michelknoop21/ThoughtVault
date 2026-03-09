import { WebviewWindow } from "@tauri-apps/api/webviewWindow";

/**
 * Opens the floating recording widget window.
 * The widget is a separate Tauri WebviewWindow at /widget.html.
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

  console.log("[Widget] Creating new widget window");
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
  console.log("[Widget] Widget window created");
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
