import { invoke } from "@tauri-apps/api/core";
import type { CalendarEvent } from "../types";
import { useCalendarStore } from "../stores/calendarStore";
import { useSettingsStore } from "../stores/settingsStore";

const GRAPH_BASE = "https://graph.microsoft.com/v1.0";
const SCOPES = ["User.Read", "Calendars.Read"];

function buildAuthUrl(tenantId: string, clientId: string, redirectUri: string, codeChallenge: string, state: string): string {
  const params = new URLSearchParams({
    client_id: clientId,
    response_type: "code",
    redirect_uri: redirectUri,
    scope: SCOPES.join(" "),
    response_mode: "query",
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
    state,
  });
  return `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/authorize?${params}`;
}

function generateCodeVerifier(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return btoa(String.fromCharCode(...array))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function generateCodeChallenge(verifier: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

export class MicrosoftGraphService {
  private static codeVerifier: string | null = null;

  static async initiateAuth(): Promise<void> {
    const settings = useSettingsStore.getState();
    const tenantId = settings.ms365_tenant_id;
    const clientId = settings.ms365_client_id;

    if (!tenantId || !clientId) {
      throw new Error("Microsoft 365 client ID en tenant ID zijn niet geconfigureerd");
    }

    const verifier = generateCodeVerifier();
    const challenge = await generateCodeChallenge(verifier);
    this.codeVerifier = verifier;

    const state = crypto.randomUUID();
    sessionStorage.setItem("oauth_state", state);

    const redirectUri = "transcript-studio://auth/callback";
    const authUrl = buildAuthUrl(tenantId, clientId, redirectUri, challenge, state);

    const { open } = await import("@tauri-apps/plugin-shell");
    await open(authUrl);
  }

  static async handleAuthCallback(callbackUrl: string): Promise<void> {
    const url = new URL(callbackUrl);
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const storedState = sessionStorage.getItem("oauth_state");

    if (!code) throw new Error("Geen autorisatiecode ontvangen");
    if (state !== storedState) throw new Error("OAuth state mismatch - mogelijke CSRF aanval");
    if (!this.codeVerifier) throw new Error("Code verifier ontbreekt");

    const settings = useSettingsStore.getState();
    const tenantId = settings.ms365_tenant_id!;
    const clientId = settings.ms365_client_id!;

    // Use Tauri proxy to bypass CORS — Microsoft's token endpoint doesn't return
    // CORS headers for non-SPA (desktop/mobile) redirect URIs
    const tokenBody = new URLSearchParams({
      client_id: clientId,
      grant_type: "authorization_code",
      code,
      redirect_uri: "transcript-studio://auth/callback",
      code_verifier: this.codeVerifier,
      scope: SCOPES.join(" "),
    }).toString();

    const tokenResponse = await invoke<{ status: number; body: string; headers: Record<string, string> }>(
      "proxy_request",
      {
        request: {
          url: `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: tokenBody,
        },
      }
    );

    if (tokenResponse.status !== 200) {
      console.error("[OAuth] Token exchange failed:", tokenResponse.status, tokenResponse.body);
      throw new Error(`Token uitwisseling mislukt: ${tokenResponse.status}`);
    }

    const tokens = JSON.parse(tokenResponse.body);

    // Get user profile via proxy
    const profileResponse = await invoke<{ status: number; body: string; headers: Record<string, string> }>(
      "proxy_request",
      {
        request: {
          url: `${GRAPH_BASE}/me`,
          method: "GET",
          headers: { Authorization: `Bearer ${tokens.access_token}` },
        },
      }
    );
    const profile = JSON.parse(profileResponse.body);

    const calendarStore = useCalendarStore.getState();
    calendarStore.setConnected(
      profile.mail || profile.userPrincipalName,
      tokens.access_token,
      tokens.refresh_token,
      Date.now() + tokens.expires_in * 1000
    );

    this.codeVerifier = null;
    sessionStorage.removeItem("oauth_state");
  }

  static async getUpcomingEvents(): Promise<CalendarEvent[]> {
    const calendarStore = useCalendarStore.getState();
    if (!calendarStore.accessToken) return [];

    const now = new Date();
    const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);

    const params = new URLSearchParams({
      startDateTime: now.toISOString(),
      endDateTime: tomorrow.toISOString(),
      $top: "20",
      $orderby: "start/dateTime",
      $select: "id,subject,start,end,onlineMeeting,organizer,attendees",
    });

    try {
      const response = await invoke<{ status: number; body: string; headers: Record<string, string> }>(
        "proxy_request",
        {
          request: {
            url: `${GRAPH_BASE}/me/calendarView?${params}`,
            method: "GET",
            headers: {
              Authorization: `Bearer ${calendarStore.accessToken}`,
              Prefer: 'outlook.timezone="UTC"',
            },
          },
        }
      );

      if (response.status !== 200) {
        if (response.status === 401) {
          calendarStore.disconnect();
          return [];
        }
        throw new Error(`Graph API error: ${response.status}`);
      }

      const data = JSON.parse(response.body);
      const events: CalendarEvent[] = (data.value || []).map((e: Record<string, unknown>) => ({
        id: e.id as string,
        title: e.subject as string,
        start: (e.start as Record<string, string>).dateTime + "Z",
        end: (e.end as Record<string, string>).dateTime + "Z",
        join_url: (e.onlineMeeting as Record<string, string> | null)?.joinUrl,
        platform: detectPlatform((e.onlineMeeting as Record<string, string> | null)?.joinUrl),
        organizer: ((e.organizer as Record<string, Record<string, string>>)?.emailAddress?.name),
        attendees: ((e.attendees as Array<Record<string, Record<string, string>>>)?.map(
          (a) => a.emailAddress?.address  // Graph v1.0 key is "address", not "email" (RESEARCH A2/Pitfall 2)
        ).filter(Boolean)),
      }));

      calendarStore.setEvents(events);
      calendarStore.setLastSync(new Date().toISOString());
      return events;
    } catch {
      return [];
    }
  }
}

function detectPlatform(joinUrl?: string | null): CalendarEvent["platform"] {
  if (!joinUrl) return undefined;
  if (joinUrl.includes("teams.microsoft.com")) return "teams";
  if (joinUrl.includes("zoom.us")) return "zoom";
  if (joinUrl.includes("meet.google.com")) return "meet";
  if (joinUrl.includes("webex.com")) return "webex";
  if (joinUrl.includes("gotomeeting.com")) return "goto";
  if (joinUrl.includes("whereby.com")) return "whereby";
  if (joinUrl.includes("jitsi")) return "jitsi";
  return "other";
}
