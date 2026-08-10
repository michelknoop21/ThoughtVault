import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";

/**
 * History length of processed envelope levels (matches EnvelopeConfig and
 * AudioEnvelopeConfig.historyLength on macOS): 90 samples @ 30 Hz = 3.0 s.
 */
export const HISTORY_SIZE = 90;

/**
 * Subscribes to the "audio-level" event emitted by the Rust backend at ~30Hz.
 * The payload is the already-processed envelope scalar (0.0–1.0). Returns it
 * as a percentage 0-100 for simple meter UIs.
 */
export function useAudioLevel(): number {
  const [level, setLevel] = useState(0);

  useEffect(() => {
    const unlisten = listen<number>("audio-level", (event) => {
      setLevel(Math.max(0, Math.min(100, event.payload * 100)));
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  return level;
}

/**
 * Returns a mutable ref to a rolling history (HISTORY_SIZE) of the processed
 * envelope levels (0.0–1.0). Uses a ref instead of state to avoid React
 * re-renders at ~30Hz. The WaveformVisualizer reads from this ref via
 * requestAnimationFrame.
 */
export function useAudioLevelsRef(): React.MutableRefObject<number[]> {
  const bufferRef = useRef<number[]>([]);

  useEffect(() => {
    const unlisten = listen<number>("audio-level", (event) => {
      const buf = bufferRef.current;
      buf.push(Math.max(0, Math.min(1, event.payload)));
      if (buf.length > HISTORY_SIZE) buf.shift();
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  return bufferRef;
}
