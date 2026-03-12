import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from "@tauri-apps/plugin-notification";
import type { CalendarEvent } from "../types";

const notifiedEventIds = new Set<string>();

export async function initMeetingNotifications(): Promise<void> {
  if (!(await isPermissionGranted())) {
    await requestPermission();
  }
}

export async function sendMeetingNotification(event: CalendarEvent): Promise<void> {
  if (notifiedEventIds.has(event.id)) return;
  notifiedEventIds.add(event.id);

  const permitted = await isPermissionGranted();
  if (!permitted) return;

  const startTime = new Date(event.start).toLocaleTimeString("nl-NL", {
    hour: "2-digit",
    minute: "2-digit",
  });

  sendNotification({
    title: event.title,
    body: `Begint om ${startTime}${event.platform ? ` · ${event.platform}` : ""}`,
  });
}
