import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import {
  MicRecord24Regular,
  Stop24Regular,
  Pause24Regular,
  Play24Regular,
  ArrowLeft24Regular,
  VideoChat24Regular,
} from "@fluentui/react-icons";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useAudioLevel } from "../hooks/useAudioLevel";
import { openWidgetWindow, closeWidgetWindow } from "../hooks/useWidgetWindow";
import {
  startRecording,
  stopRecording,
  pauseRecording,
  resumeRecording,
  getNetworkStatus,
} from "../services/tauriCommands";
import { api } from "../services/api";
import { createSSEClient } from "../services/sse";
import { enqueue } from "../services/offlineQueue";
import { WaveformVisualizer } from "../components/recording/WaveformVisualizer";
import type { TranscriptTask } from "../types";

// Profile icon mapping
function getProfileIcon(name: string): string {
  const lower = name.toLowerCase();
  if (lower.includes("zakelijk")) return "\u{1F4BC}";
  if (lower.includes("informeel")) return "\u{1F4AC}";
  if (lower.includes("technisch")) return "\u{1F527}";
  return "\u{1F4CB}";
}

export function RecordingPage() {
  const navigate = useNavigate();
  const {
    mode, phase, autoStart,
    setMode, setPhase, setFilePath, setElapsedSeconds,
    setAutoStart, setCurrentTask, reset,
  } = useRecordingStore();
  const settings = useSettingsStore();
  const { addTranscript } = useTranscriptsStore();
  const profiles = useProfilesStore((s) => s.profiles);

  const [selectedProfileId, setSelectedProfileId] = useState(settings.default_profile_id);
  const [task, setTask] = useState<Partial<TranscriptTask> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const audioLevel = useAudioLevel();
  const elapsedRef = useRef(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const filePathRef = useRef<string>("");

  useEffect(() => {
    if (autoStart && phase === "idle") {
      setAutoStart(false);
      handleStartRecording();
    }
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  // Listen for recording-stopped event from widget
  useEffect(() => {
    const unlisten = listen<{ file_path: string; duration_seconds: number }>(
      "recording-stopped",
      (event) => {
        filePathRef.current = event.payload.file_path || filePathRef.current;
        if (phase === "recording" || phase === "paused") {
          handleUpload(filePathRef.current);
        }
      }
    );
    return () => { unlisten.then((fn) => fn()); };
  }, [phase]);

  function startTimer() {
    elapsedRef.current = 0;
    timerRef.current = setInterval(() => {
      elapsedRef.current += 1;
      setElapsedSeconds(elapsedRef.current);
    }, 1000);
  }

  function stopTimer() {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }

  async function handleStartRecording() {
    setPhase("preparing");
    setError(null);

    try {
      const outputDir = await getRecordingsDir();
      const filePath = await startRecording(null, mode, outputDir);
      filePathRef.current = filePath;
      setFilePath(filePath);
      setPhase("recording");
      startTimer();
      // Open floating widget
      openWidgetWindow().catch(console.error);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Opname starten mislukt");
      setPhase("idle");
    }
  }

  async function handleStopRecording() {
    setPhase("stopping");
    stopTimer();

    try {
      const result = await stopRecording();
      const filePath = result.file_path || filePathRef.current;
      closeWidgetWindow().catch(console.error);
      await handleUpload(filePath);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Stoppen mislukt");
      setPhase("idle");
    }
  }

  async function handleUpload(filePath: string) {
    setPhase("uploading");

    const networkStatus = await getNetworkStatus().catch(() => ({ is_online: false }));

    if (!networkStatus.is_online) {
      await enqueue({ file_path: filePath, profile_id: selectedProfileId, mode });
      setError("Geen internetverbinding. Opname is toegevoegd aan de wachtrij en wordt verstuurd zodra u weer online bent.");
      reset();
      return;
    }

    try {
      const { task_id } = await api.uploadRecording(filePath, selectedProfileId, mode);

      const initialTask: TranscriptTask = {
        task_id,
        status: "uploading",
        progress: 0,
        mode,
        created_at: new Date().toISOString(),
      };
      setTask(initialTask);
      setCurrentTask(initialTask);

      const sseClient = createSSEClient(api.getStreamUrl(task_id));
      sseClient.connect(
        (update) => {
          setTask((prev) => ({ ...prev, ...update }));
          setCurrentTask({ ...initialTask, ...update });
        },
        (err) => {
          console.error("[SSE] Error:", err);
        },
        async () => {
          const transcripts = await api.getTranscripts({ limit: 1 });
          if (transcripts[0]) addTranscript(transcripts[0]);
          reset();
          navigate("/transcripts");
        }
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload mislukt");
      setPhase("idle");
    }
  }

  async function handlePause() {
    await pauseRecording();
    setPhase("paused");
    stopTimer();
  }

  async function handleResume() {
    await resumeRecording();
    setPhase("recording");
    startTimer();
  }

  const elapsed = useRecordingStore((s) => s.elapsedSeconds);
  const canGoBack = phase === "idle";

  return (
    <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 12,
          padding: "12px 16px",
          borderBottom: "1px solid var(--stroke-divider)",
          background: "var(--surface-card)",
          flexShrink: 0,
        }}
      >
        <button
          onClick={() => canGoBack && navigate("/")}
          disabled={!canGoBack}
          className="btn btn-ghost"
          style={{ width: 36, height: 36, padding: 0, opacity: canGoBack ? 1 : 0.4 }}
          title="Terug"
        >
          <ArrowLeft24Regular style={{ fontSize: 20 }} />
        </button>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {mode === "combined"
            ? <VideoChat24Regular style={{ color: "var(--fill-accent-default)", fontSize: 22 }} />
            : <MicRecord24Regular style={{ color: "var(--fill-accent-default)", fontSize: 22 }} />
          }
          <h1 style={{ fontSize: 16, fontWeight: 600, color: "var(--text-primary)" }}>
            {mode === "combined" ? "Videocall opnemen" : "Vergadering opnemen"}
          </h1>
        </div>
      </div>

      {/* Body */}
      <div
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          padding: 32,
          gap: 24,
          maxWidth: 600,
          margin: "0 auto",
          width: "100%",
          overflowY: "auto",
        }}
      >
        {phase === "idle" && (
          <IdleState
            mode={mode}
            profileId={selectedProfileId}
            profiles={profiles}
            onSetMode={setMode}
            onSetProfile={setSelectedProfileId}
            onStart={handleStartRecording}
          />
        )}

        {phase === "preparing" && (
          <div style={{ textAlign: "center" }}>
            <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center", margin: "0 auto 16px" }}>
              <div className="mic-pulse-ring mic-pulse-ring-1" />
              <div className="mic-pulse-ring mic-pulse-ring-2" />
              <div
                style={{
                  width: 96,
                  height: 96,
                  borderRadius: "50%",
                  background: "rgba(229, 0, 116, 0.08)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  animation: "widget-pulse 1.5s ease-in-out infinite",
                }}
              >
                <MicRecord24Regular style={{ fontSize: 40, color: "var(--fill-accent-default)" }} />
              </div>
            </div>
            <p style={{ color: "var(--text-secondary)" }}>Microfoon initialiseren...</p>
          </div>
        )}

        {(phase === "recording" || phase === "paused") && (
          <ActiveState
            elapsed={elapsed}
            audioLevel={audioLevel}
            isPaused={phase === "paused"}
            task={task}
            onStop={handleStopRecording}
            onPause={handlePause}
            onResume={handleResume}
          />
        )}

        {phase === "uploading" && <UploadingState task={task} />}
      </div>

      {error && (
        <div
          style={{
            margin: 16,
            padding: "10px 14px",
            background: "rgba(188, 0, 22, 0.08)",
            border: "1px solid rgba(188, 0, 22, 0.25)",
            borderRadius: 8,
            fontSize: 13,
            color: "var(--text-error)",
          }}
        >
          {error}
        </div>
      )}
    </div>
  );
}

function IdleState({
  mode, profileId, profiles, onSetMode, onSetProfile, onStart,
}: {
  mode: string;
  profileId: string;
  profiles: import("../types").Profile[];
  onSetMode: (m: "microphone" | "combined") => void;
  onSetProfile: (id: string) => void;
  onStart: () => void;
}) {
  return (
    <div style={{ width: "100%", display: "flex", flexDirection: "column", gap: 28, alignItems: "center" }}>
      {/* Section header */}
      <div style={{ textAlign: "center" }}>
        <p style={{
          fontSize: 13,
          fontWeight: 700,
          color: "var(--fill-accent-default)",
          textTransform: "uppercase",
          letterSpacing: "0.08em",
          marginBottom: 4,
        }}>
          NIEUWE OPNAME
        </p>
        <p style={{ fontSize: 13, color: "var(--text-tertiary)" }}>
          Kies bron en profiel, klik daarna om op te nemen
        </p>
      </div>

      {/* Mode selector */}
      <div style={{ width: "100%" }}>
        <p style={{ fontSize: 12, fontWeight: 600, color: "var(--text-tertiary)", marginBottom: 8, textTransform: "uppercase", letterSpacing: "0.05em" }}>
          Opnamemodus
        </p>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          {(["combined", "microphone"] as const).map((m) => (
            <button
              key={m}
              onClick={() => onSetMode(m)}
              className="card"
              style={{
                padding: 16,
                textAlign: "left",
                cursor: "pointer",
                border: mode === m
                  ? "2px solid var(--fill-accent-default)"
                  : "1px solid var(--stroke-card)",
                background: mode === m ? "rgba(229, 0, 116, 0.05)" : "var(--surface-card)",
                transition: "all 67ms ease",
              }}
            >
              <div style={{ marginBottom: 8, color: "var(--fill-accent-default)" }}>
                {m === "combined"
                  ? <VideoChat24Regular style={{ fontSize: 24 }} />
                  : <MicRecord24Regular style={{ fontSize: 24 }} />
                }
              </div>
              <p style={{ fontWeight: 600, color: "var(--text-primary)", fontSize: 14 }}>
                {m === "combined" ? "Videocall" : "Fysieke meeting"}
              </p>
              <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 2 }}>
                {m === "combined" ? "Microfoon + systeemaudio" : "Alleen microfoon"}
              </p>
            </button>
          ))}
        </div>
      </div>

      {/* Profile selector as cards with emoji icons */}
      <div style={{ width: "100%" }}>
        <p style={{ fontSize: 12, fontWeight: 600, color: "var(--text-tertiary)", marginBottom: 8, textTransform: "uppercase", letterSpacing: "0.05em" }}>
          Profiel
        </p>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {profiles.map((profile) => (
            <button
              key={profile.id}
              onClick={() => onSetProfile(profile.id)}
              className={`profile-chip ${profileId === profile.id ? "active" : ""}`}
            >
              <span className="profile-chip-icon">{getProfileIcon(profile.name)}</span>
              <span className="profile-chip-name">{profile.name}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Large pink mic button with pulse rings */}
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12, paddingTop: 8 }}>
        <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center", width: 220, height: 220 }}>
          <div className="mic-pulse-ring mic-pulse-ring-1" />
          <div className="mic-pulse-ring mic-pulse-ring-2" />
          <div className="mic-pulse-ring mic-pulse-ring-3" />
          <button
            onClick={onStart}
            className="mic-button-large"
            title="Opname starten"
          >
            <MicRecord24Regular style={{ fontSize: 48, color: "#fff" }} />
          </button>
        </div>
        <p style={{ fontSize: 13, color: "var(--text-tertiary)" }}>
          Klik om op te nemen
        </p>
      </div>
    </div>
  );
}

function ActiveState({
  elapsed, audioLevel, isPaused, task, onStop, onPause, onResume,
}: {
  elapsed: number;
  audioLevel: number;
  isPaused: boolean;
  task: Partial<TranscriptTask> | null;
  onStop: () => void;
  onPause: () => void;
  onResume: () => void;
}) {
  const minutes = Math.floor(elapsed / 60).toString().padStart(2, "0");
  const seconds = (elapsed % 60).toString().padStart(2, "0");

  return (
    <div style={{ width: "100%", display: "flex", flexDirection: "column", alignItems: "center", gap: 20 }}>
      {/* Timer */}
      <div style={{ textAlign: "center" }}>
        <div
          style={{
            fontSize: 72,
            fontWeight: 200,
            fontVariantNumeric: "tabular-nums",
            color: "var(--text-primary)",
            letterSpacing: "0.02em",
            lineHeight: 1,
            marginBottom: 10,
          }}
        >
          {minutes}:{seconds}
        </div>
        {/* LIVE badge */}
        <div className="live-badge">
          <span className={`live-dot ${isPaused ? "paused" : ""}`} />
          {isPaused ? "GEPAUZEERD" : "LIVE"}
        </div>
      </div>

      {/* Waveform */}
      <div
        className="card"
        style={{ padding: "16px 20px", width: "100%", height: 80 }}
      >
        <WaveformVisualizer level={audioLevel} isPaused={isPaused} height={48} />
      </div>

      {/* Large mic button */}
      <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center", width: 160, height: 160 }}>
        {!isPaused && (
          <>
            <div className="mic-pulse-ring mic-pulse-ring-1" />
            <div className="mic-pulse-ring mic-pulse-ring-2" />
          </>
        )}
        <button
          onClick={onStop}
          className="mic-button-large"
          title="Stoppen"
        >
          <MicRecord24Regular style={{ fontSize: 44, color: "#fff" }} />
        </button>
      </div>
      <p style={{ fontSize: 13, color: "var(--text-tertiary)", marginTop: -8 }}>
        {isPaused ? "Klik om te hervatten" : "Klik om te pauzeren"}
      </p>

      {/* Live transcription card */}
      {task?.raw_transcription && (
        <div
          className="card"
          style={{ padding: 14, width: "100%", textAlign: "left", maxHeight: 130, overflow: "hidden" }}
        >
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
            <span style={{
              fontSize: 11,
              fontWeight: 700,
              color: "var(--fill-accent-default)",
              textTransform: "uppercase",
              letterSpacing: "0.06em",
            }}>
              LIVE TRANSCRIPTIE
            </span>
            <span style={{ fontSize: 11, color: "var(--text-tertiary)" }}>Op apparaat</span>
          </div>
          <p style={{ fontSize: 13, color: "var(--text-secondary)", lineHeight: 1.5 }}>
            {task.raw_transcription}
          </p>
        </div>
      )}

      {/* Control buttons: PAUZE / NOTITIE / STOP */}
      <div className="recording-controls">
        <button
          onClick={isPaused ? onResume : onPause}
          className="recording-control-btn"
          title={isPaused ? "Hervatten" : "Pauzeren"}
        >
          {isPaused
            ? <Play24Regular style={{ fontSize: 24, color: "var(--text-primary)" }} />
            : <Pause24Regular style={{ fontSize: 24, color: "var(--text-primary)" }} />
          }
          <span className="recording-control-label">
            {isPaused ? "HERVAT" : "PAUZE"}
          </span>
        </button>
        <button
          className="recording-control-btn"
          title="Notitie"
          style={{ opacity: 0.5, cursor: "default" }}
          disabled
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" style={{ color: "var(--text-primary)" }}>
            <path d="M4 4h10l6 6v10a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
            <path d="M14 4v6h6M8 14h8M8 18h5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <span className="recording-control-label">NOTITIE</span>
        </button>
        <button
          onClick={onStop}
          className="recording-control-btn stop"
          title="Stoppen"
        >
          <Stop24Regular style={{ fontSize: 24 }} />
          <span className="recording-control-label">STOP</span>
        </button>
      </div>
    </div>
  );
}

function UploadingState({ task }: { task: Partial<TranscriptTask> | null }) {
  const progress = task?.progress ?? 0;
  const status = task?.status ?? "uploading";

  const statusLabels: Record<string, string> = {
    uploading: "Audio wordt geupload...",
    converting: "Audio wordt geconverteerd...",
    transcribing: "Spraak wordt omgezet naar tekst...",
    generating: "AI notulen structureren...",
    completed: "Voltooid!",
    failed: "Mislukt",
  };
  const statusSubLabels: Record<string, string> = {
    uploading: "Uploaden",
    converting: "Converteren",
    transcribing: "Transcriberen",
    generating: "Structureren",
    completed: "Klaar",
    failed: "Fout",
  };
  const label = statusLabels[status] ?? "Verwerken...";
  const subLabel = statusSubLabels[status] ?? "Verwerken";

  // Progress steps
  const steps = [
    { key: "uploading", label: "Audio uploaden" },
    { key: "converting", label: "Audio converteren" },
    { key: "transcribing", label: "Spraak naar tekst" },
    { key: "generating", label: "AI notulen structureren" },
  ];
  const statusOrder = ["uploading", "converting", "transcribing", "generating", "completed"];
  const currentIdx = statusOrder.indexOf(status);

  // Circular progress ring calculations
  const radius = 60;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (progress / 100) * circumference;

  return (
    <div className="processing-view">
      {/* Title */}
      <p style={{ fontSize: 20, fontWeight: 600, color: "var(--text-primary)" }}>
        AI Processing
      </p>

      {/* Circular progress */}
      <div className="circular-progress">
        <svg width="140" height="140">
          <circle className="progress-track" cx="70" cy="70" r={radius} />
          <circle
            className="progress-fill"
            cx="70"
            cy="70"
            r={radius}
            strokeDasharray={circumference}
            strokeDashoffset={offset}
          />
        </svg>
        <div className="progress-text">
          <span style={{ fontSize: 32, fontWeight: 600, color: "var(--text-primary)" }}>
            {progress}%
          </span>
        </div>
      </div>

      {/* Status text */}
      <div style={{ textAlign: "center" }}>
        <p style={{ fontSize: 14, color: "var(--text-secondary)", marginBottom: 4 }}>
          {label}
        </p>
        <p style={{ fontSize: 12, color: "var(--text-tertiary)" }}>
          {subLabel}
        </p>
      </div>

      {/* Progress steps card */}
      <div className="card" style={{ width: "100%", padding: "16px 20px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
          <div style={{
            width: 8,
            height: 8,
            borderRadius: "50%",
            background: "var(--fill-accent-default)",
          }} />
          <span style={{
            fontSize: 11,
            fontWeight: 700,
            textTransform: "uppercase",
            letterSpacing: "0.06em",
            color: "var(--text-tertiary)",
          }}>
            VOORTGANG
          </span>
        </div>
        <div style={{ display: "flex", flexDirection: "column" }}>
          {steps.map((step, i) => {
            const stepIdx = statusOrder.indexOf(step.key);
            const isCompleted = currentIdx > stepIdx;
            const isActive = currentIdx === stepIdx;
            const stateClass = isCompleted ? "completed" : isActive ? "active" : "pending";

            return (
              <div key={step.key} className={`processing-step ${stateClass}`}>
                <span className="step-icon">
                  {isCompleted ? (
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                      <path d="M2 6l3 3 5-5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                    </svg>
                  ) : isActive ? (
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                      <circle cx="6" cy="6" r="5" stroke="currentColor" strokeWidth="1.5" strokeDasharray="8 4"/>
                    </svg>
                  ) : (
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                      <circle cx="6" cy="6" r="2.5" fill="currentColor"/>
                    </svg>
                  )}
                </span>
                <span>{step.label}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

async function getRecordingsDir(): Promise<string> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<string>("get_recordings_dir");
}
