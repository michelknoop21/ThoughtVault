import { useEffect, useRef, useState } from "react";
import { listen, emit } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { WaveformVisualizer } from "./WaveformVisualizer";
import { useAudioLevelsRef } from "../../hooks/useAudioLevel";
import {
  Stop24Regular,
  Pause24Regular,
  Play24Regular,
} from "@fluentui/react-icons";

type WidgetState = "recording" | "paused" | "stopping";

export function RecordingWidget() {
  const [elapsed, setElapsed] = useState(0);
  const [state, setState] = useState<WidgetState>("recording");
  const levelsBufferRef = useAudioLevelsRef();
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startedAtRef = useRef<number>(Date.now());
  const pausedDurationRef = useRef<number>(0);
  const pausedAtRef = useRef<number | null>(null);

  useEffect(() => {
    function calcElapsed() {
      const now = Date.now();
      const totalPaused = pausedDurationRef.current + (pausedAtRef.current ? now - pausedAtRef.current : 0);
      return Math.floor((now - startedAtRef.current - totalPaused) / 1000);
    }

    // Receive synced start time from main window
    const unlistenSync = listen<{ recordingStartedAt: number | null; pausedDuration: number }>(
      "widget-sync-timer",
      (event) => {
        if (event.payload.recordingStartedAt) {
          startedAtRef.current = event.payload.recordingStartedAt;
          pausedDurationRef.current = event.payload.pausedDuration ?? 0;
          setElapsed(calcElapsed());
        }
      }
    );

    timerRef.current = setInterval(() => {
      setElapsed(calcElapsed());
    }, 1000);

    const unlistenStopped = listen("recording-stopped", () => {
      if (timerRef.current) clearInterval(timerRef.current);
      getCurrentWindow().close();
    });
    const unlistenState = listen<{ phase: string; recordingStartedAt: number | null; pausedAt: number | null; pausedDuration: number }>("widget-recording-state", ({ payload }) => {
      if (["recording", "paused", "stopping"].includes(payload.phase)) setState(payload.phase as WidgetState);
      if (payload.recordingStartedAt) startedAtRef.current = payload.recordingStartedAt;
      pausedAtRef.current = payload.pausedAt;
      pausedDurationRef.current = payload.pausedDuration;
    });

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      unlistenSync.then((fn) => fn());
      unlistenStopped.then((fn) => fn());
      unlistenState.then((fn) => fn());
    };
  }, []);

  async function handleStop() {
    setState("stopping");
    try {
      await emit("widget-recording-action", "stop");
    } catch (e) {
      console.error("[Widget] Stop failed:", e);
      setState("recording");
    }
  }

  async function handlePauseResume() {
    try {
      await emit("widget-recording-action", state === "paused" ? "resume" : "pause");
    } catch (error) {
      console.error("[Widget] Pause/resume failed:", error);
    }
  }

  const isPaused = state === "paused";
  const isStopping = state === "stopping";
  const hours = Math.floor(elapsed / 3600);
  const minutes = Math.floor((elapsed % 3600) / 60).toString().padStart(2, "0");
  const seconds = (elapsed % 60).toString().padStart(2, "0");
  const timerText = hours > 0
    ? `${hours}:${minutes}:${seconds}`
    : `${minutes}:${seconds}`;

  return (
    <div className={`widget-pill ${isPaused ? "paused" : ""} ${isStopping ? "stopping" : ""}`}>
      {/* Drag region — entire pill is draggable except buttons */}
      <div className="widget-drag-region" data-tauri-drag-region>
        {/* Status badge */}
        <div className={`widget-badge ${state}`}>
          <span className={`widget-badge-dot ${state}`} />
          <span className="widget-badge-label">
            {isStopping ? "STOP..." : isPaused ? "PAUZE" : "REC"}
          </span>
        </div>

        {/* Waveform */}
        <div className="widget-waveform">
          <WaveformVisualizer levelsRef={levelsBufferRef} isActive={!isPaused && !isStopping} height={32} />
        </div>

        {/* Timer */}
        <span className="widget-timer">{timerText}</span>
      </div>

      {/* Divider */}
      <div className="widget-divider" data-tauri-drag-region />

      {/* Action buttons */}
      <div className="widget-actions">
        {!isStopping && (
          <button
            className="widget-btn"
            onClick={handlePauseResume}
            title={isPaused ? "Hervatten" : "Pauzeren"}
          >
            {isPaused
              ? <Play24Regular style={{ fontSize: 14 }} />
              : <Pause24Regular style={{ fontSize: 14 }} />
            }
          </button>
        )}
        <button
          className="widget-btn-stop"
          onClick={handleStop}
          disabled={isStopping}
          title="Stoppen"
        >
          <Stop24Regular style={{ fontSize: 11 }} />
          <span>Stop</span>
        </button>
      </div>
    </div>
  );
}
