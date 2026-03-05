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
} from "@fluentui/react-icons";
import { useRecordingStore } from "../stores/recordingStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useCalendarStore } from "../stores/calendarStore";
import { useAuthStore } from "../stores/authStore";
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
  const { transcripts, setTranscripts, deleteTranscript } = useTranscriptsStore();
  const calendar = useCalendarStore();
  const user = useAuthStore((s) => s.user);
  const [upcomingEvents, setUpcomingEvents] = useState<CalendarEvent[]>([]);

  useEffect(() => {
    loadRecentTranscripts();
    if (calendar.isConnected) {
      loadCalendarEvents();
    }
  }, []);

  async function loadRecentTranscripts() {
    const data = await api.getTranscripts({ limit: 50 });
    setTranscripts(data);
  }

  async function loadCalendarEvents() {
    const events = await MicrosoftGraphService.getUpcomingEvents();
    setUpcomingEvents(events.slice(0, 3));
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
    <div className="page-content">

      {/* Greeting */}
      <section>
        <h2 className="text-subtitle">{getGreeting(user?.name, user?.email)}</h2>
        <p className="text-caption" style={{ marginTop: 4 }}>
          Wat wil je vandaag transcriberen?
        </p>
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
        <p className="section-label">Recente sessies</p>
        {transcripts.length === 0 ? (
          <div className="empty-state">
            <p className="empty-state-text">
              Nog geen transcripten. Start een opname om te beginnen.
            </p>
          </div>
        ) : (
          <div className="flex-col gap-10" style={{ overflowY: "auto", flex: 1 }}>
            {transcripts.map((transcript) => (
              <SessionCard
                key={transcript.id}
                transcript={transcript}
                onClick={() => navigate("/transcripts")}
                onDelete={handleDeleteTranscript}
              />
            ))}
          </div>
        )}
      </section>

      {/* Quick start */}
      <section className="flex-shrink-0">
        <p className="section-label">Snel starten</p>
        <div className="grid-2 gap-12">
          <button onClick={() => handleQuickStart("microphone")} className="quick-start-btn">
            <People24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)" }} />
            Fysieke meeting
          </button>
          <button onClick={() => handleQuickStart("combined")} className="quick-start-btn">
            <VideoChat24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)" }} />
            Videocall
          </button>
        </div>
      </section>

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
  const isComplete = !!transcript.notule_html || !!transcript.raw_transcription;

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
      <p className="session-card-title">{transcript.title || "Naamloze opname"}</p>

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

function getPreviewText(transcript: Transcript): string {
  if (transcript.notule_html) {
    const text = transcript.notule_html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
    return text.slice(0, 200);
  }
  if (transcript.raw_transcription) {
    return transcript.raw_transcription.slice(0, 200);
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
  return `${fmt(s)} – ${fmt(e)}`;
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("nl-NL", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
