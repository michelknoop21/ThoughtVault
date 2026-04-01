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
} from "@fluentui/react-icons";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
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
    try {
      const data = await api.getTranscripts();
      setTranscripts(data);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Laden mislukt";
      setLoadError(msg);
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
      await api.deleteTranscript(transcript.id);
      deleteTranscript(transcript.id);
    } catch (err) {
      console.error("Delete failed:", err);
    }
  }

  return (
    <div className="page-scroll bg-blobs">
    <div className="bg-blobs-clip">
      <div className="bg-blob bg-blob-magenta" />
      <div className="bg-blob bg-blob-blue" />
    </div>
    <div className="page-content" style={{ position: "relative", zIndex: 1 }}>

      {/* Update banner */}
      {isUpdateAvailable && latestVersion && dismissedVersion !== latestVersion && (
        <section>
          <UpdateBanner
            version={latestVersion}
            downloadUrl={downloadUrl}
            onDismiss={() => updateSettings({ dismissed_update_version: latestVersion })}
          />
        </section>
      )}

      {/* Greeting */}
      <section>
        <h2 className="text-subtitle">{getGreeting(user?.name, user?.email)}</h2>
        <p className="text-caption" style={{ marginTop: 4 }}>
          Wat wil je vandaag transcriberen?
        </p>
      </section>

      {/* Hero CTA — start recording */}
      <section>
        <p className="section-label">Snel starten</p>
        <button onClick={() => handleQuickStart("microphone")} className="hero-cta-card">
          <div className="hero-cta-rings">
            <div className="hero-cta-ring hero-cta-ring-1" />
            <div className="hero-cta-ring hero-cta-ring-2" />
            <div className="hero-cta-ring hero-cta-ring-3" />
            <MicRecord24Regular className="hero-cta-mic" />
          </div>
          <div className="hero-cta-text">
            <span className="hero-cta-title">Start nieuwe opname</span>
            <span className="hero-cta-subtitle">Tik om direct te beginnen met opnemen</span>
          </div>
          <ChevronRight24Regular className="hero-cta-chevron" />
        </button>

        <div className="flex-row gap-10" style={{ marginTop: 10 }}>
          <button onClick={() => handleQuickStart("microphone")} className="quick-start-pill">
            <People24Regular style={{ fontSize: 14 }} />
            Fysieke meeting
          </button>
          <button onClick={() => handleQuickStart("combined")} className="quick-start-pill">
            <VideoChat24Regular style={{ fontSize: 14 }} />
            Videocall
          </button>
        </div>
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
          <p className="section-label" style={{ margin: 0 }}>Recente sessies</p>
          {isLoading && <span className="text-caption" style={{ color: "var(--fill-accent-default)" }}>Laden...</span>}
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
        ) : transcripts.length === 0 ? (
          <div className="empty-state">
            <p className="empty-state-text">
              Nog geen transcripten. Start een opname om te beginnen.
            </p>
          </div>
        ) : (
          <div className="flex-col gap-10">
            {transcripts.map((transcript) => (
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
