import { getName } from "@tauri-apps/api/app";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect } from "react";
import { useRecordingStore } from "../../stores/recordingStore";

// Let Windows own the caption buttons, snap menu, resize borders and system menu.
export function TitleBar() {
  const phase = useRecordingStore((state) => state.phase);
  useEffect(() => {
    const status = phase === "recording" ? "Opname actief" : phase === "paused" ? "Opname gepauzeerd" : phase === "stopping" ? "Opname stoppen…" : "";
    let active = true;
    void getName().then(name => {
      if (active) return getCurrentWindow().setTitle(status ? `${name} · ${status}` : name);
    }).catch(console.error);
    return () => { active = false; };
  }, [phase]);
  return null;
}
