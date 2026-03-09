import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { createAudioLevelNormalizer } from "../services/audioLevel";

/** Max samples to keep in history (≈1 second at 60Hz) */
const HISTORY_SIZE = 60;

/**
 * Subscribes to the "audio-level" event emitted by the Rust backend at ~60Hz.
 * Returns the current RMS level as a percentage 0-100.
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

/**
 * Returns a mutable ref to a rolling history of audio levels normalized to 0.0-1.0.
 * Uses a ref instead of state to avoid triggering React re-renders at ~60Hz.
 * The WaveformVisualizer reads from this ref via requestAnimationFrame.
 */
export function useAudioLevelsRef(): React.MutableRefObject<number[]> {
  const bufferRef = useRef<number[]>([]);

  useEffect(() => {
    const normalizeLevel = createAudioLevelNormalizer();

    const unlisten = listen<number>("audio-level", (event) => {
      const normalized = normalizeLevel(event.payload) / 100; // 0-100 → 0.0-1.0
      const buf = bufferRef.current;
      buf.push(normalized);
      if (buf.length > HISTORY_SIZE) buf.shift();
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  return bufferRef;
}
