import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  MicRecord24Regular,
  VideoChat24Regular,
  CalendarLtr24Regular,
  Clock24Regular,
  MoreHorizontal24Regular,
  Delete24Regular,
  People24Regular,
  ChevronRight24Regular,
  Search24Regular,
  Settings24Regular,
  DocumentText24Regular,
} from "@fluentui/react-icons";
import { invoke } from "@tauri-apps/api/core";
import { getAudioDevices } from "../services/tauriCommands";
import homeMountains from "../assets/home-mountains.svg";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useLocalTranscriptsStore, isLocalId } from "../stores/localTranscriptsStore";
import { useCalendarStore } from "../stores/calendarStore";
import { useAuthStore } from "../stores/authStore";
import { useSettingsStore } from "../stores/settingsStore";
import { api } from "../services/api";
import { MicrosoftGraphService } from "../services/microsoftGraph";
import { useUpdateCheck } from "../hooks/useUpdateCheck";
import { UpdateBanner } from "../components/ui/UpdateBanner";
import type { CalendarEvent, Transcript } from "../types";

function getGreeting(name?: string, email?: string): string {
  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Goedemorgen" : hour < 18 ? "Goedemiddag" : "Goedenavond";
  const firstName = name?.split(" ")[0] || email?.split("@")[0] || "";
  return firstName ? `${greeting}, ${firstName}` : greeting;
}

export function HomePage() {
  const navigate = useNavigate();
  const { setMode, setAutoStart } = useRecordingStore();
  const { transcripts, setTranscripts, deleteTranscript, setSelectedId, isLoading, setIsLoading } = useTranscriptsStore();
  const calendar = useCalendarStore();
  const user = useAuthStore((s) => s.user);
  const { isUpdateAvailable, latestVersion, downloadUrl } = useUpdateCheck();
  const dismissedVersion = useSettingsStore((s) => s.dismissed_update_version);
  const updateSettings = useSettingsStore((s) => s.updateSettings);
  const [upcomingEvents, setUpcomingEvents] = useState<CalendarEvent[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<Transcript | null>(null);

  useEffect(() => {
    loadRecentTranscripts();
    if (calendar.isConnected) {
      loadCalendarEvents();
      const interval = setInterval(loadCalendarEvents, 5 * 60 * 1000);
      return () => clearInterval(interval);
    }
  }, []);

  async function loadRecentTranscripts() {
    setIsLoading(true);
    setLoadError(null);
    // Locally generated transcripts always show, even with no server/login.
    const local = useLocalTranscriptsStore.getState().items;
    try {
      if (useSettingsStore.getState().processing_mode === "local") {
        setTranscripts(local);
        return;
      }
      const data = await api.getTranscripts();
      setTranscripts([...local, ...data]);
    } catch (err) {
      setTranscripts(local);
      // In local mode there is no backend, so a failed fetch is expected.
      if (useSettingsStore.getState().processing_mode !== "local") {
        setLoadError(err instanceof Error ? err.message : "Laden mislukt");
      }
    } finally {
      setIsLoading(false);
    }
  }

  async function loadCalendarEvents() {
    const events = await MicrosoftGraphService.getUpcomingEvents();
    const now = Date.now();
    const future = events.filter((e) => new Date(e.end).getTime() > now);
    setUpcomingEvents(future.slice(0, 3));
  }

  function handleQuickStart(mode: "microphone" | "combined") {
    setMode(mode);
    setAutoStart(true);
    navigate("/recording");
  }

  function handleRecordMeeting(_event: CalendarEvent) {
    setMode("combined");
    setAutoStart(true);
    navigate("/recording");
  }

  async function handleDeleteTranscript(transcript: Transcript) {
    try {
      if (isLocalId(transcript.id)) {
        await useLocalTranscriptsStore.getState().remove(transcript.id);
      } else {
        await api.deleteTranscript(transcript.id);
      }
      deleteTranscript(transcript.id);
    } catch (err) {
      console.error("Delete failed:", err);
      setLoadError(err instanceof Error ? err.message : "Verwijderen mislukt");
    }
  }

  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("Alle");
  const [micAvailable, setMicAvailable] = useState<boolean | null>(null);
  const [micError, setMicError] = useState("");
  const activeTasks = useRecordingStore(s => s.backgroundTasks);
  useEffect(() => { getAudioDevices().then(devices => setMicAvailable(devices.some(d => d.is_input))).catch(() => setMicAvailable(null)); }, []);
  const visible = transcripts.filter(t => filter === "Alle" || (filter === "Notulen" ? Boolean(t.notule_html || t.has_notes) : !t.notule_html && !t.has_notes)).slice(0, 10);

  return <div className="page-scroll northstar-home">
    <div className="home-topbar"><form onSubmit={e => { e.preventDefault(); useTranscriptsStore.getState().setSearchQuery(query); navigate("/transcripts"); }}>
      <Search24Regular /><input aria-label="Zoek in je notulen" placeholder="Zoek in je notulen…" value={query} onChange={e => setQuery(e.target.value)} /></form>
      <button className="home-account" aria-label="Account" onClick={() => navigate(user ? "/account" : "/settings")}>{user?.name?.slice(0, 1).toUpperCase() || <People24Regular />}</button>
    </div>
    {isUpdateAvailable && latestVersion && dismissedVersion !== latestVersion && <UpdateBanner version={latestVersion} downloadUrl={downloadUrl} onDismiss={() => updateSettings({ dismissed_update_version: latestVersion })} />}
    <div className="home-columns"><div className="home-main">
      <header className="home-greeting"><p className="home-kicker">{new Date().toLocaleDateString("nl-NL", { weekday: "long", day: "numeric", month: "long" })}</p>
        <h1>{getGreeting(user?.name, user?.email)}</h1><p>Goede ideeën beginnen vaak met een gesprek.</p>
        <img src={homeMountains} alt="" aria-hidden="true" /><div className="home-tagline"><strong>Spreek. Denk. Bewaar.</strong><span>ThoughtVault zet je gesprekken om in heldere notities, taken en inzichten.</span></div>
      </header>
      <section className="home-record-card"><div><p className="home-kicker">NIEUWE OPNAME</p><h2>Begin een nieuwe opname</h2>
        <p>Spreek je gedachten, vergadering of idee. ThoughtVault maakt er automatisch notities, samenvattingen en taken van.</p>
        <div className="home-record-controls"><button className="btn btn-secondary icon-btn" aria-label="Instellingen" onClick={() => navigate("/settings")}><Settings24Regular /></button>
          <button className="home-mic-button" aria-label="Opname starten" onClick={() => handleQuickStart("combined")}><MicRecord24Regular /></button>
          <div className="home-idle-levels"><div aria-hidden="true">{Array.from({ length: 55 }, (_, i) => <i key={i} style={{ height: Math.max(4, Math.pow(Math.sin(Math.PI * i / 54), 1.4) * (.25 + .75 * Math.abs(Math.sin(i * 1.73) * Math.cos(i * .61 + .4))) * 65) }} />)}</div>
            <span><i className="home-ready-dot" />{micAvailable === false ? "Geen microfoon gevonden" : "Klaar om op te nemen"}</span></div><span className="home-zero">0:00</span>
        </div></div>
        <aside className="home-mic-panel"><strong>{micAvailable === true ? "Microfoon gevonden" : micAvailable === false ? "Geen microfoon gevonden" : "Microfoontoegang"}</strong>
          <p>Windows controleert toegang wanneer je de opname start.</p>
          <button className="btn btn-secondary" onClick={() => invoke("open_microphone_settings").catch(() => setMicError("Open Windows-instellingen → Privacy en beveiliging → Microfoon."))}>Toegang beheren <ChevronRight24Regular /></button>
          {micError && <p role="alert">{micError}</p>}<hr /><strong className="home-tip">Tip</strong><p>Spreek natuurlijk. Je kunt op elk moment pauzeren.</p>
        </aside>
      </section>
      <section className="home-recents"><header><h2>Recente notities</h2><div role="group" aria-label="Filter recente notities">{["Alle", "Opnames", "Notulen"].map(value => <button key={value} aria-pressed={filter === value} className={filter === value ? "active" : ""} onClick={() => setFilter(value)}>{value}</button>)}</div></header>
        {loadError && <div className="error-banner-inline"><span>{loadError}</span><button className="btn btn-sm" onClick={loadRecentTranscripts}>Opnieuw</button></div>}
        {isLoading && !transcripts.length ? <p>Laden…</p> : !transcripts.length ? <div className="home-empty"><h3>Je vault is nog leeg</h3><p>Alles wat je inspreekt verschijnt hier als notitie of notule.</p><button className="studio-link" onClick={() => handleQuickStart("combined")}>Maak je eerste opname</button></div>
          : <div className="home-recent-list">{visible.map(transcript => <SessionCard key={transcript.id} transcript={transcript} onClick={() => { setSelectedId(transcript.id); navigate("/transcripts"); }} onDelete={setDeleteConfirm} />)}{!visible.length && <p className="home-empty">Geen {filter.toLowerCase()} in deze lijst.</p>}</div>}
      </section>
      {activeTasks.length > 0 && <section className="northstar-card"><h3>Bezig met verwerken</h3>{activeTasks.map(task => <button className="home-task-row" key={task.task_id} onClick={() => navigate("/tasks")}><span>{task.extracted_title || task.filename || "Opname"}<small>{task.error_message || task.message || task.status}</small></span><span>{task.progress}%</span></button>)}</section>}
    </div><aside className="home-side">
      <section className="northstar-card"><h2>Vandaag</h2>{upcomingEvents.length ? upcomingEvents.map(event => <div className="home-calendar-row" key={event.id}><CalendarLtr24Regular /><div><strong>{event.title}</strong><p>{formatEventTime(event.start, event.end)}</p><button className="studio-link" onClick={() => handleRecordMeeting(event)}>Direct opnemen</button></div></div>) : <><p>{calendar.isConnected ? "Geen aankomende vergaderingen." : "Koppel je agenda om je vergaderingen hier te zien."}</p><button className="studio-link" onClick={() => navigate("/settings")}>Agenda instellen</button></>}</section>
      <section className="northstar-card"><h2>Snel vastleggen</h2><button className="home-quick-action" onClick={() => handleQuickStart("microphone")}><People24Regular />Fysieke meeting</button><button className="home-quick-action" onClick={() => handleQuickStart("combined")}><VideoChat24Regular />Videocall</button><button className="home-quick-action" onClick={() => navigate("/recording")}><DocumentText24Regular />Audiobestand importeren</button></section>
      <section className="northstar-card home-brand-note"><strong>Laat gedachten groeien tot kennis.</strong><p>Eén gesprek kan meerdere inzichten, taken en plannen opleveren.</p></section>
    </aside></div>
    {deleteConfirm && <div className="profile-overlay" onClick={() => setDeleteConfirm(null)}><div className="card profile-modal-confirm" onClick={e => e.stopPropagation()}>
      <h3>Sessie verwijderen?</h3><p>“{deleteConfirm.title}” wordt definitief verwijderd. Dit kan niet ongedaan worden gemaakt.</p>
      <div className="profile-modal-actions"><button className="btn btn-secondary" onClick={() => setDeleteConfirm(null)}>Annuleren</button><button className="btn btn-secondary text-error" onClick={() => { void handleDeleteTranscript(deleteConfirm); setDeleteConfirm(null); }}>Verwijderen</button></div>
    </div></div>}
  </div>;
}

function SessionCard({
  transcript,
  onClick,
  onDelete,
}: {
  transcript: Transcript;
  onClick: () => void;
  onDelete: (t: Transcript) => void;
}) {
  const [menuOpen, setMenuOpen] = useState(false);

  const previewText = getPreviewText(transcript);
  const isComplete = !!transcript.notule_html || !!transcript.raw_transcription || transcript.has_notes || transcript.has_transcription;

  return (
    <div className="card session-card" onClick={onClick}>
      {/* Header row */}
      <div className="session-card-header">
        <div className="flex-row gap-8">
          <span className="status-badge-accent">Sessie</span>
          <span className="text-caption">{formatDate(transcript.created_at)}</span>
        </div>
        <div style={{ position: "relative" }}>
          <button
            onClick={(e) => { e.stopPropagation(); setMenuOpen(!menuOpen); }}
            className="icon-btn icon-btn-sm"
          >
            <MoreHorizontal24Regular style={{ fontSize: 16 }} />
          </button>
          {menuOpen && (
            <div
              className="context-menu"
              style={{ position: "absolute", right: 0, top: "100%" }}
              onClick={(e) => e.stopPropagation()}
            >
              <button
                onClick={() => { setMenuOpen(false); onDelete(transcript); }}
                className="context-menu-item context-menu-item-danger"
              >
                <Delete24Regular style={{ fontSize: 14 }} />
                Verwijderen
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Title */}
      <p className="session-card-title truncate">{transcript.title || "Naamloze opname"}</p>

      {/* Preview */}
      {previewText && <p className="session-card-preview">{previewText}</p>}

      {/* Bottom row */}
      <div className="session-card-meta flex-row gap-8">
        <span className="flex-row gap-4">
          <Clock24Regular style={{ fontSize: 12 }} />
          {formatTimeAgo(transcript.created_at)}
        </span>
        {isComplete && <span className="status-badge-success">Voltooid</span>}
      </div>
    </div>
  );
}

function stripHtml(html: string): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function getPreviewText(transcript: Transcript): string {
  if (typeof transcript.notule_html === "string" && transcript.notule_html) {
    return stripHtml(transcript.notule_html).slice(0, 200);
  }
  if (typeof transcript.raw_transcription === "string" && transcript.raw_transcription) {
    return transcript.raw_transcription.slice(0, 200);
  }
  // Listing endpoint returns preview (first 200 chars of result) without full text
  if (typeof transcript.preview === "string" && transcript.preview) {
    return stripHtml(transcript.preview).slice(0, 200);
  }
  return "";
}

function formatTimeAgo(dateStr: string): string {
  const now = new Date();
  const date = new Date(dateStr);
  const diffMs = now.getTime() - date.getTime();
  const diffMin = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMin < 1) return "Zojuist";
  if (diffMin < 60) return `${diffMin} min geleden`;
  if (diffHours < 24) return `${diffHours} uur geleden`;
  if (diffDays === 1) return "Gisteren";
  if (diffDays < 7) return `${diffDays} dagen geleden`;
  if (diffDays < 30) return `${Math.floor(diffDays / 7)} weken geleden`;
  return formatDate(dateStr);
}

function formatEventTime(start: string, end: string): string {
  const s = new Date(start);
  const e = new Date(end);
  const fmt = (d: Date) =>
    d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" });

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const eventDay = new Date(s.getFullYear(), s.getMonth(), s.getDate());
  const diffDays = Math.round((eventDay.getTime() - today.getTime()) / 86400000);

  let dayLabel = "";
  if (diffDays === 0) dayLabel = "Vandaag";
  else if (diffDays === 1) dayLabel = "Morgen";
  else dayLabel = s.toLocaleDateString("nl-NL", { weekday: "long", day: "numeric", month: "short" });

  return `${dayLabel}, ${fmt(s)} – ${fmt(e)}`;
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("nl-NL", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
