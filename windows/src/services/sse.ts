import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useAuthStore } from "../stores/authStore";
import type { TranscriptTask } from "../types";

type SSECallback = (task: Partial<TranscriptTask>) => void;
type ErrorCallback = (error: Error) => void;
type CompleteCallback = () => void;

const TERMINAL_STATUSES = new Set(["completed", "failed", "cancelled", "error"]);
const MAX_RECONNECT_ATTEMPTS = 5;

export class SSEClient {
  private unlisten: (() => void) | null = null;
  private unlistenDone: (() => void) | null = null;
  private unlistenInterrupted: (() => void) | null = null;
  private url: string;
  private token: string | null;

  // Reconnect state
  private reconnectAttempts = 0;
  private terminalReached = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private isStopped = false;

  // Callbacks stored for reconnect use
  private onUpdate: SSECallback | null = null;
  private onError: ErrorCallback | undefined = undefined;
  private onComplete: CompleteCallback | undefined = undefined;

  constructor(url: string, token: string | null) {
    this.url = url;
    this.token = token;
  }

  async connect(
    onUpdate: SSECallback,
    onError?: ErrorCallback,
    onComplete?: CompleteCallback
  ): Promise<void> {
    this.onUpdate = onUpdate;
    this.onError = onError;
    this.onComplete = onComplete;
    this.isStopped = false;
    await this._startStream();
  }

  private async _startStream(): Promise<void> {
    if (this.isStopped) return;

    const eventName = `sse-${Date.now()}`;

    // Listen for SSE data events from Tauri backend
    this.unlisten = await listen<string>(eventName, (event) => {
      if (this.isStopped) return;
      try {
        const data = normalizeTaskUpdate(JSON.parse(event.payload));
        // A successful data event proves the stream is healthy again — reset the
        // backoff budget so a long-lived stream that reconnected once earlier
        // still gets a full retry allowance on a later drop.
        this.reconnectAttempts = 0;
        this.onUpdate?.(data);

        if (TERMINAL_STATUSES.has(data.status ?? "")) {
          this.terminalReached = true;
          this.disconnect();
          this.onComplete?.();
        }
      } catch (e) {
        console.error("[SSE] Parse error:", e);
      }
    });

    // Clean DONE sentinel — successful stream completion
    this.unlistenDone = await listen(`${eventName}-done`, () => {
      if (this.isStopped) return;
      this.reconnectAttempts = 0;
      this.disconnect();
      this.onComplete?.();
    });

    // Interrupted stream (no [DONE] received) — attempt reconnect unless terminal
    this.unlistenInterrupted = await listen(`${eventName}-interrupted`, () => {
      if (this.isStopped) return;
      if (this.terminalReached) {
        // Terminal status already seen — treat as clean completion
        this.disconnect();
        this.onComplete?.();
      } else {
        this._clearListeners();
        this._reconnect();
      }
    });

    // Start the SSE stream via Tauri IPC — token goes in headers, not URL
    const headers: Record<string, string> = {};
    if (this.token) {
      headers["X-User-Token"] = this.token;
    }

    try {
      await invoke("http_sse_stream", {
        url: this.url,
        headers: Object.keys(headers).length > 0 ? headers : null,
        eventName,
      });
    } catch (e) {
      if (this.isStopped) return;
      // Connect-time failure — route through reconnect logic
      this._clearListeners();
      this._reconnect();
    }
  }

  private _reconnect(): void {
    if (this.isStopped) return;

    // Re-entry guard: the `-interrupted` listener and the invoke() catch are two
    // independent paths that can both call _reconnect() for the same stream.
    // Without this, each schedules its own timer → zombie parallel streams.
    if (this.reconnectTimer !== null) return;

    if (this.reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
      this.disconnect();
      this.onError?.(new Error("SSE verbinding verbroken"));
      return;
    }

    this.reconnectAttempts += 1;
    // Exponential backoff: 2s, 4s, 8s, 16s, 16s — mirrors macOS pow(2, attempt) capped at 16
    const backoffMs = Math.min(Math.pow(2, this.reconnectAttempts), 16) * 1000;
    console.warn(`[SSE] Verbinding onderbroken, reconnect poging ${this.reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS} over ${backoffMs / 1000}s`);

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this._startStream();
    }, backoffMs);
  }

  private _clearListeners(): void {
    this.unlisten?.();
    this.unlisten = null;
    this.unlistenDone?.();
    this.unlistenDone = null;
    this.unlistenInterrupted?.();
    this.unlistenInterrupted = null;
  }

  disconnect(): void {
    this.isStopped = true;

    // Cancel any pending reconnect timer
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    this._clearListeners();
  }
}

/** Safely extract a string value, skipping objects/arrays. */
function safeStr(val: unknown): string | undefined {
  if (typeof val === "string") return val;
  return undefined;
}

function normalizeTaskUpdate(raw: Record<string, unknown>): Partial<TranscriptTask> {
  return {
    task_id: String(raw.task_id ?? ""),
    status: raw.status as TranscriptTask["status"],
    progress: Number(raw.progress ?? 0),
    raw_transcription: safeStr(raw.raw_transcription) ?? safeStr(raw.transcription),
    notule_html: safeStr(raw.notule_html) ?? safeStr(raw.result),
    error_message: safeStr(raw.error_message),
    duration_seconds: typeof raw.duration_seconds === "number" ? raw.duration_seconds : undefined,
    mode: (raw.mode as TranscriptTask["mode"]) ?? "microphone",
    created_at: String(raw.created_at ?? new Date().toISOString()),
    profile_id: safeStr(raw.profile_id),
  };
}

export function createSSEClient(url: string): SSEClient {
  const token = useAuthStore.getState().token;
  return new SSEClient(url, token);
}
