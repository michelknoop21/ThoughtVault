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
} from "@fluentui/react-icons";
import { listen } from "@tauri-apps/api/event";
import { useRecordingStore, registerAbortController, unregisterAbortController } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useAudioLevelsRef } from "../hooks/useAudioLevel";
import { openWidgetWindow, closeWidgetWindow } from "../hooks/useWidgetWindow";
import {
  startRecording,
  stopRecording,
  pauseRecording,
  resumeRecording,
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
  const mode = useRecordingStore((s) => s.mode);
  const phase = useRecordingStore((s) => s.phase);
  const autoStart = useRecordingStore((s) => s.autoStart);
  const setMode = useRecordingStore((s) => s.setMode);
  const setPhase = useRecordingStore((s) => s.setPhase);
  const setFilePath = useRecordingStore((s) => s.setFilePath);
  const setAutoStart = useRecordingStore((s) => s.setAutoStart);
  const startTimer = useRecordingStore((s) => s.startTimer);
  const pauseTimer = useRecordingStore((s) => s.pauseTimer);
  const resumeTimer = useRecordingStore((s) => s.resumeTimer);
  const reset = useRecordingStore((s) => s.reset);
  const addBackgroundTask = useRecordingStore((s) => s.addBackgroundTask);
  const updateBackgroundTask = useRecordingStore((s) => s.updateBackgroundTask);
  const removeBackgroundTask = useRecordingStore((s) => s.removeBackgroundTask);

  const settings = useSettingsStore();
  const { addTranscript } = useTranscriptsStore();
  const profiles = useProfilesStore((s) => s.profiles);

  const isYouTubeEnabled = useRecordingStore((s) => s.isYouTubeEnabled);
  const youtubeURL = useRecordingStore((s) => s.youtubeURL);
  const isSubmittingYouTube = useRecordingStore((s) => s.isSubmittingYouTube);
  const youtubeError = useRecordingStore((s) => s.youtubeError);
  const setYouTubeEnabled = useRecordingStore((s) => s.setYouTubeEnabled);
  const setYouTubeURL = useRecordingStore((s) => s.setYouTubeURL);
  const setSubmittingYouTube = useRecordingStore((s) => s.setSubmittingYouTube);
  const setYouTubeError = useRecordingStore((s) => s.setYouTubeError);
  const youtubeProfileId = useRecordingStore((s) => s.youtubeProfileId);
  const setYouTubeProfileId = useRecordingStore((s) => s.setYouTubeProfileId);

  const [selectedProfileId, setSelectedProfileId] = useState(settings.default_profile_id);
  const [error, setError] = useState<string | null>(null);

  const audioLevelsRef = useAudioLevelsRef();
  const filePathRef = useRef<string>("");
  const isUploadingRef = useRef(false);
  const phaseRef = useRef(phase);
  phaseRef.current = phase;

  useEffect(() => {
    if (autoStart && phase === "idle") {
      setAutoStart(false);
      handleStartRecording();
    }
  }, []);

  // Check feature flags on mount
  useEffect(() => {
    api.fetchFeatures()
      .then((features) => setYouTubeEnabled(features.youtube_transcription ?? false))
      .catch(() => setYouTubeEnabled(false));
  }, []);

  // Initialize YouTube profile ID from default when profiles load
  useEffect(() => {
    if (profiles.length > 0 && !youtubeProfileId) {
      setYouTubeProfileId(settings.default_profile_id || profiles[0].id);
    }
  }, [profiles]);

  // Listen for recording-stopped event (emitted by Rust AFTER WAV file is finalized).
  // This is the single upload trigger for ALL stop scenarios (user-initiated and widget-initiated).
  // We must wait for this event because stop_recording() returns before the recording thread
  // has finalized the WAV file — uploading earlier causes the file to be locked/incomplete
  // on Windows, resulting in a 422 "file field required" error from the server.
  useEffect(() => {
    let unlistenFn: (() => void) | undefined;
    listen<{ file_path: string; duration_seconds: number }>(
      "recording-stopped",
      (event) => {
        if (event.payload.file_path) {
          filePathRef.current = event.payload.file_path;
        }
        const currentPhase = phaseRef.current;
        if (currentPhase === "recording" || currentPhase === "paused" || currentPhase === "stopping") {
          handleUpload(filePathRef.current);
        }
      }
    ).then((fn) => { unlistenFn = fn; }).catch(console.error);
    return () => { unlistenFn?.(); };
  }, []);

  // Listen for recording-error event from Rust backend
  useEffect(() => {
    let unlistenFn: (() => void) | undefined;
    listen<string>("recording-error", (event) => {
      console.error("[Recording] Event: recording-error:", event.payload);
      setError(`Opname fout: ${event.payload}`);
      setPhase("idle");
      closeWidgetWindow().catch((e) => console.error("[Recording] Widget close on error failed:", e));
    }).then((fn) => { unlistenFn = fn; }).catch(console.error);
    return () => { unlistenFn?.(); };
  }, []);

  async function handleSubmitYouTube() {
    const url = youtubeURL.trim();
    if (!url) return;

    const ytPattern = /^https?:\/\/(www\.)?(youtube\.com\/(watch\?v=|shorts\/|live\/)|youtu\.be\/)/;
    if (!ytPattern.test(url)) {
      setYouTubeError("Ongeldige YouTube URL");
      return;
    }

    setSubmittingYouTube(true);
    setYouTubeError(null);

    try {
      const task = await api.transcribeYouTube(url, youtubeProfileId || selectedProfileId);

      // Add as background task and track via SSE
      addBackgroundTask(task);
      setYouTubeURL("");

      const sseClient = createSSEClient(api.getStreamUrl(task.task_id));
      sseClient.connect(
        (update) => updateBackgroundTask(task.task_id, update),
        (err) => {
          console.error("[SSE] YouTube task error:", err);
          updateBackgroundTask(task.task_id, { status: "failed", error_message: "Verbinding verloren" });
        },
        async () => {
          const transcripts = await api.getTranscripts();
          if (transcripts[0]) addTranscript(transcripts[0]);
          removeBackgroundTask(task.task_id);
        }
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : "YouTube transcriptie mislukt";
      setYouTubeError(msg);
    } finally {
      setSubmittingYouTube(false);
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
      openWidgetWindow().catch((e) => console.error("[Recording] Widget open failed:", e));
      // Minimize main window if recording was auto-started from calendar alert
      if (useRecordingStore.getState().minimizeOnAutoStart) {
        useRecordingStore.getState().setMinimizeOnAutoStart(false);
        import("@tauri-apps/api/window").then(({ getCurrentWindow }) => {
          getCurrentWindow().minimize();
        }).catch((e) => console.error("[Recording] Minimize failed:", e));
      }
    } catch (err) {
      console.error("[Recording] Start failed:", err);
      setError(err instanceof Error ? err.message : "Opname starten mislukt");
      setPhase("idle");
    }
  }

  async function handleStopRecording() {
    setPhase("stopping");

    try {
      const result = await stopRecording();
      const filePath = result.file_path || filePathRef.current;
      filePathRef.current = filePath;
      closeWidgetWindow().catch((e) => console.error("[Recording] Widget close failed:", e));
      // Upload is triggered by the recording-stopped event listener, which fires
      // after the WAV file is fully finalized by the recording thread.
    } catch (err) {
      console.error("[Recording] Stop failed:", err);
      setError(err instanceof Error ? err.message : "Stoppen mislukt");
      setPhase("idle");
    }
  }

  async function handleUpload(filePath: string) {
    if (isUploadingRef.current) return;
    isUploadingRef.current = true;

    try {
      // Immediately add a background task and reset to idle so the user can start a new recording
      const tempId = `pending-${Date.now()}`;
      const bgTask: TranscriptTask = {
        task_id: tempId,
        status: "uploading",
        progress: 0,
        mode,
        created_at: new Date().toISOString(),
      };
      addBackgroundTask(bgTask);
      reset();

      // Upload and SSE tracking happen in the background
      const abortController = new AbortController();
      registerAbortController(tempId, abortController);
      try {
        const { task_id } = await api.uploadRecordingWithProgress(
          filePath, selectedProfileId, mode,
          (fraction) => updateBackgroundTask(tempId, { progress: Math.round(fraction * 100) }),
          abortController.signal
        );

        // Replace temp task with real task_id — move abort controller to new key
        unregisterAbortController(tempId);
        updateBackgroundTask(tempId, { task_id, status: "uploading", progress: 10 });

        // SSE updates go to background task store (use real task_id from here)
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
            const transcripts = await api.getTranscripts();
            if (transcripts[0]) addTranscript(transcripts[0]);
            removeBackgroundTask(task_id);
          }
        );
      } catch (err) {
        unregisterAbortController(tempId);
        // User cancelled — just remove the task, don't enqueue for retry
        if (err instanceof DOMException && err.name === "AbortError") {
          removeBackgroundTask(tempId);
          return;
        }
        const msg = err instanceof Error ? err.message : "Upload mislukt";
        console.error("[Recording] Upload failed:", msg);
        // Only enqueue for retry on network/server errors, not client errors (4xx)
        const isClientError = msg.includes("HTTP 4");
        if (!isClientError) {
          await enqueue({ file_path: filePath, profile_id: selectedProfileId, mode }).catch(() => {});
        }
        updateBackgroundTask(tempId, {
          status: "failed",
          error_message: msg,
        });
      }
    } finally {
      isUploadingRef.current = false;
    }
  }

  async function handlePause() {
    try {
      await pauseRecording();
      setPhase("paused");
      pauseTimer();
    } catch (error) {
      console.error("[Recording] Pause failed:", error);
      setPhase("idle");
    }
  }

  async function handleResume() {
    try {
      await resumeRecording();
      setPhase("recording");
      resumeTimer();
    } catch (error) {
      console.error("[Recording] Resume failed:", error);
      setPhase("idle");
    }
  }

  const canGoBack = phase === "idle";

  return (
    <div className="page-scroll bg-blobs">
      <div className="bg-blobs-clip">
        <div className="bg-blob bg-blob-magenta" style={{ top: "-150px", right: "-100px", left: "auto" }} />
        <div className="bg-blob bg-blob-neon" />
      </div>
      {/* Header */}
      <div className="page-header flex-row gap-12">
        <button
          onClick={() => canGoBack && navigate("/")}
          disabled={!canGoBack}
          className="btn btn-ghost icon-btn"
          aria-label="Terug naar startpagina"
          title="Terug"
        >
          <ArrowLeft24Regular />
        </button>
        <div className="flex-row gap-8">
          {mode === "combined"
            ? <VideoChat24Regular className="text-accent" />
            : <MicRecord24Regular className="text-accent" />
          }
          <h1 className="page-title-sm" style={{ fontSize: 16 }}>
            {mode === "combined" ? "Videocall opnemen" : "Vergadering opnemen"}
          </h1>
        </div>
      </div>

      {/* Body */}
      <div className="text-center recording-body">
        {phase === "idle" && (
          <IdleState
            mode={mode}
            profileId={selectedProfileId}
            profiles={profiles}
            onSetMode={setMode}
            onSetProfile={setSelectedProfileId}
            onStart={handleStartRecording}
            isYouTubeEnabled={isYouTubeEnabled}
            youtubeURL={youtubeURL}
            isSubmittingYouTube={isSubmittingYouTube}
            youtubeError={youtubeError}
            onYouTubeURLChange={setYouTubeURL}
            onSubmitYouTube={handleSubmitYouTube}
            youtubeProfileId={youtubeProfileId}
            onYouTubeProfileChange={setYouTubeProfileId}
          />
        )}

        {phase === "preparing" && (
          <div className="text-center">
            <div className="mic-button-container mic-button-container-active" style={{ marginInline: "auto", marginBottom: 16 }}>
              <div className="mic-pulse-ring mic-pulse-ring-1" />
              <div className="mic-pulse-ring mic-pulse-ring-2" />
              <div className="mic-button-large mic-preparing" style={{ background: "rgba(229, 0, 116, 0.08)", boxShadow: "none" }}>
                <MicRecord24Regular className="text-accent" style={{ fontSize: 28 }} />
              </div>
            </div>
            <p className="text-secondary">Microfoon initialiseren...</p>
          </div>
        )}

        {(phase === "recording" || phase === "paused") && (
          <ActiveState
            audioLevelsRef={audioLevelsRef}
            isPaused={phase === "paused"}
            onStop={handleStopRecording}
            onPause={handlePause}
            onResume={handleResume}
          />
        )}

        {phase === "stopping" && (
          <div className="text-center">
            <div className="mic-button-container mic-button-container-active" style={{ marginInline: "auto", marginBottom: 16 }}>
              <div className="mic-pulse-ring mic-pulse-ring-1" />
              <div className="mic-pulse-ring mic-pulse-ring-2" />
              <div className="mic-button-large mic-preparing" style={{ background: "rgba(229, 0, 116, 0.08)", boxShadow: "none" }}>
                <ArrowUpload24Regular className="text-accent" style={{ fontSize: 28 }} />
              </div>
            </div>
            <p className="text-secondary">Opname afronden...</p>
          </div>
        )}
      </div>

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
        style={{ padding: "6px 12px", fontSize: 12, minHeight: 32 }}
      >
        <MicRecord24Regular style={{ fontSize: 13 }} />
        Opnemen
      </button>
    </div>
  );
}

function IdleState({
  mode, profileId, profiles, onSetMode, onSetProfile, onStart,
  isYouTubeEnabled, youtubeURL, isSubmittingYouTube, youtubeError,
  onYouTubeURLChange, onSubmitYouTube, youtubeProfileId, onYouTubeProfileChange,
}: {
  mode: string;
  profileId: string;
  profiles: import("../types").Profile[];
  onSetMode: (m: "microphone" | "combined") => void;
  onSetProfile: (id: string) => void;
  onStart: () => void;
  isYouTubeEnabled: boolean;
  youtubeURL: string;
  isSubmittingYouTube: boolean;
  youtubeError: string | null;
  onYouTubeURLChange: (url: string) => void;
  onSubmitYouTube: () => void;
  youtubeProfileId: string;
  onYouTubeProfileChange: (id: string) => void;
}) {
  return (
    <div className="idle-state">
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
                className={`mode-selector-btn ${isActive ? "active" : ""}`}
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
      <div className="flex-col gap-12" style={{ alignItems: "center" }}>
        <div className="mic-button-container mic-button-container-idle">
          <div className="mic-pulse-ring mic-pulse-ring-1" />
          <div className="mic-pulse-ring mic-pulse-ring-2" />
          <div className="mic-pulse-ring mic-pulse-ring-3" />
          <button
            onClick={onStart}
            className="mic-button-large"
            aria-label="Start opname"
            title="Opname starten"
          >
            <MicRecord24Regular style={{ fontSize: 28, color: "#fff" }} />
          </button>
        </div>
        <p className="text-caption text-tertiary">
          Klik om op te nemen
        </p>
      </div>

      {/* YouTube transcription card */}
      {isYouTubeEnabled && (
        <div style={{ width: "100%" }}>
          <p className="section-label" style={{ color: "#E61212" }}>
            YOUTUBE VIDEO
          </p>
          <p className="text-caption text-tertiary" style={{ marginTop: -4, marginBottom: 8 }}>
            Plak een YouTube URL om te transcriberen
          </p>
          <div className="card card-static" style={{ padding: 16, borderColor: "rgba(230, 18, 18, 0.12)" }}>
            <div className="flex-col gap-12">
              <input
                type="url"
                value={youtubeURL}
                onChange={(e) => onYouTubeURLChange(e.target.value)}
                placeholder="Plak een YouTube URL..."
                className="input"
                style={{ width: "100%" }}
                disabled={isSubmittingYouTube}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !isSubmittingYouTube) onSubmitYouTube();
                }}
              />

              {/* YouTube profile selector */}
              {profiles.length > 0 && (
                <div>
                  <p className="section-label" style={{ marginBottom: 6, fontSize: 11 }}>Profiel</p>
                  <div className="flex-col gap-8">
                    {profiles.map((profile) => (
                      <button
                        key={profile.id}
                        onClick={() => onYouTubeProfileChange(profile.id)}
                        className={`profile-chip ${youtubeProfileId === profile.id ? "active" : ""}`}
                      >
                        <span className="profile-chip-icon">{getProfileIcon(profile.name)}</span>
                        <span className="profile-chip-name">{profile.name}</span>
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {youtubeError && (
                <p style={{ fontSize: 12, color: "var(--fill-danger)", margin: 0 }}>
                  {youtubeError}
                </p>
              )}
              <button
                className="btn btn-youtube"
                onClick={onSubmitYouTube}
                disabled={isSubmittingYouTube || !youtubeURL.trim()}
                style={{ alignSelf: "flex-start" }}
              >
                {isSubmittingYouTube ? "Bezig..." : "Transcriberen"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Saved recordings — reprocess uploads the existing file */}
      <SavedRecordings />
    </div>
  );
}

function ActiveState({
  audioLevelsRef, isPaused, onStop, onPause, onResume,
}: {
  audioLevelsRef: React.RefObject<number[]>;
  isPaused: boolean;
  onStop: () => void;
  onPause: () => void;
  onResume: () => void;
}) {
  const recordingStartedAt = useRecordingStore((s) => s.recordingStartedAt);
  const pausedAt = useRecordingStore((s) => s.pausedAt);
  const pausedDuration = useRecordingStore((s) => s.pausedDuration);
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    function calcElapsed() {
      if (!recordingStartedAt) return 0;
      const now = Date.now();
      const totalPaused = pausedDuration + (pausedAt ? now - pausedAt : 0);
      return Math.floor((now - recordingStartedAt - totalPaused) / 1000);
    }
    setElapsed(calcElapsed());
    if (!isPaused) {
      const id = setInterval(() => setElapsed(calcElapsed()), 1000);
      return () => clearInterval(id);
    }
  }, [isPaused, recordingStartedAt, pausedAt, pausedDuration]);

  const minutes = Math.floor(elapsed / 60).toString().padStart(2, "0");
  const seconds = (elapsed % 60).toString().padStart(2, "0");

  return (
    <div className="active-state">
      {/* Timer — matches macOS 56pt thin monospaced */}
      <div className="text-center">
        <div className="recording-timer">
          {minutes}:{seconds}
        </div>
        {/* LIVE badge */}
        <div className="live-badge">
          <span className={`live-dot ${isPaused ? "paused" : ""}`} />
          {isPaused ? "GEPAUZEERD" : "LIVE"}
        </div>
      </div>

      {/* Waveform */}
      <div className="card card-static waveform-card">
        <WaveformVisualizer levelsRef={audioLevelsRef} isActive={!isPaused} />
      </div>

      {/* Mic button — active recording */}
      <div className="mic-button-container mic-button-container-active">
        {!isPaused && (
          <>
            <div className="mic-pulse-ring mic-pulse-ring-1" />
            <div className="mic-pulse-ring mic-pulse-ring-2" />
          </>
        )}
        <button
          onClick={onStop}
          className="mic-button-large"
          aria-label="Stop opname"
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

async function getRecordingsDir(): Promise<string> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<string>("get_recordings_dir");
}
