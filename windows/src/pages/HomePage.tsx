import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  MicRecord24Regular,
  VideoChat24Regular,
  CalendarLtr24Regular,
  Clock24Regular,
  MoreHorizontal24Regular,
  Delete24Regular,
  Settings24Regular,
  Search24Regular,
  Person24Regular,
} from "@fluentui/react-icons";
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
  const { setMode, setAutoStart } = useRecordingStore();
  const { transcripts, setTranscripts, deleteTranscript, setSelectedId, isLoading, setIsLoading } = useTranscriptsStore();
  const calendar = useCalendarStore();
  const user = useAuthStore((s) => s.user);
  const [upcomingEvents, setUpcomingEvents] = useState<CalendarEvent[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
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
    setMode(mode);
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

  return (
    <div className="page-scroll thoughtvault-home" data-theme="dark">
    <div className="thoughtvault-home-content">
      <div className="thoughtvault-home-toolbar">
        <form className="thoughtvault-search" onSubmit={(e) => { e.preventDefault(); useTranscriptsStore.getState().setSearchQuery(search.trim()); navigate("/transcripts"); }}>
          <Search24Regular />
          <input aria-label="Zoek in je notulen" placeholder="Zoek in je notulen…" value={search} onChange={e => setSearch(e.target.value)} />
        </form>
        <button className="thoughtvault-account" aria-label="Instellingen" onClick={() => navigate("/settings")}><Person24Regular /></button>
      </div>
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
          <h2>Begin een nieuwe opname</h2>
          <p>Spreek je gedachten, vergadering of idee. ThoughtVault maakt er automatisch notities, samenvattingen en taken van.</p>
          <div className="thoughtvault-record-controls">
            <button className="btn btn-secondary icon-btn" aria-label="Opname-instellingen" onClick={() => navigate("/settings")}><Settings24Regular /></button>
            <button className="thoughtvault-record-orb" aria-label="Nieuwe opname voorbereiden" onClick={() => handleQuickStart("microphone")}><MicRecord24Regular /></button>
            <div className="thoughtvault-idle-wave" aria-hidden="true">{Array.from({length: 57}, (_, i) => <i key={i} style={{ height: Math.max(4, Math.pow(Math.sin(Math.PI * i / 56), 1.4) * (0.25 + 0.75 * Math.abs(Math.sin(i * 1.73) * Math.cos(i * 0.61 + 0.4))) * 65) }} />)}</div>
          </div>
          <p className="thoughtvault-ready">Klaar om op te nemen</p>
        </div>
        <aside className="thoughtvault-record-tip"><MicRecord24Regular /><h3>Alleen audio opnemen</h3><p>Kies je opnamebron en profiel. Je start de opname op het volgende scherm.</p><hr /><strong>Tip</strong><p>Spreek natuurlijk. Je kunt op elk moment pauzeren.</p></aside>
      </section>
      <section className="thoughtvault-quick-capture" aria-label="Snel vastleggen">
        <h2>Snel vastleggen</h2>
        <button className="btn btn-secondary" onClick={() => handleQuickStart("microphone")}><MicRecord24Regular />Alleen audio opnemen</button>
        <button className="btn btn-secondary" onClick={() => handleQuickStart("combined")}><VideoChat24Regular />Gesprek opnemen</button>
      </section>

      {/* Upcoming meetings */}
      {upcomingEvents.length > 0 && (
        <section>
          <p className="section-label">Aankomende vergaderingen</p>
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
      )}

      {/* Recent sessions */}
      <section style={{ flex: 1, minHeight: 0 }} className="flex-col">
        <div className="flex-row justify-between" style={{ alignItems: "center" }}>
          <p className="section-label" style={{ margin: 0 }}>Recente notities</p>
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
          <div className="flex-col gap-10">
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

      {/* Delete confirmation dialog */}
      {deleteConfirm && (
        <div className="profile-overlay" onClick={() => setDeleteConfirm(null)}>
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
        </div>
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
