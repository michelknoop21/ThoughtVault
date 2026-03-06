import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import {
  MicRecord24Regular,
  Stop24Regular,
  Pause24Regular,
  Play24Regular,
  ArrowLeft24Regular,
  ArrowUpload24Regular,
  VideoChat24Regular,
  Checkmark24Regular,
  Dismiss24Regular,
} from "@fluentui/react-icons";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useAudioLevels } from "../hooks/useAudioLevel";
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
import { SavedRecordings } from "../components/recording/SavedRecordings";
import type { TranscriptTask } from "../types";

import {
  Briefcase24Regular,
  ChatMultiple24Regular,
  Wrench24Regular,
  DocumentText24Regular,
} from "@fluentui/react-icons";

function getProfileIcon(name: string): React.ReactNode {
  const lower = name.toLowerCase();
  const style = { fontSize: 14 };
  if (lower.includes("zakelijk")) return <Briefcase24Regular style={style} />;
  if (lower.includes("informeel")) return <ChatMultiple24Regular style={style} />;
  if (lower.includes("technisch")) return <Wrench24Regular style={style} />;
  return <DocumentText24Regular style={style} />;
}

export function RecordingPage() {
  const navigate = useNavigate();
  const {
    mode, phase, autoStart,
    setMode, setPhase, setFilePath, setElapsedSeconds,
    setAutoStart, reset,
    addBackgroundTask, updateBackgroundTask, removeBackgroundTask, backgroundTasks,
  } = useRecordingStore();
  const settings = useSettingsStore();
  const { addTranscript } = useTranscriptsStore();
  const profiles = useProfilesStore((s) => s.profiles);

  const [selectedProfileId, setSelectedProfileId] = useState(settings.default_profile_id);
  const [error, setError] = useState<string | null>(null);

  const audioLevels = useAudioLevels();
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

      const bgTask: TranscriptTask = {
        task_id,
        status: "uploading",
        progress: 0,
        mode,
        created_at: new Date().toISOString(),
      };

      // Move task to background and reset recording to idle
      addBackgroundTask(bgTask);
      reset();

      // SSE updates go to background task store
      const sseClient = createSSEClient(api.getStreamUrl(task_id));
      sseClient.connect(
        (update) => {
          updateBackgroundTask(task_id, update);
        },
        (err) => {
          console.error("[SSE] Error:", err);
          updateBackgroundTask(task_id, { status: "failed", error_message: "Verbinding verloren" });
        },
        async () => {
          const transcripts = await api.getTranscripts({ limit: 1 });
          if (transcripts[0]) addTranscript(transcripts[0]);
          removeBackgroundTask(task_id);
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
    <div className="page-scroll bg-blobs">
      <div className="bg-blob bg-blob-magenta" style={{ top: "-150px", right: "-100px", left: "auto" }} />
      <div className="bg-blob bg-blob-neon" />
      {/* Header */}
      <div className="page-header flex-row gap-12" style={{ position: "relative", zIndex: 1 }}>
        <button
          onClick={() => canGoBack && navigate("/")}
          disabled={!canGoBack}
          className="btn btn-ghost icon-btn"
          title="Terug"
        >
          <ArrowLeft24Regular />
        </button>
        <div className="flex-row gap-8">
          {mode === "combined"
            ? <VideoChat24Regular className="text-accent" />
            : <MicRecord24Regular className="text-accent" />
          }
          <h1 className="page-title" style={{ fontSize: 16 }}>
            {mode === "combined" ? "Videocall opnemen" : "Vergadering opnemen"}
          </h1>
        </div>
      </div>

      {/* Body */}
      <div className="flex-1 flex-col text-center" style={{ position: "relative", zIndex: 1, alignItems: "center", justifyContent: "center", padding: 32, gap: 24, maxWidth: 600, margin: "0 auto", width: "100%" }}>
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
          <div className="text-center">
            <div className="flex-row" style={{ position: "relative", justifyContent: "center", margin: "0 auto 16px" }}>
              <div className="mic-pulse-ring mic-pulse-ring-1" />
              <div className="mic-pulse-ring mic-pulse-ring-2" />
              <div className="flex-row" style={{ width: 80, height: 80, borderRadius: "50%", background: "rgba(229, 0, 116, 0.08)", justifyContent: "center", animation: "widget-pulse 1.5s ease-in-out infinite" }}>
                <MicRecord24Regular className="text-accent" style={{ fontSize: 28 }} />
              </div>
            </div>
            <p className="text-secondary">Microfoon initialiseren...</p>
          </div>
        )}

        {(phase === "recording" || phase === "paused") && (
          <ActiveState
            elapsed={elapsed}
            audioLevels={audioLevels}
            isPaused={phase === "paused"}
            onStop={handleStopRecording}
            onPause={handlePause}
            onResume={handleResume}
          />
        )}

        {phase === "uploading" && (
          <div className="text-center">
            <div className="flex-row" style={{ position: "relative", justifyContent: "center", margin: "0 auto 16px" }}>
              <div className="mic-pulse-ring mic-pulse-ring-1" />
              <div className="mic-pulse-ring mic-pulse-ring-2" />
              <div className="flex-row" style={{ width: 80, height: 80, borderRadius: "50%", background: "rgba(229, 0, 116, 0.08)", justifyContent: "center", animation: "widget-pulse 1.5s ease-in-out infinite" }}>
                <ArrowUpload24Regular className="text-accent" style={{ fontSize: 28 }} />
              </div>
            </div>
            <p className="text-secondary">Uploaden...</p>
          </div>
        )}
      </div>

      {/* Background processing tasks — visible while user can start new recordings */}
      {backgroundTasks.length > 0 && (
        <div style={{ padding: "0 16px 16px", position: "relative", zIndex: 1 }}>
          {backgroundTasks.map((bgTask) => (
            <BackgroundTaskCard key={bgTask.task_id} task={bgTask} />
          ))}
        </div>
      )}

      {error && (
        <div className="error-banner" style={{ margin: 16 }}>
          {error}
        </div>
      )}
    </div>
  );
}

function MeetingDetectionBanner({ onRecord }: { onRecord: () => void }) {
  const [meetingApp, setMeetingApp] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function check() {
      try {
        const { detectMeetingApps } = await import("../services/tauriCommands");
        const apps = await detectMeetingApps();
        const running = apps.find((a) => a.is_running);
        if (!cancelled && running) {
          setMeetingApp(running.name);
        }
      } catch {
        // Meeting detection not available
      }
    }
    check();
    const interval = setInterval(check, 15000);
    return () => { cancelled = true; clearInterval(interval); };
  }, []);

  if (!meetingApp) return null;

  return (
    <div
      className="card card-static flex-row gap-10"
      style={{
        width: "100%",
        padding: "10px 14px",
        alignItems: "center",
        borderLeft: "3px solid var(--fill-accent)",
      }}
    >
      <VideoChat24Regular style={{ fontSize: 18, color: "var(--fill-accent)", flexShrink: 0 }} />
      <div className="flex-1" style={{ minWidth: 0 }}>
        <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>
          {meetingApp} is actief
        </p>
        <p className="text-caption text-secondary">
          Wil je de vergadering opnemen?
        </p>
      </div>
      <button
        className="btn btn-accent flex-shrink-0"
        onClick={onRecord}
        style={{ padding: "4px 12px", fontSize: 12 }}
      >
        <MicRecord24Regular style={{ fontSize: 13 }} />
        Opnemen
      </button>
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
    <div className="flex-col gap-20" style={{ width: "100%", gap: 28, alignItems: "center" }}>
      {/* Meeting detection banner */}
      <MeetingDetectionBanner onRecord={() => { onSetMode("combined"); onStart(); }} />

      {/* Section header */}
      <div className="text-center">
        <p className="section-label text-accent" style={{ marginBottom: 4 }}>
          NIEUWE OPNAME
        </p>
        <p className="text-caption text-tertiary">
          Kies bron en profiel, klik daarna om op te nemen
        </p>
      </div>

      {/* Mode selector — pill capsules matching macOS */}
      <div style={{ width: "100%" }}>
        <p className="section-label">
          Opnamemodus
        </p>
        <div className="flex-row gap-8">
          {(["combined", "microphone"] as const).map((m) => {
            const isActive = mode === m;
            return (
              <button
                key={m}
                onClick={() => onSetMode(m)}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "8px 16px",
                  borderRadius: "var(--radius-xs)",
                  border: isActive ? "1px solid var(--fill-accent-default)" : "1px solid rgba(229, 0, 116, 0.20)",
                  background: isActive ? "var(--fill-accent-default)" : "rgba(229, 0, 116, 0.06)",
                  color: isActive ? "#fff" : "var(--text-primary)",
                  fontSize: 13,
                  fontWeight: isActive ? 600 : 500,
                  cursor: "default",
                  transition: "all 180ms ease",
                  fontFamily: "inherit",
                  boxShadow: isActive ? "0 2px 8px rgba(229, 0, 116, 0.35)" : "none",
                }}
              >
                {m === "combined"
                  ? <VideoChat24Regular style={{ fontSize: 16 }} />
                  : <MicRecord24Regular style={{ fontSize: 16 }} />
                }
                <span>{m === "combined" ? "Videocall" : "Fysieke meeting"}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Profile selector as cards with emoji icons */}
      <div style={{ width: "100%" }}>
        <p className="section-label">
          Profiel
        </p>
        <div className="flex-col gap-8">
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

      {/* Mic button with concentric rings — matches macOS */}
      <div className="flex-col gap-12" style={{ alignItems: "center", paddingTop: 8 }}>
        <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center", width: 180, height: 180 }}>
          <div className="mic-pulse-ring mic-pulse-ring-1" />
          <div className="mic-pulse-ring mic-pulse-ring-2" />
          <div className="mic-pulse-ring mic-pulse-ring-3" />
          <button
            onClick={onStart}
            className="mic-button-large"
            title="Opname starten"
          >
            <MicRecord24Regular style={{ fontSize: 28, color: "#fff" }} />
          </button>
        </div>
        <p className="text-caption text-tertiary">
          Klik om op te nemen
        </p>
      </div>

      {/* Saved recordings */}
      <SavedRecordings onReprocess={() => {
        onStart();
      }} />
    </div>
  );
}

function ActiveState({
  elapsed, audioLevels, isPaused, onStop, onPause, onResume,
}: {
  elapsed: number;
  audioLevels: number[];
  isPaused: boolean;
  onStop: () => void;
  onPause: () => void;
  onResume: () => void;
}) {
  const minutes = Math.floor(elapsed / 60).toString().padStart(2, "0");
  const seconds = (elapsed % 60).toString().padStart(2, "0");

  return (
    <div className="flex-col gap-20" style={{ width: "100%", alignItems: "center" }}>
      {/* Timer — matches macOS 56pt thin monospaced */}
      <div className="text-center">
        <div
          style={{
            fontSize: 56,
            fontWeight: 100,
            fontVariantNumeric: "tabular-nums",
            fontFamily: "'Segoe UI Variable', 'Segoe UI', system-ui, monospace",
            color: "var(--text-primary)",
            letterSpacing: "0.04em",
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
      <div className="card card-static" style={{ padding: "16px 20px", width: "100%" }}>
        <WaveformVisualizer levels={audioLevels} isActive={!isPaused} height={120} />
      </div>

      {/* Mic button — active recording */}
      <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center", width: 120, height: 120 }}>
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
          <MicRecord24Regular style={{ fontSize: 28, color: "#fff" }} />
        </button>
      </div>
      <p className="text-caption text-tertiary" style={{ marginTop: -8 }}>
        {isPaused ? "Klik om te hervatten" : "Klik om te pauzeren"}
      </p>

      {/* Control buttons: PAUZE / NOTITIE / STOP */}
      <div className="recording-controls">
        <button
          onClick={isPaused ? onResume : onPause}
          className="recording-control-btn"
          title={isPaused ? "Hervatten" : "Pauzeren"}
        >
          {isPaused
            ? <Play24Regular style={{ fontSize: 24 }} />
            : <Pause24Regular style={{ fontSize: 24 }} />
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

function BackgroundTaskCard({ task }: { task: TranscriptTask }) {
  const navigate = useNavigate();
  const { removeBackgroundTask } = useRecordingStore();

  const status = task.status ?? "uploading";
  const progress = task.progress ?? 0;
  const isFailed = status === "failed";

  const statusLabels: Record<string, string> = {
    uploading: "Uploaden...",
    converting: "Converteren...",
    transcribing: "Transcriberen...",
    generating: "Notulen genereren...",
    completed: "Voltooid",
    failed: "Mislukt",
  };
  const label = statusLabels[status] ?? "Verwerken...";

  return (
    <div
      className="card card-static"
      style={{
        padding: "10px 14px",
        display: "flex",
        alignItems: "center",
        gap: 12,
        marginBottom: 8,
      }}
    >
      {/* Status indicator */}
      {isFailed ? (
        <Dismiss24Regular style={{ fontSize: 16, color: "var(--status-error)", flexShrink: 0 }} />
      ) : status === "completed" ? (
        <Checkmark24Regular style={{ fontSize: 16, color: "var(--status-success)", flexShrink: 0 }} />
      ) : (
        <div className="live-dot" style={{ flexShrink: 0 }} />
      )}

      {/* Label + progress */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 4 }}>
          <span className="text-body" style={{ fontWeight: 500 }}>{label}</span>
          <span className="text-caption text-tertiary">{progress}%</span>
        </div>
        <div style={{
          height: 3,
          borderRadius: 2,
          background: "var(--border-secondary)",
          overflow: "hidden",
        }}>
          <div style={{
            height: "100%",
            width: `${progress}%`,
            background: isFailed ? "var(--status-error)" : "var(--interactive-bg)",
            borderRadius: 2,
            transition: "width 300ms ease",
          }} />
        </div>
      </div>

      {/* Action button */}
      {status === "completed" ? (
        <button
          className="btn btn-secondary"
          style={{ padding: "4px 10px", fontSize: 12 }}
          onClick={() => {
            removeBackgroundTask(task.task_id);
            navigate("/transcripts");
          }}
        >
          Bekijk
        </button>
      ) : isFailed ? (
        <button
          className="btn btn-ghost"
          style={{ padding: "4px 8px", fontSize: 12 }}
          onClick={() => removeBackgroundTask(task.task_id)}
          title="Verwijderen"
        >
          <Dismiss24Regular style={{ fontSize: 14 }} />
        </button>
      ) : null}
    </div>
  );
}

async function getRecordingsDir(): Promise<string> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<string>("get_recordings_dir");
}
