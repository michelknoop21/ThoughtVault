import { useEffect, useRef, useState } from "react";
import { emit, listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { stopRecording, pauseRecording, resumeRecording } from "../../services/tauriCommands";
import { WaveformVisualizer } from "./WaveformVisualizer";
import { useAudioLevelsRef, useAudioBandsRef } from "../../hooks/useAudioLevel";
import {
  Stop24Regular,
  Pause24Regular,
  Play24Regular,
} from "../ui/StudioIcons";

type WidgetState = "recording" | "paused" | "stopping";

export function RecordingWidget() {
  const [elapsed, setElapsed] = useState(0);
  const [state, setState] = useState<WidgetState>("recording");
  const levelsBufferRef = useAudioLevelsRef();
  const bandsBufferRef = useAudioBandsRef();
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
    const unlistenSync = listen<{ phase: string; recordingStartedAt: number | null; pausedAt: number | null; pausedDuration: number }>(
      "widget-sync-timer",
      (event) => {
        // A newly loaded widget may have missed the native stop event.
        if (!event.payload.recordingStartedAt) {
          if (timerRef.current) clearInterval(timerRef.current);
          void getCurrentWindow().close().catch(console.error);
          return;
        }
        if (event.payload.recordingStartedAt) {
          startedAtRef.current = event.payload.recordingStartedAt;
          pausedDurationRef.current = event.payload.pausedDuration ?? 0;
          pausedAtRef.current = event.payload.pausedAt;
          setState(event.payload.phase === "paused" ? "paused" : event.payload.phase === "stopping" ? "stopping" : "recording");
          setElapsed(calcElapsed());
        }
      }
    );

    unlistenSync.then(() => emit("widget-ready")).catch(console.error);

    timerRef.current = setInterval(() => {
      setElapsed(calcElapsed());
    }, 1000);

    const unlistenStopped = listen("recording-stopped", () => {
      if (timerRef.current) clearInterval(timerRef.current);
      getCurrentWindow().close();
    });

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      unlistenSync.then((fn) => fn());
      unlistenStopped.then((fn) => fn());
    };
  }, []);

  async function handleStop() {
    setState("stopping");
    try {
      await stopRecording();
    } catch (e) {
      console.error("[Widget] Stop failed:", e);
      setState("recording");
    }
  }

  async function handlePauseResume() {
    try {
      if (state === "paused") {
        await resumeRecording();
      } else {
        await pauseRecording();
      }
    } catch (e) {
      console.error("[Widget] Pause/resume failed:", e);
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
        <span className="widget-drag-handle" aria-hidden="true">{Array.from({ length: 6 }, (_, i) => <i key={i} />)}</span>
        {/* Status badge */}
        <div className={`widget-badge ${state}`}>
          <span className={`widget-badge-dot ${state}`} />
          <span className="widget-badge-label">
            {isStopping ? "STOP..." : isPaused ? "PAUZE" : "REC"}
          </span>
        </div>

        {/* Waveform */}
        <div className="widget-waveform">
          <WaveformVisualizer levelsRef={levelsBufferRef} bandsRef={bandsBufferRef} isActive={!isPaused && !isStopping} height={32} />
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
