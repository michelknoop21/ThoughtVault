import { invoke } from "@tauri-apps/api/core";
import { logRetry, TIME_LIMIT_MESSAGE, type RequestTrace } from "./modelRequestLog";

// Transport for every model request on Windows: the native proxy, time limits and one HTTP 429 retry.

/** Total time per model request, as on macOS. A cold local model plus a long non-streamed draft can need it. */
const LLM_TIME_LIMIT_SECONDS = 900;
/** A streamed request (the routed provider) ends after this much silence, like the macOS idle timeout; keep-alive lines and
 * reasoning deltas count as progress. A reasoning model can then write longer than 900 s, up to the outer limit. */
export const STREAM_IDLE_SECONDS = 300;
export const STREAM_TIME_LIMIT_SECONDS = 3600;
export type TimeLimits = { total: number; idle?: number };
/** Prefix of the proxy_request error for a timeout (http.rs). */
const PROXY_TIMEOUT = "Tijdslimiet bereikt";

/** Wait before retrying an HTTP 429 when the provider sends no usable Retry-After, as on macOS. */
export const RATE_LIMIT_DEFAULT_WAIT_MS = 2_000;
/** Longest Retry-After that is waited for; a provider asking more is reported as rate limiting right away. */
export const RATE_LIMIT_MAX_WAIT_MS = 30_000;
export const RATE_LIMIT_MESSAGE = "API-limiet bereikt (429), ook na een nieuwe poging. Probeer het later opnieuw of verwerk minder opnames tegelijk.";

/** Milliseconds to wait before retrying a 429: Retry-After as delta-seconds or HTTP date, else the default.
 * null when the provider asks for more than RATE_LIMIT_MAX_WAIT_MS. */
export function rateLimitWaitMs(retryAfter: string | undefined, now = Date.now()): number | null {
  const value = (retryAfter ?? "").trim();
  const wait = /^\d+$/.test(value) ? Number(value) * 1000 : /[a-z]/i.test(value) && !Number.isNaN(Date.parse(value))
    ? Math.max(0, Date.parse(value) - now) : RATE_LIMIT_DEFAULT_WAIT_MS;
  return wait <= RATE_LIMIT_MAX_WAIT_MS ? wait : null;
}

type ProxyResponse = { status: number; body: string; headers?: Record<string, string> };

export function checkModelCancellation(signal?: AbortSignal): void {
  if (signal?.aborted) throw new DOMException("Geannuleerd", "AbortError");
}

async function proxy(request: { url: string; headers: Record<string, string>; body: string }, timeoutSeconds: number, idleSeconds?: number, signal?: AbortSignal): Promise<ProxyResponse> {
  checkModelCancellation(signal);
  const requestId = signal ? await invoke<string>("register_proxy_request") : undefined;
  const cancel = () => { void invoke("cancel_proxy_request", { requestId }).catch(() => {}); };
  if (signal) signal.addEventListener("abort", cancel, { once: true });
  try {
    checkModelCancellation(signal);
    const response = await invoke<ProxyResponse>("proxy_request", { ...(requestId ? { requestId } : {}), request: { ...request, method: "POST", timeout_seconds: timeoutSeconds,
      ...(idleSeconds ? { idle_timeout_seconds: idleSeconds } : {}) } });
    checkModelCancellation(signal);
    return response;
  } catch (error) {
    checkModelCancellation(signal);
    const message = error instanceof Error ? error.message : String(error);
    throw message.startsWith(PROXY_TIMEOUT) ? new Error(TIME_LIMIT_MESSAGE) : error;
  } finally {
    signal?.removeEventListener("abort", cancel);
    if (requestId) await invoke("cancel_proxy_request", { requestId });
  }
}

function retryWait(ms: number, signal?: AbortSignal): Promise<void> {
  checkModelCancellation(signal);
  return new Promise((resolve, reject) => {
    const abort = () => { clearTimeout(timer); signal?.removeEventListener("abort", abort); reject(new DOMException("Geannuleerd", "AbortError")); };
    const timer = setTimeout(() => { signal?.removeEventListener("abort", abort); resolve(); }, ms);
    signal?.addEventListener("abort", abort, { once: true });
  });
}

/** Wait before sending a request again after its connection to a remote provider broke. */
export const CONNECTION_RETRY_WAIT_MS = 2_000;

/** A native connection failure (no HTTP answer) to a remote provider: sent once more after a short wait, within the
 * same time limit (TV-000024: both notule requests to OpenRouter broke at the same moment). A local server that refuses
 * the connection is not running, so retrying it only delays the message. Timeouts and cancellation are never retried. */
async function proxyWithReconnect(request: { url: string; headers: Record<string, string>; body: string }, trace: RequestTrace,
  limits: TimeLimits, started: number): Promise<ProxyResponse> {
  try {
    return await proxy(request, limits.total, limits.idle, trace.signal);
  } catch (error) {
    const remainingSeconds = Math.floor((limits.total * 1000 - (Date.now() - started) - CONNECTION_RETRY_WAIT_MS) / 1000);
    // proxy() turns a timeout and a cancellation into Error objects; a native connection failure stays the plain string from http.rs.
    if (typeof error !== "string" || !request.url.startsWith("https://") || remainingSeconds < 1) throw error;
    logRetry(trace, CONNECTION_RETRY_WAIT_MS, "connection error");
    await retryWait(CONNECTION_RETRY_WAIT_MS, trace.signal);
    return proxy(request, remainingSeconds, limits.idle, trace.signal);
  }
}

/** Every model request goes through here: one total time limit, a timeout named as such, one retry after a broken
 * connection to a remote provider, and one retry on HTTP 429
 * after the provider's Retry-After plus up to one second of jitter, so requests that were rate limited together do
 * not collide again. The wait and the retry count against the same time limit. A wait that is too long, and a
 * second 429, return the 429 to the caller, which reports it. Cancellation also stops the rate-limit wait and native HTTP connection. */
export async function modelRequest(request: { url: string; headers: Record<string, string>; body: string }, trace: RequestTrace,
  limits: TimeLimits = { total: LLM_TIME_LIMIT_SECONDS }): Promise<ProxyResponse> {
  const started = Date.now();
  const first = await proxyWithReconnect(request, trace, limits, started);
  trace.status = first.status;
  const header = Object.entries(first.headers ?? {}).find(([name]) => name.toLowerCase() === "retry-after")?.[1];
  const wait = first.status === 429 ? rateLimitWaitMs(header) : null;
  if (wait === null) return first;
  const jittered = wait + Math.random() * 1000;
  const remainingSeconds = Math.floor((limits.total * 1000 - (Date.now() - started) - jittered) / 1000);
  if (remainingSeconds < 1) return first;
  logRetry(trace, jittered);
  await retryWait(jittered, trace.signal);
  const second = await proxy(request, remainingSeconds, limits.idle, trace.signal);
  trace.status = second.status;
  return second;
}
