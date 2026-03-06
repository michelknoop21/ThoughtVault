import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { createAudioLevelNormalizer } from "../services/audioLevel";

/**
 * Subscribes to the "audio-level" event emitted by the Rust backend at ~60Hz.
 * Returns the current RMS level as a percentage 0–100.
 */
export function useAudioLevel(): number {
  const [level, setLevel] = useState(0);

  useEffect(() => {
    const normalizeLevel = createAudioLevelNormalizer();

    const unlisten = listen<number>("audio-level", (event) => {
      setLevel(normalizeLevel(event.payload));
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  return level;
}
