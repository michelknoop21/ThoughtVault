import type { TranscriptTask } from "../types";

type SSECallback = (task: Partial<TranscriptTask>) => void;
type ErrorCallback = (error: Error) => void;
type CompleteCallback = () => void;

export class SSEClient {
  private eventSource: EventSource | null = null;
  private url: string;
  private token: string | null;

  constructor(url: string, token: string | null) {
    this.url = url;
    this.token = token;
  }

  connect(
    onUpdate: SSECallback,
    onError?: ErrorCallback,
    onComplete?: CompleteCallback
  ): void {
    // Append token as query param since EventSource doesn't support custom headers
    const urlWithAuth = this.token
      ? `${this.url}?token=${encodeURIComponent(this.token)}`
      : this.url;

    this.eventSource = new EventSource(urlWithAuth);

    this.eventSource.onmessage = (event) => {
      try {
        const data = normalizeTaskUpdate(JSON.parse(event.data));
        onUpdate(data);

        if (data.status === "completed" || data.status === "failed" || data.status === "cancelled") {
          this.disconnect();
          onComplete?.();
        }
      } catch (e) {
        console.error("[SSE] Parse error:", e);
      }
    };

    this.eventSource.onerror = () => {
      this.disconnect();
      onError?.(new Error("SSE verbinding verbroken"));
    };
  }

  disconnect(): void {
    if (this.eventSource) {
      this.eventSource.close();
      this.eventSource = null;
    }
  }
}

function normalizeTaskUpdate(raw: Record<string, unknown>): Partial<TranscriptTask> {
  return {
    task_id: String(raw.task_id ?? ""),
    status: raw.status as TranscriptTask["status"],
    progress: Number(raw.progress ?? 0),
    raw_transcription:
      (raw.raw_transcription as string | undefined)
      ?? (raw.transcription as string | undefined),
    notule_html:
      (raw.notule_html as string | undefined)
      ?? (raw.result as string | undefined),
    error_message: raw.error_message as string | undefined,
    duration_seconds: typeof raw.duration_seconds === "number" ? raw.duration_seconds : undefined,
    mode: (raw.mode as TranscriptTask["mode"]) ?? "microphone",
    created_at: String(raw.created_at ?? new Date().toISOString()),
    profile_id: raw.profile_id as string | undefined,
  };
}

export function createSSEClient(url: string): SSEClient {
  const stored = localStorage.getItem("auth-store");
  let token: string | null = null;
  if (stored) {
    try {
      const auth = JSON.parse(stored);
      token = auth.state?.token || null;
    } catch {
      // ignore
    }
  }
  return new SSEClient(url, token);
}
