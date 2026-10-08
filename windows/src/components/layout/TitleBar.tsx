import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect } from "react";
import { useRecordingStore } from "../../stores/recordingStore";

// Let Windows own the caption buttons, snap menu, resize borders and system menu.
export function TitleBar() {
  const phase = useRecordingStore((state) => state.phase);
  useEffect(() => {
    const status = phase === "recording" ? "Opname actief" : phase === "paused" ? "Opname gepauzeerd" : phase === "stopping" ? "Opname stoppen…" : "";
    void getCurrentWindow().setTitle(status ? `ThoughtVault · ${status}` : "ThoughtVault").catch(console.error);
  }, [phase]);
  return null;
}
