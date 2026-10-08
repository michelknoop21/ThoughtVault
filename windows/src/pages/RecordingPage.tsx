import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { open, ask } from "@tauri-apps/plugin-dialog";
import {
  MicRecord24Regular,
  Stop24Regular,
  Pause24Regular,
  Play24Regular,
  Edit24Regular,
  ArrowUpload24Regular,
  VideoChat24Regular,
  People24Regular,
} from "@fluentui/react-icons";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useAudioLevelsRef, useAudioLevel } from "../hooks/useAudioLevel";
import { openWidgetWindow, closeWidgetWindow } from "../hooks/useWidgetWindow";
import {
  startRecording,
  stopRecording,
  pauseRecording,
  resumeRecording,
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
import { saveQuickNote } from "../services/quickNotes";
import { useCalendarStore } from "../stores/calendarStore";

import { DocumentText24Regular } from "@fluentui/react-icons";

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
          try {
            const transcripts = await api.getTranscripts();
            const result = transcripts.find(item => item.task_id === task.task_id || item.id === task.task_id);
            if (!result) throw new Error("Het resultaat is nog niet beschikbaar. Vernieuw Opnames.");
            addTranscript(result);
            removeBackgroundTask(task.task_id);
          } catch (err) {
            updateBackgroundTask(task.task_id, { status: "failed", error_message: err instanceof Error ? err.message : String(err) });
          }
        }
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : "YouTube transcriptie mislukt";
      setYouTubeError(msg);
    } finally {
      setSubmittingYouTube(false);
    }
  }

  async function handleStartRecording(recordingMode = mode) {
    setMode(recordingMode);
    setPhase("preparing");
    setError(null);

    try {
      const outputDir = await getRecordingsDir();
      const filePath = await startRecording(null, recordingMode, outputDir);
      filePathRef.current = filePath;
      setFilePath(filePath);
      setPhase("recording");
      audioLevelsRef.current = [];
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
      setError(err instanceof Error ? err.message : String(err));
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
    const pendingEmails = [...useRecordingStore.getState().pendingSeedAttendees];
    setPhase("stopping");

    try {
      const result = await stopRecording();
      const filePath = result.file_path || filePathRef.current;
      filePathRef.current = filePath;
      closeWidgetWindow().catch((e) => console.error("[Recording] Widget close failed:", e));

      // The global handler resolves participants before resetting the store.
      // Use our snapshot for the directory prompt without clearing its inputs.

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
      setPhase("idle");
    }
  }

  async function handlePause() {
    try {
      await pauseRecording();
      setPhase("paused");
      pauseTimer();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Pauzeren mislukt");
    }
  }

  async function handleResume() {
    try {
      await resumeRecording();
      setPhase("recording");
      resumeTimer();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Hervatten mislukt");
    }
  }

  const quickNote = useRecordingStore(s => s.quickNote);
  const setQuickNote = useRecordingStore(s => s.setQuickNote);
  const selectedParticipantIds = useRecordingStore(s => s.selectedParticipantIds);
  const recordingStartedAt = useRecordingStore(s => s.recordingStartedAt);
  const pausedAt = useRecordingStore(s => s.pausedAt);
  const pausedDuration = useRecordingStore(s => s.pausedDuration);
  const level = useAudioLevel();
  const [elapsed, setElapsed] = useState(0);
  const [panel, setPanel] = useState<"note" | "saved" | "youtube" | "people" | null>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (panel && panel !== "people") dialogRef.current?.showModal();
  }, [panel]);
  const isLive = phase === "recording" || phase === "paused";
  const isBusy = phase === "preparing" || phase === "stopping" || phase === "uploading";
  useEffect(() => {
    const tick = () => setElapsed(recordingStartedAt
      ? Math.max(0, Math.floor(((pausedAt ?? Date.now()) - recordingStartedAt - pausedDuration) / 1000)) : 0);
    tick();
    if (phase === "recording") {
      const id = setInterval(tick, 1000);
      return () => clearInterval(id);
    }
  }, [phase, recordingStartedAt, pausedAt, pausedDuration]);
  const duration = `${Math.floor(elapsed / 60).toString().padStart(2, "0")}:${(elapsed % 60).toString().padStart(2, "0")}`;
  const profileName = profiles.find(p => p.id === selectedProfileId)?.name ?? "Geen profiel";
  const status = phase === "recording" ? "OPNAME ACTIEF" : phase === "paused" ? "OPNAME GEPAUZEERD"
    : phase === "preparing" ? "OPNAME STARTEN" : phase === "stopping" ? "OPNAME STOPPEN" : "KLAAR OM OP TE NEMEN";

  async function handleKeepRecording() {
    if (!await ask("Stoppen zonder te verwerken? De opname blijft beschikbaar bij Opgeslagen opnames.", { title: "Opname stoppen", kind: "warning", okLabel: "Stoppen", cancelLabel: "Annuleren" })) return;
    // The global stopped handler deliberately ignores idle, keeping the WAV for
    // manual processing later. It must not upload a recording the user cancelled.
    setPhase("idle");
    try {
      await stopRecording();
      saveQuickNote(filePathRef.current || useRecordingStore.getState().filePath || "", quickNote);
      useRecordingStore.getState().reset();
      await closeWidgetWindow();
    } catch (err) {
      // The phase is already idle: drop the session and widget so the UI matches.
      useRecordingStore.getState().reset();
      closeWidgetWindow().catch((e) => console.error("[Recording] Widget close failed:", e));
      setError(err instanceof Error ? err.message : "Stoppen mislukt");
    }
  }

  return <div className="recording-studio">
    <section className="studio-workspace" aria-label="Opnamestudio">
      <header className="studio-topline">
        <span className={`studio-status ${phase}`} role="status"><i />{status}</span>
        <span className="studio-language">Spreektaal: Nederlands</span>
      </header>
      {error && <div className="error-banner" role="alert">{error}</div>}
      {!isLive && !isBusy && <MeetingDetectionBanner onRecord={() => {
        setMode("combined"); void handleStartRecording("combined");
      }} />}
      <div className="studio-timer" aria-label={`Opnameduur ${duration}`}>{duration}</div>
      <div className="studio-listening"><span className="studio-mini-bars" aria-hidden="true">
        {Array.from({ length: 9 }, (_, i) => <i key={i} style={{ height: 3 + (phase === "recording" ? level / 100 * (14 - i) : 0) }} />)}
      </span><span>{phase === "recording" ? "Ik luister…" : phase === "paused" ? "Opname is gepauzeerd" : isBusy ? "Even geduld…" : "Klaar"}</span></div>
      <div className="studio-wave"><WaveformVisualizer levelsRef={audioLevelsRef} isActive={phase === "recording"} height={240} /></div>
      <div className="studio-transport">
        {isLive ? <>
          <div><button className="studio-round" onClick={phase === "paused" ? handleResume : handlePause}
            aria-label={phase === "paused" ? "Hervat opname" : "Pauzeer opname"}>{phase === "paused" ? <Play24Regular /> : <Pause24Regular />}</button>
            <span>{phase === "paused" ? "Hervat" : "Pauzeer"}</span></div>
          <div><button className="studio-round studio-stop" onClick={handleStopRecording} aria-label="Stop en verwerk"><Stop24Regular /></button><span>Stop en verwerk</span></div>
          <div><button className="studio-round" onClick={() => setPanel("note")} aria-label="Notitie maken"><Edit24Regular /></button><span>Notitie</span></div>
        </> : <div><button className="studio-round studio-record" onClick={() => void handleStartRecording()} disabled={isBusy} aria-label="Start opname"><MicRecord24Regular /></button>
          <span>{isBusy ? "Even geduld…" : "Start opname"}</span></div>}
      </div>
      <div className="studio-controlbar">
        <label><VideoChat24Regular /><span><small>Bron</small><select aria-label="Bron" value={mode} disabled={isLive || isBusy} onChange={e => setMode(e.target.value as "combined" | "microphone")}>
          <option value="combined">Gecombineerd</option><option value="microphone">Microfoon</option>
        </select></span></label>
        <label><DocumentText24Regular /><span><small>Opnameprofiel</small><select aria-label="Opnameprofiel" value={selectedProfileId} onChange={e => setSelectedProfileId(e.target.value)}>
          {profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select></span></label>
        <div className="studio-transcription"><small>Transcriptie</small><span>{settings.processing_mode === "local" ? "Whisper op deze pc" : "ThoughtVault Cloud"}</span>
          <button className="studio-link" disabled={isLive || isBusy} onClick={() => navigate("/settings")}>Instellen</button></div>
      </div>
    </section>
    <aside className="studio-inspector">
      <section>
      <h2>Huidige opname</h2>
      <div className="studio-identity"><MicRecord24Regular /><div><strong>Nieuwe opname</strong><span>Titel na verwerking</span></div></div>
      <p className="studio-meta">Tags na verwerking</p>
      <button className="studio-meta studio-people" onClick={() => setPanel("people")}><People24Regular />{selectedParticipantIds.length ? `${selectedParticipantIds.length} personen` : "Geen personen"}<span>＋</span></button>
      <p className="studio-meta">Wordt na verwerking aangevuld</p>
      <section className="studio-live-panel"><h3>Live opname</h3>
        <dl><div><dt>Duur</dt><dd>{duration}</dd></div><div><dt>Geluidsniveau</dt><dd><meter min={0} max={100} value={phase === "recording" ? level : 0} aria-label="Geluidsniveau" /></dd></div>
          <div><dt>Bron</dt><dd>{mode === "combined" ? "Gecombineerd" : "Microfoon"}</dd></div><div><dt>Profiel</dt><dd>{profileName}</dd></div></dl>
      </section>
      </section>
      <section>
      <h2>Snelle acties</h2>
      <div className="studio-actions">
        {isLive ? <><button onClick={() => setPanel("note")}><Edit24Regular />Notitie maken{quickNote.trim() && <span>●</span>}</button>
          <button onClick={() => setPanel("people")}><People24Regular />Deelnemers kiezen</button>
          {phase === "paused" && <button onClick={handleKeepRecording}><DocumentText24Regular />Bewaar zonder verwerken</button>}</>
          : <><button onClick={handleImportAudio} disabled={isImporting || isBusy}><ArrowUpload24Regular />{isImporting ? "Importeren…" : "Audiobestand importeren"}</button>
            {isYouTubeEnabled && <button onClick={() => setPanel("youtube")} disabled={isBusy}><Play24Regular />YouTube-video</button>}
            <button onClick={() => setPanel("saved")}><DocumentText24Regular />Opgeslagen opnames</button></>}
      </div>
      {settings.processing_mode === "cloud" && <label className="studio-premium"><input type="checkbox" checked={usePremium} onChange={e => setUsePremium(e.target.checked)} />Premium model</label>}
      <p className="studio-hint">{mode === "combined" ? "Microfoon en systeemgeluid worden opgenomen." : "Alleen je microfoon wordt opgenomen."} Transcriptie gebeurt na afloop.</p>
      </section>
    </aside>
    {panel === "people" && <ParticipantPicker onClose={() => setPanel(null)} />}
    {panel && panel !== "people" && <dialog ref={dialogRef} className="studio-dialog" aria-label={panel === "note" ? "Snelle notitie" : panel === "saved" ? "Opgeslagen opnames" : "YouTube-video"} onCancel={() => setPanel(null)}>
      <header><h2>{panel === "note" ? "Snelle notitie" : panel === "saved" ? "Opgeslagen opnames" : "YouTube-video"}</h2><button className="btn btn-secondary" onClick={() => setPanel(null)}>Sluiten</button></header>
      {panel === "note" && <><p>Context voor je notulen; dit wordt apart van het gesproken transcript bewaard.</p>
        <textarea autoFocus rows={7} className="input" aria-label="Snelle notitie" value={quickNote} onChange={e => setQuickNote(e.target.value)} />
        <p className="text-caption">Wordt bij het stoppen met deze opname opgeslagen.</p></>}
      {panel === "saved" && <SavedRecordings initiallyExpanded />}
      {panel === "youtube" && <form onSubmit={e => { e.preventDefault(); void handleSubmitYouTube(); }}>
        <label>Video-URL<input className="input" type="url" value={youtubeURL} onChange={e => setYouTubeURL(e.target.value)} required placeholder="https://www.youtube.com/watch?v=…" /></label>
        <label>Template<select className="select" value={youtubeProfileId} onChange={e => setYouTubeProfileId(e.target.value)}>{profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
        {youtubeError && <p role="alert" className="text-error">{youtubeError}</p>}
        <button className="btn btn-accent" disabled={isSubmittingYouTube}>{isSubmittingYouTube ? "Versturen…" : "Verwerken"}</button>
      </form>}
    </dialog>}
    {seedCandidates.length > 0 && <SeedReviewSheet candidates={seedCandidates} onClose={() => setSeedCandidates([])} />}
  </div>;
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


async function getRecordingsDir(): Promise<string> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<string>("get_recordings_dir");
}
