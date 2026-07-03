import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  VideoChat24Regular,
  MicRecord24Regular,
  Dismiss24Regular,
  Calendar24Regular,
} from "@fluentui/react-icons";
import { useCalendarStore } from "../../stores/calendarStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { MicrosoftGraphService } from "../../services/microsoftGraph";
import { sendMeetingNotification } from "../../services/meetingNotifications";
import type { CalendarEvent } from "../../types";

const ALERT_LOOKAHEAD_MS = 5 * 60 * 1000; // 5 minutes before meeting
const CHECK_INTERVAL_MS  = 60 * 1000;      // check every minute

export function CallAlertOverlay() {
  const navigate = useNavigate();
  const calendar = useCalendarStore();
  const { setMode, setAutoStart, setPendingSeedAttendees } = useRecordingStore();
  const [upcomingAlert, setUpcomingAlert] = useState<CalendarEvent | null>(null);
  const [dismissed, setDismissed] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!calendar.isConnected) return;

    // Initial load
    MicrosoftGraphService.getUpcomingEvents();

    const interval = setInterval(() => {
      MicrosoftGraphService.getUpcomingEvents();
      checkForUpcoming();
    }, CHECK_INTERVAL_MS);

    checkForUpcoming();
    return () => clearInterval(interval);
  }, [calendar.isConnected]);

  useEffect(() => {
    checkForUpcoming();
  }, [calendar.events]);

  function checkForUpcoming() {
    const now = Date.now();
    const upcoming = calendar.events.find((event) => {
      if (dismissed.has(event.id)) return false;
      const start = new Date(event.start).getTime();
      const msBefore = start - now;
      return msBefore > 0 && msBefore <= ALERT_LOOKAHEAD_MS;
    });

    setUpcomingAlert(upcoming || null);
    // Send OS notification for the detected meeting
    if (upcoming) {
      sendMeetingNotification(upcoming);
    }
  }

  function handleDismiss() {
    if (upcomingAlert) {
      setDismissed((prev) => new Set([...prev, upcomingAlert.id]));
    }
    setUpcomingAlert(null);
  }

  function handleRecord(event: CalendarEvent) {
    const mode = event.join_url ? "combined" : "microphone";
    setMode(mode);
    setAutoStart(true);
    // Store attendee emails so SeedReviewSheet can filter new people on stop (D-07/D-10)
    setPendingSeedAttendees(event.attendees?.filter(Boolean) ?? []);
    // Signal that main window should minimize after recording starts
    useRecordingStore.getState().setMinimizeOnAutoStart(true);
    handleDismiss();
    navigate("/recording");
  }

  if (!upcomingAlert) return null;

  const startTime = new Date(upcomingAlert.start).toLocaleTimeString("nl-NL", {
    hour: "2-digit",
    minute: "2-digit",
  });

  const isVideoCall = !!upcomingAlert.join_url;

  return (
    <div
      className="fixed bottom-6 right-6 z-50 animate-reveal-up"
      style={{ maxWidth: 340 }}
    >
      <div
        className="card-elevated rounded-xl overflow-hidden"
        style={{ border: "1px solid var(--stroke-card)" }}
      >
        {/* Brand bar top */}
        <div className="brand-bar" />

        <div className="p-4">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <div
                className="w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0"
                style={{
                  background: isVideoCall
                    ? "rgba(144, 72, 240, 0.10)"
                    : "rgba(0, 120, 212, 0.10)",
                }}
              >
                {isVideoCall
                  ? <VideoChat24Regular style={{ color: "#9048F0", fontSize: 20 }} />
                  : <Calendar24Regular style={{ color: "#0078D4", fontSize: 20 }} />
                }
              </div>
              <div className="min-w-0">
                <p
                  className="text-sm font-semibold truncate"
                  style={{ color: "var(--text-primary)" }}
                >
                  {upcomingAlert.title}
                </p>
                <p className="text-xs" style={{ color: "var(--text-tertiary)" }}>
                  Begint om {startTime}
                  {upcomingAlert.platform && ` · ${upcomingAlert.platform}`}
                </p>
              </div>
            </div>
            <button
              onClick={handleDismiss}
              className="flex-shrink-0 w-7 h-7 flex items-center justify-center rounded-md transition-colors"
              style={{ color: "var(--text-tertiary)" }}
              title="Sluiten"
            >
              <Dismiss24Regular style={{ fontSize: 16 }} />
            </button>
          </div>

          <div className="flex gap-2 mt-3">
            <button
              onClick={() => handleRecord(upcomingAlert)}
              className="btn btn-accent flex-1 text-xs"
            >
              <MicRecord24Regular style={{ fontSize: 14 }} />
              {isVideoCall ? "Videocall opnemen" : "Meeting opnemen"}
            </button>
            <button
              onClick={handleDismiss}
              className="btn btn-ghost text-xs px-3"
            >
              Negeren
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
