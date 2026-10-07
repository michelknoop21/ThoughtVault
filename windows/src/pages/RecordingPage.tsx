import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { open } from "@tauri-apps/plugin-dialog";
import {
  MicRecord24Regular,
  Stop24Regular,
  Pause24Regular,
  Play24Regular,
  ArrowLeft24Regular,
  ArrowUpload24Regular,
  VideoChat24Regular,
  People24Regular,
} from "@fluentui/react-icons";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useAudioLevelsRef } from "../hooks/useAudioLevel";
import { recordingAction } from "../services/recordingActions";
import {
  importAudio,
} from "../services/tauriCommands";
import { processLocally } from "../services/localPipeline";
import { uploadAndTrack } from "../services/uploadAndTrack";
import { api } from "../services/api";
import { createSSEClient } from "../services/sse";
import { WaveformVisualizer } from "../components/recording/WaveformVisualizer";
import { SavedRecordings } from "../components/recording/SavedRecordings";
import { SeedReviewSheet } from "./SeedReviewSheet";
import { ParticipantPicker } from "./ParticipantPicker";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import { useCalendarStore } from "../stores/calendarStore";

import {
  Briefcase24Regular,
  ChatMultiple24Regular,
  Wrench24Regular,
  DocumentText24Regular,
  Book24Regular,
} from "@fluentui/react-icons";

function getProfileIcon(name: string): React.ReactNode {
  const lower = name.toLowerCase();
  const style = { fontSize: 14 };
  if (lower.includes("zakelijk")) return <Briefcase24Regular style={style} />;
  if (lower.includes("informeel")) return <ChatMultiple24Regular style={style} />;
  if (lower.includes("technisch")) return <Wrench24Regular style={style} />;
  if (lower.includes("handleiding")) return <Book24Regular style={style} />;
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
  const addBackgroundTask = useRecordingStore((s) => s.addBackgroundTask);
  const updateBackgroundTask = useRecordingStore((s) => s.updateBackgroundTask);
  const removeBackgroundTask = useRecordingStore((s) => s.removeBackgroundTask);
  const setSelectedProfileId = useRecordingStore((s) => s.setSelectedProfileId);
  const usePremium = useRecordingStore((s) => s.usePremium);
  const setUsePremium = useRecordingStore((s) => s.setUsePremium);

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

  // Profile selection is stored globally so the global recording handler can access it
  const selectedProfileId = useRecordingStore((s) => s.selectedProfileId);
  const [error, setError] = useState<string | null>(null);
  const [isImporting, setIsImporting] = useState(false);
  const [seedCandidates, setSeedCandidates] = useState<string[]>([]);

  const calendarAccountEmail = useCalendarStore((s) => s.accountEmail);
  const newSeedCandidates = usePeopleDirectoryStore((s) => s.newSeedCandidates);

  const audioLevelsRef = useAudioLevelsRef();
  const filePathRef = useRef<string>("");

  // A persisted legacy profile ID is still valid for old documents, but not
  // for a new recording. Choose the current default when options change.
  useEffect(() => {
    if (profiles.length === 0 || profiles.some((profile) => profile.id === selectedProfileId)) return;
    const fallback = profiles.find((profile) => profile.id === settings.default_profile_id) ?? profiles[0];
    setSelectedProfileId(fallback.id);
  }, [profiles, selectedProfileId, settings.default_profile_id, setSelectedProfileId]);

  useEffect(() => {
    if (autoStart && phase === "idle") {
      setAutoStart(false);
      handleStartRecording();
    }
  }, []);

  // Check feature flags on mount
  useEffect(() => {
    if (settings.processing_mode === "local") {
      setYouTubeEnabled(false);
      return;
    }
    api.fetchFeatures()
      .then((features) => setYouTubeEnabled(features.youtube_transcription ?? false))
      .catch(() => setYouTubeEnabled(false));
  }, [settings.processing_mode]);

  // Initialize YouTube profile ID from default when profiles load
  useEffect(() => {
    if (profiles.length > 0 && !youtubeProfileId) {
      setYouTubeProfileId(settings.default_profile_id || profiles[0].id);
    }
  }, [profiles]);

  // NOTE: recording-stopped and recording-error event listeners are handled globally
  // in useGlobalRecordingHandler (mounted in ProtectedRoutes) so they survive page navigation.
  // This ensures uploads trigger even when the user stops from the floating widget
  // while on a different page.

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
    setError(null);

    try {
      const filePath = await recordingAction("start") as string;
      filePathRef.current = filePath;
      setFilePath(filePath);

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

  async function handleImportAudio() {
    setError(null);
    try {
      const source = await open({
        multiple: false,
        filters: [{ name: "Audio", extensions: ["wav", "mp3", "m4a", "mp4", "aac", "flac", "ogg"] }],
      });
      if (!source || typeof source !== "string") return;
      setIsImporting(true);
      const filePath = await importAudio(source);
      if (settings.processing_mode === "local") {
        void processLocally(filePath, selectedProfileId || settings.default_profile_id, "microphone");
      } else {
        void uploadAndTrack(filePath, selectedProfileId || settings.default_profile_id, "microphone");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setIsImporting(false);
    }
  }

  async function handleStopRecording() {
    try {
      const result = await recordingAction("stop") as { file_path: string };
      const filePath = result.file_path || filePathRef.current;
      filePathRef.current = filePath;

      // Read and clear pendingSeedAttendees — show SeedReviewSheet if new people found (D-07)
      const store = useRecordingStore.getState();
      const pendingEmails = store.pendingSeedAttendees;
      store.clearPendingSeedAttendees();

      if (pendingEmails.length > 0) {
        // Dedup: filter emails already in directory and the calendar account email (self, D-10)
        const candidates = newSeedCandidates(pendingEmails, calendarAccountEmail ?? undefined);
        if (candidates.length > 0) {
          setSeedCandidates(candidates);
        }
      }

      // Upload is triggered by the recording-stopped event listener, which fires
      // after the WAV file is fully finalized by the recording thread.
    } catch (err) {
      console.error("[Recording] Stop failed:", err);
      setError(err instanceof Error ? err.message : "Stoppen mislukt");
    }
  }

  async function handlePause() {
    try {
      await recordingAction("pause");
    } catch (error) {
      setError(String(error));
    }
  }

  async function handleResume() {
    try {
      await recordingAction("resume");
    } catch (error) {
      setError(String(error));
    }
  }

  const canGoBack = phase === "idle";

  return (
    <div className="page-scroll bg-blobs thoughtvault-recording" data-theme="dark">
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
            onImport={handleImportAudio}
            isImporting={isImporting}
            usePremium={usePremium}
            onSetPremium={setUsePremium}
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
              <div className="mic-button-large mic-preparing" style={{ background: "rgba(144, 72, 240, 0.08)", boxShadow: "none" }}>
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
              <div className="mic-button-large mic-preparing" style={{ background: "rgba(144, 72, 240, 0.08)", boxShadow: "none" }}>
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

      {/* Seed review sheet — shown after recording stops when new attendees found (D-07) */}
      {seedCandidates.length > 0 && (
        <SeedReviewSheet
          candidates={seedCandidates}
          onClose={() => setSeedCandidates([])}
        />
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
  mode, profileId, profiles, onSetMode, onSetProfile, onStart, onImport, isImporting,
  usePremium, onSetPremium,
  isYouTubeEnabled, youtubeURL, isSubmittingYouTube, youtubeError,
  onYouTubeURLChange, onSubmitYouTube, youtubeProfileId, onYouTubeProfileChange,
}: {
  mode: string;
  profileId: string;
  profiles: import("../types").Profile[];
  onSetMode: (m: "microphone" | "combined") => void;
  onSetProfile: (id: string) => void;
  onStart: () => void;
  onImport: () => void;
  isImporting: boolean;
  usePremium: boolean;
  onSetPremium: (value: boolean) => void;
  isYouTubeEnabled: boolean;
  youtubeURL: string;
  isSubmittingYouTube: boolean;
  youtubeError: string | null;
  onYouTubeURLChange: (url: string) => void;
  onSubmitYouTube: () => void;
  youtubeProfileId: string;
  onYouTubeProfileChange: (id: string) => void;
}) {
  const [showParticipants, setShowParticipants] = useState(false);
  const selectedParticipantIds = useRecordingStore((s) => s.selectedParticipantIds);

  return (
    <div className="idle-state">
      <div className="thoughtvault-record-workspace">
        <span className="thoughtvault-record-status">Nieuwe opname</span>
        <div className="recording-timer">00:00</div>
        <p className="thoughtvault-listening">Klaar om je gedachten vast te leggen</p>
        <div className="thoughtvault-record-idle-line" aria-hidden="true" />
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

      </div>
      <aside className="thoughtvault-record-inspector" aria-label="Opname-instellingen">
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

      {/* Mode selector — card style matching macOS */}
      <div style={{ width: "100%" }}>
        <p className="section-label">
          Opnamemodus
        </p>
        <div className="mode-selector-grid">
          {(["microphone", "combined"] as const).map((m) => {
            const isActive = mode === m;
            const isCombined = m === "combined";
            return (
              <button
                key={m}
                onClick={() => onSetMode(m)}
                className={`mode-selector-card ${isActive ? "active" : ""}`}
              >
                <div className={`mode-selector-icon ${isCombined ? "accent" : "secondary"} ${isActive ? "active" : ""}`}>
                  {isCombined
                    ? <VideoChat24Regular style={{ fontSize: 20 }} />
                    : <MicRecord24Regular style={{ fontSize: 20 }} />
                  }
                </div>
                <div className="mode-selector-text">
                  <span className="mode-selector-title">{isCombined ? "Videocall" : "Fysieke meeting"}</span>
                  <span className="mode-selector-subtitle">{isCombined ? "Microfoon + systeemgeluid" : "Alleen microfoon"}</span>
                </div>
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

      {/* Participants picker */}
      <div style={{ width: "100%" }}>
        <p className="section-label">Deelnemers</p>
        <button
          className="profile-chip"
          style={{ width: "100%", justifyContent: "space-between" }}
          onClick={() => setShowParticipants(true)}
        >
          <span className="profile-chip-name">
            {selectedParticipantIds.length === 0
              ? "Optioneel · agenda-deelnemers gaan automatisch mee"
              : `${selectedParticipantIds.length} gekozen`}
          </span>
          <People24Regular style={{ fontSize: 18 }} />
        </button>
      </div>

      {/* Premium model toggle */}
      <div style={{ width: "100%" }}>
        <label className="premium-toggle">
          <input
            type="checkbox"
            checked={usePremium}
            onChange={(e) => onSetPremium(e.target.checked)}
          />
          <div className="premium-toggle-content">
            <span className="premium-toggle-label">Premium model</span>
            <span className="premium-toggle-desc">Betere kwaliteit, langzamer</span>
          </div>
        </label>
      </div>

      {/* YouTube transcription — collapsible */}
      {isYouTubeEnabled && (
        <details className="disclosure" style={{ width: "100%" }}>
          <summary className="section-label" style={{ color: "#E61212", cursor: "pointer", userSelect: "none" }}>
            YOUTUBE VIDEO
          </summary>
          <div style={{ marginTop: 8 }}>
            <p className="text-caption text-tertiary" style={{ marginBottom: 8 }}>
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
        </details>
      )}

      <button className="btn btn-secondary" onClick={onImport} disabled={isImporting}>
        <ArrowUpload24Regular style={{ fontSize: 16 }} />
        {isImporting ? "Audio importeren..." : "Audiobestand importeren"}
      </button>

      {/* Saved recordings — collapsible */}
      <SavedRecordings />

      </aside>
      {showParticipants && (
        <ParticipantPicker onClose={() => setShowParticipants(false)} />
      )}
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

      {/* Mic button — active recording: toggles pause/resume */}
      <div className="mic-button-container mic-button-container-active">
        {!isPaused && (
          <>
            <div className="mic-pulse-ring mic-pulse-ring-1" />
            <div className="mic-pulse-ring mic-pulse-ring-2" />
          </>
        )}
        <button
          onClick={isPaused ? onResume : onPause}
          className="mic-button-large"
          aria-label={isPaused ? "Hervat opname" : "Pauzeer opname"}
          title={isPaused ? "Hervatten" : "Pauzeren"}
        >
          {isPaused
            ? <Play24Regular style={{ fontSize: 28, color: "#fff" }} />
            : <Pause24Regular style={{ fontSize: 28, color: "#fff" }} />
          }
        </button>
      </div>

      {/* Control buttons: PAUZE / STOP */}
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
