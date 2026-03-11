import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useAuthStore } from "../stores/authStore";
import type { TranscriptTask } from "../types";

type SSECallback = (task: Partial<TranscriptTask>) => void;
type ErrorCallback = (error: Error) => void;
type CompleteCallback = () => void;

export class SSEClient {
  private unlisten: (() => void) | null = null;
  private unlistenDone: (() => void) | null = null;
  private url: string;
  private token: string | null;

  constructor(url: string, token: string | null) {
    this.url = url;
    this.token = token;
  }

  async connect(
    onUpdate: SSECallback,
    onError?: ErrorCallback,
    onComplete?: CompleteCallback
  ): Promise<void> {
    const eventName = `sse-${Date.now()}`;

    // Listen for SSE data events from Tauri backend
    this.unlisten = await listen<string>(eventName, (event) => {
      try {
        const data = normalizeTaskUpdate(JSON.parse(event.payload));
        onUpdate(data);

        if (data.status === "completed" || data.status === "failed" || data.status === "cancelled") {
          this.disconnect();
          onComplete?.();
        }
      } catch (e) {
        console.error("[SSE] Parse error:", e);
      }
    });

    this.unlistenDone = await listen(`${eventName}-done`, () => {
      this.disconnect();
      onComplete?.();
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
      this.disconnect();
      onError?.(new Error(typeof e === "string" ? e : "SSE verbinding mislukt"));
    }
  }

  disconnect(): void {
    this.unlisten?.();
    this.unlisten = null;
    this.unlistenDone?.();
    this.unlistenDone = null;
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
