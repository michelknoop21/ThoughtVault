import { useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { stopRecording, pauseRecording, resumeRecording } from "../../services/tauriCommands";
import { WaveformVisualizer } from "./WaveformVisualizer";
import {
  Stop24Regular,
  Pause24Regular,
  Play24Regular,
} from "@fluentui/react-icons";

export function RecordingWidget() {
  const [elapsed, setElapsed] = useState(0);
  const [isPaused, setIsPaused] = useState(false);
  const [audioLevel, setAudioLevel] = useState(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    // Start timer
    timerRef.current = setInterval(() => {
      setElapsed((s) => s + 1);
    }, 1000);

    // Listen for audio level updates from Rust backend
    const unlistenLevel = listen<number>("audio-level", (event) => {
      // RMS 0.0–1.0 → percentage 0–100
      setAudioLevel(Math.min(100, event.payload * 100 * 4));
    });

    // Listen for recording stopped event
    const unlistenStopped = listen("recording-stopped", () => {
      if (timerRef.current) clearInterval(timerRef.current);
      getCurrentWindow().close();
    });

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      unlistenLevel.then((fn) => fn());
      unlistenStopped.then((fn) => fn());
    };
  }, []);

  async function handleStop() {
    if (timerRef.current) clearInterval(timerRef.current);
    try {
      await stopRecording();
    } catch (e) {
      console.error("[Widget] Stop failed:", e);
    }
  }

  async function handlePauseResume() {
    try {
      if (isPaused) {
        await resumeRecording();
        timerRef.current = setInterval(() => setElapsed((s) => s + 1), 1000);
        setIsPaused(false);
      } else {
        await pauseRecording();
        if (timerRef.current) clearInterval(timerRef.current);
        setIsPaused(true);
      }
    } catch (e) {
      console.error("[Widget] Pause/resume failed:", e);
    }
  }

  const minutes = Math.floor(elapsed / 60).toString().padStart(2, "0");
  const seconds = (elapsed % 60).toString().padStart(2, "0");

  return (
    <div className="widget-shell">
      <div className="widget-drag-region" data-tauri-drag-region>
        <span className="widget-title">Opname</span>
      </div>

      <div className="widget-status">
        <div className={`widget-status-dot${isPaused ? " paused" : ""}`} />
        <span className="widget-timer">{minutes}:{seconds}</span>
      </div>

      <div className="widget-waveform">
        <WaveformVisualizer level={audioLevel} isPaused={isPaused} />
      </div>

      <div className="widget-controls">
        <button
          className="widget-btn"
          onClick={handlePauseResume}
          title={isPaused ? "Hervatten" : "Pauzeren"}
        >
          {isPaused
            ? <Play24Regular style={{ fontSize: 18 }} />
            : <Pause24Regular style={{ fontSize: 18 }} />
          }
        </button>
        <button
          className="widget-btn widget-btn-stop"
          onClick={handleStop}
          title="Stoppen"
        >
          <Stop24Regular style={{ fontSize: 20 }} />
        </button>
      </div>
    </div>
  );
}
