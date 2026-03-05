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
import { api } from "../services/api";
import { MicrosoftGraphService } from "../services/microsoftGraph";
import type { CalendarEvent, Transcript } from "../types";

export function HomePage() {
  const navigate = useNavigate();
  const { setMode, setAutoStart } = useRecordingStore();
  const { transcripts, setTranscripts, deleteTranscript } = useTranscriptsStore();
  const calendar = useCalendarStore();
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
    <div style={{ padding: 24, display: "flex", flexDirection: "column", gap: 20, overflowY: "auto", height: "100%" }}>

      {/* Upcoming meetings */}
      {upcomingEvents.length > 0 && (
        <section>
          <p style={{ fontSize: 11, fontWeight: 600, color: "var(--text-tertiary)", textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 10 }}>
            Aankomende vergaderingen
          </p>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {upcomingEvents.map((event) => (
              <div
                key={event.id}
                className="card session-card"
                style={{ display: "flex", alignItems: "center", gap: 12 }}
              >
                <CalendarLtr24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)", flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                    {event.title}
                  </p>
                  <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>
                    {formatEventTime(event.start, event.end)}
                  </p>
                </div>
                {event.join_url && (
                  <button
                    onClick={() => handleRecordMeeting(event)}
                    className="btn btn-accent"
                    style={{ padding: "4px 10px", fontSize: 12, flexShrink: 0 }}
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

      {/* Recent sessions — primary content */}
      <section style={{ flex: 1, minHeight: 0, display: "flex", flexDirection: "column" }}>
        <p style={{ fontSize: 11, fontWeight: 600, color: "var(--text-tertiary)", textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 10 }}>
          Recente sessies
        </p>
        {transcripts.length === 0 ? (
          <div
            style={{
              padding: "24px 16px",
              textAlign: "center",
              border: "1px dashed var(--stroke-divider)",
              borderRadius: "var(--radius-lg)",
            }}
          >
            <p style={{ fontSize: 13, color: "var(--text-tertiary)" }}>
              Nog geen transcripten. Start een opname om te beginnen.
            </p>
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 10, overflowY: "auto", flex: 1 }}>
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

      {/* Quick start — bottom */}
      <section style={{ flexShrink: 0 }}>
        <p style={{ fontSize: 11, fontWeight: 600, color: "var(--text-tertiary)", textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 10 }}>
          Snel starten
        </p>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <button
            onClick={() => handleQuickStart("microphone")}
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 8,
              padding: "12px 16px",
              background: "transparent",
              border: "1px solid var(--stroke-card)",
              borderRadius: "var(--radius-lg)",
              color: "var(--text-primary)",
              fontSize: 13,
              fontWeight: 500,
              cursor: "pointer",
              transition: "border-color 67ms ease, background 67ms ease",
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = "var(--fill-accent-default)";
              (e.currentTarget as HTMLButtonElement).style.background = "rgba(229, 0, 116, 0.04)";
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = "var(--stroke-card)";
              (e.currentTarget as HTMLButtonElement).style.background = "transparent";
            }}
          >
            <People24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)" }} />
            Fysieke meeting
          </button>
          <button
            onClick={() => handleQuickStart("combined")}
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 8,
              padding: "12px 16px",
              background: "transparent",
              border: "1px solid var(--stroke-card)",
              borderRadius: "var(--radius-lg)",
              color: "var(--text-primary)",
              fontSize: 13,
              fontWeight: 500,
              cursor: "pointer",
              transition: "border-color 67ms ease, background 67ms ease",
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = "var(--fill-accent-default)";
              (e.currentTarget as HTMLButtonElement).style.background = "rgba(229, 0, 116, 0.04)";
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = "var(--stroke-card)";
              (e.currentTarget as HTMLButtonElement).style.background = "transparent";
            }}
          >
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
    <div
      className="card session-card"
      onClick={onClick}
    >
      {/* Header row: badge + date + menu */}
      <div className="session-card-header">
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span className="status-badge-accent">Sessie</span>
          <span style={{ fontSize: 11, color: "var(--text-tertiary)" }}>
            {formatDate(transcript.created_at)}
          </span>
        </div>
        <div style={{ position: "relative" }}>
          <button
            onClick={(e) => {
              e.stopPropagation();
              setMenuOpen(!menuOpen);
            }}
            style={{
              padding: 4,
              background: "transparent",
              border: "none",
              color: "var(--text-tertiary)",
              cursor: "pointer",
              borderRadius: "var(--radius-sm)",
              display: "flex",
            }}
          >
            <MoreHorizontal24Regular style={{ fontSize: 16 }} />
          </button>
          {menuOpen && (
            <div
              style={{
                position: "absolute",
                right: 0,
                top: "100%",
                background: "var(--surface-card)",
                border: "1px solid var(--stroke-card)",
                borderRadius: "var(--radius-md)",
                boxShadow: "var(--shadow-lg)",
                zIndex: 10,
                minWidth: 140,
                padding: 4,
              }}
              onClick={(e) => e.stopPropagation()}
            >
              <button
                onClick={() => {
                  setMenuOpen(false);
                  onDelete(transcript);
                }}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  width: "100%",
                  padding: "8px 12px",
                  background: "transparent",
                  border: "none",
                  color: "var(--text-error)",
                  fontSize: 12,
                  cursor: "pointer",
                  borderRadius: "var(--radius-sm)",
                }}
                onMouseEnter={(e) => {
                  (e.currentTarget as HTMLButtonElement).style.background = "rgba(196, 43, 28, 0.06)";
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLButtonElement).style.background = "transparent";
                }}
              >
                <Delete24Regular style={{ fontSize: 14 }} />
                Verwijderen
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Title */}
      <p className="session-card-title">
        {transcript.title || "Naamloze opname"}
      </p>

      {/* Preview text */}
      {previewText && (
        <p className="session-card-preview">
          {previewText}
        </p>
      )}

      {/* Bottom row: time ago + status */}
      <div className="session-card-meta">
        <span style={{ display: "flex", alignItems: "center", gap: 4 }}>
          <Clock24Regular style={{ fontSize: 12 }} />
          {formatTimeAgo(transcript.created_at)}
        </span>
        {isComplete && (
          <span className="status-badge-success">Voltooid</span>
        )}
      </div>
    </div>
  );
}

function getPreviewText(transcript: Transcript): string {
  if (transcript.notule_html) {
    // Strip HTML tags for preview
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

