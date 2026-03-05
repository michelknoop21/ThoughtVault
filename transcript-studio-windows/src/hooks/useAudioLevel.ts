import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";

/**
 * Subscribes to the "audio-level" event emitted by the Rust backend at ~60Hz.
 * Returns the current RMS level as a percentage 0–100.
 */
export function useAudioLevel(): number {
  const [level, setLevel] = useState(0);

  useEffect(() => {
    const unlisten = listen<number>("audio-level", (event) => {
      // RMS 0.0–1.0, amplify for display and clamp
      const pct = Math.min(100, event.payload * 100 * 4);
      setLevel(pct);
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  return level;
}
