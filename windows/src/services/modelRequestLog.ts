import { log } from "./appLog";

export const TIME_LIMIT_MESSAGE = "Tijdslimiet bereikt: de AI-provider gaf niet op tijd een volledig antwoord. Probeer het opnieuw of kies een sneller model.";
export const TRUNCATED_MESSAGE = "Het antwoord van de AI-provider is afgebroken omdat het de maximale lengte bereikte.";

/** One step of notule generation, as on macOS (ModelStep). In the log `index` is the request's 1-based position;
 * in a progress report it is the number of finished requests. */
export interface ModelStep {
  kind: "draft" | "chunk-summary" | "source-check" | "note-check" | "coverage" | "sentence-check" | "context-suggestions";
  index?: number;
  total?: number;
}

/** Dutch task label, e.g. "Controle 12 van 61". */
export function stepLabel(step: ModelStep): string {
  const counted = (name: string) => `${name} ${step.index ?? 0} van ${step.total ?? 0}`;
  switch (step.kind) {
    case "draft": return "Concept schrijven";
    case "chunk-summary": return counted("Samenvatten");
    case "source-check": return "Broncontrole";
    case "note-check": return "Inhoudscontrole";
    case "coverage": return counted("Dekkingscontrole");
    case "sentence-check": return counted("Controle");
    case "context-suggestions": return "Contextsuggesties";
  }
}

function logLabel(step: ModelStep | undefined): string {
  if (!step) return "other";
  return step.index === undefined ? step.kind : `${step.kind} ${step.index}/${step.total ?? 0}`;
}

/** Metadata of one model request. `status` is set by the request once the provider answered. */
export interface RequestTrace {
  step?: ModelStep;
  provider: string;
  model: string;
  system: string;
  user: string;
  status?: number;
}

/** Only metadata: the log tail is attached to support reports (DEC-064), so prompt, transcript and notule
 * text never reach it. */
function head(trace: RequestTrace): string {
  return `step=${logLabel(trace.step)} provider=${trace.provider} model=${trace.model} input_chars=${trace.system.length + trace.user.length}`;
}

function outcome(error: unknown, status: number | undefined): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message === TIME_LIMIT_MESSAGE) return "timed out";
  if (message === TRUNCATED_MESSAGE) return "truncated";
  if (status !== undefined && status >= 400) return `HTTP ${status}`;
  return "error";
}

/** Start and end line per model request, as on macOS (ModelRequestLog). */
export async function logModelRequest<T>(trace: RequestTrace, run: () => Promise<T>): Promise<T> {
  log.info("ModelRequest", `model request start ${head(trace)}`);
  const started = Date.now();
  try {
    const result = await run();
    log.info("ModelRequest", `model request end ${head(trace)} ms=${Date.now() - started} outcome=ok`);
    return result;
  } catch (error) {
    log.warn("ModelRequest", `model request end ${head(trace)} ms=${Date.now() - started} outcome=${outcome(error, trace.status)}`);
    throw error;
  }
}

/** The request got HTTP 429 and is sent again after `waitMs`. */
export function logRetry(trace: RequestTrace, waitMs: number): void {
  log.info("ModelRequest", `model request retry step=${logLabel(trace.step)} after HTTP 429 wait_ms=${Math.round(waitMs)}`);
}
