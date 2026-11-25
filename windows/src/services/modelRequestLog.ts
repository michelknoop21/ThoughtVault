import { log } from "./appLog";
import type { Usage, UsageMeter } from "./usageMeter";

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
  signal?: AbortSignal;
  step?: ModelStep;
  provider: string;
  model: string;
  system: string;
  user: string;
  status?: number;
  /** Counts every request of one notule run; set by the caller. */
  meter?: UsageMeter;
  /** What the provider reported for this request; stays unset when no body arrived. */
  usage?: Usage;
}

/** Only metadata: the log tail is attached to support reports (DEC-064), so prompt, transcript and notule
 * text never reach it. */
function head(trace: RequestTrace): string {
  return `step=${logLabel(trace.step)} provider=${trace.provider} model=${trace.model} input_chars=${trace.system.length + trace.user.length}`;
}

/** Token and cost numbers only, when the provider reported usage. */
function usageFields(trace: RequestTrace): string {
  const u = trace.usage;
  if (!u) return "";
  return ` in_tok=${u.input ?? 0} out_tok=${u.output ?? 0} reason_tok=${u.reasoning ?? 0}${u.cost === undefined ? "" : ` cost=${u.cost}`}`;
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
    trace.meter?.record(trace.step?.kind, trace.usage);
    log.info("ModelRequest", `model request end ${head(trace)} ms=${Date.now() - started} outcome=ok${usageFields(trace)}`);
    return result;
  } catch (error) {
    trace.meter?.record(trace.step?.kind, trace.usage);
    log.warn("ModelRequest", `model request end ${head(trace)} ms=${Date.now() - started} outcome=${outcome(error, trace.status)}${usageFields(trace)}`);
    throw error;
  }
}

/** The request got HTTP 429, or lost its connection, and is sent again after `waitMs`. */
export function logRetry(trace: RequestTrace, waitMs: number, reason = "HTTP 429"): void {
  log.info("ModelRequest", `model request retry step=${logLabel(trace.step)} after ${reason} wait_ms=${Math.round(waitMs)}`);
}
