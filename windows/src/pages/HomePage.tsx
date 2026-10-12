import { DesktopDialog } from "../components/ui/DesktopDialog";
import { invoke } from "@tauri-apps/api/core";
import { getAudioDevices } from "../services/tauriCommands";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  MicRecord24Regular,
  VideoChat24Regular,
  CalendarLtr24Regular,
  MoreHorizontal24Regular,
  Delete24Regular,
  Settings24Regular,
  Search24Regular,
  Person24Regular,
  DocumentText24Regular,
  ChevronRight24Regular,
} from "../components/ui/StudioIcons";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useLocalTranscriptsStore, isLocalId } from "../stores/localTranscriptsStore";
import { useCalendarStore } from "../stores/calendarStore";
import { useAuthStore } from "../stores/authStore";
import { useSettingsStore } from "../stores/settingsStore";
import { api } from "../services/api";
import { MicrosoftGraphService } from "../services/microsoftGraph";
import type { CalendarEvent, Transcript } from "../types";

function getGreeting(name?: string, email?: string): string {
  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Goedemorgen" : hour < 18 ? "Goedemiddag" : "Goedenavond";
  const firstName = name?.split(" ")[0] || email?.split("@")[0] || "";
  return firstName ? `${greeting}, ${firstName}` : greeting;
}

export function HomePage() {
  const navigate = useNavigate();
  const { setMode, setAutoStart, phase } = useRecordingStore();
  const sessionActive = phase !== "idle";
  const { transcripts, setTranscripts, deleteTranscript, setSelectedId, isLoading, setIsLoading } = useTranscriptsStore();
  const calendar = useCalendarStore();
  const user = useAuthStore((s) => s.user);
  const [upcomingEvents, setUpcomingEvents] = useState<CalendarEvent[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [micAvailable, setMicAvailable] = useState<boolean | null>(null);
  const [micError, setMicError] = useState("");
  useEffect(() => { getAudioDevices().then(devices => setMicAvailable(devices.some(d => d.is_input))).catch(() => setMicAvailable(null)); }, []);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<"all" | "recordings" | "notes">("all");
  const visibleTranscripts = transcripts.filter(t => filter === "all" || (filter === "notes" ? !!(t.notule_html || t.has_notes) : !(t.notule_html || t.has_notes)));
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
    if (!sessionActive) setMode(mode);
    navigate("/recording");
  }

  function handleRecordMeeting(_event: CalendarEvent) {
    if (!sessionActive) { setMode("combined"); setAutoStart(true); }
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

  return (
    <div className="page-scroll thoughtvault-home" data-theme="dark">
    <div className="thoughtvault-home-content">
      <div className="thoughtvault-home-toolbar">
        <form className="thoughtvault-search" onSubmit={(e) => { e.preventDefault(); useTranscriptsStore.getState().setSearchQuery(search.trim()); navigate("/transcripts"); }}>
          <Search24Regular />
          <input aria-label="Zoek in je notulen" placeholder="Zoek in je notulen…" value={search} onChange={e => setSearch(e.target.value)} />
        </form>
        <button className="thoughtvault-account" aria-label={user ? "Account" : "Instellingen"} onClick={() => navigate(user ? "/account" : "/settings")}><Person24Regular /></button>
      </div>
      <div className="thoughtvault-home-body"><div className="thoughtvault-home-main">
      <header className="thoughtvault-welcome">
        <svg className="thoughtvault-landscape" viewBox="0 0 480 190" aria-hidden="true">
          <defs>
            <linearGradient id="ridge" x2="0" y2="1"><stop stopColor="#3b2e7a" /><stop offset="1" stopColor="#141628" stopOpacity="0" /></linearGradient>
            <linearGradient id="moon" x2="0" y2="1"><stop stopColor="#eee6ff" /><stop offset="1" stopColor="#baa8f2" /></linearGradient>
            <linearGradient id="front" x2="0" y2="1"><stop stopColor="#261f54" /><stop offset="1" stopColor="#141628" stopOpacity="0" /></linearGradient>
          </defs>
          <path d="M0 160 C60 140 120 120 170 95 C215 72 265 22 292 18 C325 20 360 60 400 62 C430 64 460 55 480 58 L480 190 L0 190Z" fill="url(#ridge)" />
          <circle cx="168" cy="105" r="25" fill="url(#moon)" />
          <path d="M0 178 C55 160 110 128 150 122 C190 116 220 128 250 140 C320 168 420 160 480 165 L480 190 L0 190Z" fill="url(#front)" />
          <path d="M92 178 C130 170 190 162 186 150 C182 140 130 146 128 136 C126 128 160 126 178 124" fill="none" stroke="#bd6df9" strokeWidth="2" />
        </svg>
        <div className="thoughtvault-welcome-copy">
          <p className="section-label">{new Date().toLocaleDateString("nl-NL", { weekday: "long", day: "numeric", month: "long" })}</p>
          <h1>{getGreeting(user?.name, user?.email)}.</h1>
          <p>“Goede ideeën beginnen vaak met een gesprek.”</p>
        </div>
        <div className="thoughtvault-tagline"><strong>Spreek. Denk. Bewaar.</strong><p>ThoughtVault zet je gesprekken om in heldere notities, taken en inzichten.</p></div>
      </header>
      <section className="thoughtvault-new-recording" aria-label="Nieuwe opname">
        <div>
          <p className="section-label">Nieuwe opname</p>
          <h2>{sessionActive ? phase === "paused" ? "Je opname is gepauzeerd" : "Je opname loopt" : "Begin een nieuwe opname"}</h2>
          <p>Spreek je gedachten, vergadering of idee. ThoughtVault maakt er automatisch notities, samenvattingen en taken van.</p>
          <div className="thoughtvault-record-controls">
            <button className="btn btn-secondary icon-btn" aria-label="Opname-instellingen" onClick={() => navigate("/settings")}><Settings24Regular /></button>
            <button className="thoughtvault-record-orb" aria-label={sessionActive ? "Open huidige opname" : "Nieuwe opname voorbereiden"} onClick={() => handleQuickStart("combined")}><MicRecord24Regular /><span>{sessionActive ? "Huidige opname" : "Nieuwe opname"}</span></button>
            <div className="thoughtvault-wave-status"><div className="thoughtvault-idle-wave" aria-hidden="true">{Array.from({length: 57}, (_, i) => <i key={i} style={{ height: Math.max(4, Math.pow(Math.sin(Math.PI * i / 56), 1.4) * (0.25 + 0.75 * Math.abs(Math.sin(i * 1.73) * Math.cos(i * 0.61 + 0.4))) * 65) }} />)}</div><p className="thoughtvault-ready">{sessionActive ? "Open de opname om verder te gaan" : "Klaar om op te nemen"}</p></div>{!sessionActive && <span className="thoughtvault-idle-time" aria-hidden="true">0:00</span>}
          </div>
        </div>
        <section className="thoughtvault-record-tip"><h3>{micAvailable === true ? "Microfoon gevonden" : micAvailable === false ? "Geen microfoon gevonden" : "Opname-instellingen en toegang"}</h3><p>Windows controleert toegang wanneer je de opname start.</p><button className="btn btn-secondary" onClick={() => invoke("open_microphone_settings").catch(() => setMicError("Open Windows-instellingen → Privacy en beveiliging → Microfoon."))}>Toegang beheren</button>{micError && <p role="alert">{micError}</p>}<p>Spreek natuurlijk. Je kunt op elk moment pauzeren.</p></section>
      </section>



      {/* Recent notes */}
      <section style={{ flex: 1, minHeight: 0 }} className="flex-col thoughtvault-home-recent">
        <div className="flex-row justify-between" style={{ alignItems: "center" }}>
          <h2>Recente notities</h2>
          {isLoading && <span className="text-caption" style={{ color: "var(--fill-accent-default)" }}>Laden...</span>}
        </div>
        <div className="thoughtvault-recent-filters" role="group" aria-label="Notities filteren">
          {([["all", "Alle"], ["recordings", "Opnames"], ["notes", "Notulen"]] as const).map(([value, label]) => <button key={value} className="btn btn-ghost btn-sm" aria-pressed={filter === value} onClick={() => setFilter(value)}>{label}</button>)}
        </div>
        {loadError ? (
          <div className="error-banner-inline">
            <span>{loadError}</span>
            <button className="btn btn-sm" onClick={loadRecentTranscripts}>Opnieuw</button>
          </div>
        ) : isLoading ? (
          <div className="flex-col gap-10">
            {[1, 2, 3].map((i) => (
              <div key={i} className="card card-static" style={{ padding: 16 }}>
                <div className="flex-col gap-8">
                  <div className="skeleton skeleton-line skeleton-line-short" />
                  <div className="skeleton skeleton-line skeleton-line-long" />
                  <div className="skeleton skeleton-line skeleton-line-medium" />
                </div>
              </div>
            ))}
          </div>
        ) : visibleTranscripts.length === 0 ? (
          <div className="empty-state">
            <p className="empty-state-title">Nog geen transcripten</p>
            <p className="empty-state-body">
              Start je eerste opname. ThoughtVault maakt daarna automatisch een
              transcript en helpt je om er een duidelijke notule van te maken.
            </p>
            <button onClick={() => handleQuickStart("microphone")} className="btn btn-accent">
              Maak je eerste opname
            </button>
          </div>
        ) : (
          <div className="thoughtvault-notes-list">
            {visibleTranscripts.map((transcript) => (
              <SessionCard
                key={transcript.id}
                transcript={transcript}
                onClick={() => { setSelectedId(transcript.id); navigate("/transcripts"); }}
                onDelete={setDeleteConfirm}
              />
            ))}
          </div>
        )}
      </section>


      </div>
      <aside className="thoughtvault-home-side">
      {/* Upcoming meetings */}
        <section className="thoughtvault-agenda" aria-label="Vandaag">
          <h2>Vandaag</h2>
          {upcomingEvents.length === 0 && <div className="thoughtvault-agenda-empty"><p>{calendar.isConnected ? "Geen aankomende vergaderingen." : "Koppel je agenda om je meetings hier te zien."}</p>{!calendar.isConnected && <button className="btn btn-secondary" onClick={() => navigate("/settings")}>Agenda koppelen</button>}</div>}
          <div className="flex-col gap-8">
            {upcomingEvents.map((event) => (
              <div key={event.id} className="card session-card flex-row gap-12">
                <CalendarLtr24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)", flexShrink: 0 }} />
                <div className="flex-1" style={{ minWidth: 0 }}>
                  <p className="truncate" style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>{event.title}</p>
                  <p className="text-caption" style={{ marginTop: 1 }}>
                    {formatEventTime(event.start, event.end)}
                  </p>
                </div>
                {event.join_url && (
                  <button
                    onClick={() => handleRecordMeeting(event)}
                    className="btn btn-accent flex-shrink-0"
                    style={{ padding: "4px 10px", fontSize: 12 }}
                  >
                    <MicRecord24Regular style={{ fontSize: 13 }} />
                    Direct opnemen
                  </button>
                )}
              </div>
            ))}
          </div>
        </section>

      <section className="thoughtvault-quick-capture" aria-label="Snel vastleggen">
        <h2>Snel vastleggen</h2>
        <button className="btn btn-secondary" onClick={() => handleQuickStart("microphone")}><MicRecord24Regular />Alleen audio opnemen</button>
        <button className="btn btn-secondary" onClick={() => handleQuickStart("combined")}><VideoChat24Regular />Gesprek opnemen</button>
        <button className="btn btn-secondary" onClick={() => navigate("/recording")}><DocumentText24Regular />Audiobestand importeren</button>
      </section>

      <section className="thoughtvault-brand-note"><strong>Laat gedachten groeien tot kennis.</strong><p>Eén gesprek kan meerdere inzichten, taken en plannen opleveren.</p></section>
      </aside>
      </div>
    </div>

      {/* Delete confirmation dialog */}
      {deleteConfirm && (
        <DesktopDialog label="Sessie verwijderen" onClose={() => setDeleteConfirm(null)}>
          <div className="card profile-modal-confirm" onClick={(e) => e.stopPropagation()}>
            <p className="text-body-strong" style={{ marginBottom: 8 }}>Sessie verwijderen?</p>
            <p className="text-caption" style={{ marginBottom: 4, color: "var(--text-secondary)" }}>
              "{deleteConfirm.title || "Naamloze opname"}" wordt definitief verwijderd.
            </p>
            <p className="text-caption" style={{ marginBottom: 16, color: "var(--text-tertiary)" }}>
              Dit kan niet ongedaan worden gemaakt.
            </p>
            <div className="profile-modal-actions">
              <button onClick={() => setDeleteConfirm(null)} className="btn btn-secondary btn-sm">
                Annuleren
              </button>
              <button
                onClick={() => { handleDeleteTranscript(deleteConfirm); setDeleteConfirm(null); }}
                className="btn btn-sm"
                style={{ color: "var(--text-error)", borderColor: "rgba(188,0,22,0.3)" }}
              >
                Verwijderen
              </button>
            </div>
          </div>
        </DesktopDialog>
      )}
    </div>
  );
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
  const hasNotes = !!(transcript.notule_html || transcript.has_notes);

  return (
    <div className="thoughtvault-note-row">
      <button className="thoughtvault-note-open" onClick={onClick}>
        <span className={`thoughtvault-note-icon${hasNotes ? "" : " thoughtvault-note-audio"}`}><DocumentText24Regular /></span>
        <span className="thoughtvault-note-copy">
          <span className="thoughtvault-note-title">{transcript.title || "Naamloze opname"}</span>
          <span className="thoughtvault-note-summary"><time dateTime={transcript.created_at}>{formatDate(transcript.created_at)}</time>{previewText && <span>{previewText}</span>}</span>
        </span>
        <ChevronRight24Regular className="thoughtvault-note-chevron" />
      </button>
      <div className="thoughtvault-note-menu">
        <button onClick={() => setMenuOpen(!menuOpen)} className="icon-btn icon-btn-sm" aria-label={`Acties voor ${transcript.title || "Naamloze opname"}`} aria-expanded={menuOpen}><MoreHorizontal24Regular /></button>
        {menuOpen && <div className="context-menu" style={{ position: "absolute", right: 0, top: "100%" }}><button onClick={() => { setMenuOpen(false); onDelete(transcript); }} className="context-menu-item context-menu-item-danger"><Delete24Regular />Verwijderen</button></div>}
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
