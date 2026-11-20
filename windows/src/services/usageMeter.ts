import DOMPurify from "dompurify";
import { htmlToPlainText } from "../utils/htmlToMarkdown";
import { noteSentenceCount } from "./notuleAudit";
import type { MonthUsage, NotuleBilling, NotuleDetailLevel, NotuleUsage } from "../types";

/** What a provider reported for one request. A field is unset when the provider did not send it. */
export interface Usage { input?: number; output?: number; reasoning?: number; cost?: number }

const num = (value: unknown): number | undefined => typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;

/** Reads `usage` of an OpenAI-compatible body (prompt_tokens, completion_tokens, usage.cost on OpenRouter) or
 * an Anthropic body (input_tokens, output_tokens). undefined when there is nothing usable. */
export function parseUsage(raw: unknown): Usage | undefined {
  if (!raw || typeof raw !== "object") return undefined;
  const u = raw as Record<string, unknown>;
  const details = u.completion_tokens_details as Record<string, unknown> | undefined;
  const usage: Usage = {
    input: num(u.prompt_tokens) ?? num(u.input_tokens),
    output: num(u.completion_tokens) ?? num(u.output_tokens),
    reasoning: num(details?.reasoning_tokens),
    cost: num(u.cost),
  };
  return usage.input === undefined && usage.output === undefined ? undefined : usage;
}

/** Counts the requests of one notule run. Requests run in parallel; every field is a plain total. */
export class UsageMeter {
  private readonly started = Date.now();
  provider = "";
  model = "";
  billing: NotuleBilling = "metered";
  contentCheckSkipped = false;
  detailLevel?: NotuleDetailLevel;
  private requests = 0;
  private unknownRequests = 0;
  private input = 0;
  private output = 0;
  private reasoning = 0;
  private cost = 0;
  private costUnknown = false;
  private steps: NotuleUsage["steps"] = {};

  /** One finished request; `usage` undefined when no body arrived or it had no usage. */
  record(kind: string | undefined, usage?: Usage): void {
    this.requests += 1;
    const step = (this.steps[kind ?? "other"] ??= { requests: 0, input_tokens: 0, output_tokens: 0 });
    step.requests += 1;
    if (!usage) this.unknownRequests += 1;
    this.input += usage?.input ?? 0;
    this.output += usage?.output ?? 0;
    this.reasoning += usage?.reasoning ?? 0;
    step.input_tokens += usage?.input ?? 0;
    step.output_tokens += usage?.output ?? 0;
    // Free and subscription runs cost nothing; for the others one request without a cost makes the total unknown.
    if (this.billing === "metered" || this.billing === "unpriced") {
      if (usage?.cost === undefined) this.costUnknown = true;
      else this.cost += usage.cost;
    }
  }

  get hasRequests(): boolean { return this.requests > 0; }
  get costKnown(): boolean { return !this.costUnknown; }
  get totalCost(): number { return this.cost; }
  get requestCount(): number { return this.requests; }

  /** The record stored on the transcript, once the notule html is final. */
  usageFor(transcription: string, html: string): NotuleUsage {
    const text = htmlToPlainText(DOMPurify.sanitize(html));
    return {
      provider: this.provider, model: this.model, billing: this.billing,
      transcript_chars: transcription.length, notule_chars: text.length, words: wordCount(text),
      sentences: noteSentenceCount(text),
      requests: this.requests, unknown_requests: this.unknownRequests,
      input_tokens: this.input, output_tokens: this.output, reasoning_tokens: this.reasoning,
      cost_usd: this.costUnknown ? null : this.cost,
      duration_ms: Date.now() - this.started, steps: this.steps,
      content_check: this.contentCheckSkipped ? "skipped" : "ran",
      ...(this.detailLevel ? { detail_level: this.detailLevel } : {}),
    };
  }
}

export const wordCount = (text: string): number => text.split(/\s+/).filter(Boolean).length;

/** Month key of a date in local time, "yyyy-MM". */
export const monthKey = (date: Date): string => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;

/** Adds one run to the ledger. `notule` is false for a run that failed but still spent requests. */
export function addToLedger(ledger: Record<string, MonthUsage>, meter: UsageMeter, notule: boolean, now = new Date()): Record<string, MonthUsage> {
  const key = monthKey(now);
  const month = ledger[key] ?? { notules: 0, requests: 0, cost_usd: 0, unknown_cost_runs: 0 };
  return { ...ledger, [key]: {
    notules: month.notules + (notule ? 1 : 0),
    requests: month.requests + meter.requestCount,
    cost_usd: month.cost_usd + meter.totalCost,
    unknown_cost_runs: month.unknown_cost_runs + (meter.costKnown ? 0 : 1),
  } };
}

/** Fixed approximation of the dollar-euro rate, not a live rate: the amounts are indicative. */
export const USD_TO_EUR = 0.86;

const nl = (value: number, digits = 0) => value.toLocaleString("nl-NL", { minimumFractionDigits: digits, maximumFractionDigits: digits });

export function formatEuro(usd: number): string {
  const eur = usd * USD_TO_EUR;
  return eur < 0.005 ? "minder dan € 0,01" : `ongeveer € ${nl(eur, 2)}`;
}

function formatDuration(ms: number): string {
  const seconds = Math.max(1, Math.round(ms / 1000));
  return seconds < 60 ? `${seconds} s` : `${Math.floor(seconds / 60)} min ${seconds % 60} s`;
}

const PROVIDER_NAMES: Record<string, string> = { openrouter: "OpenRouter", openai: "OpenAI", anthropic: "Anthropic", ollama: "Ollama", "lm-studio": "LM Studio" };

/** Footer line of a notule. Old records have no usage: only length and words, computed from the html. */
export function usageLine(usage: NotuleUsage | undefined, html: string): string {
  if (!usage) {
    const text = htmlToPlainText(DOMPurify.sanitize(html));
    return `${nl(text.length)} tekens · ${nl(wordCount(text))} woorden`;
  }
  const cost = usage.billing === "free" ? "gratis, op deze pc"
    : usage.billing === "subscription" ? "via je Ollama-abonnement"
    : usage.cost_usd === null ? "kosten niet bekend in de app" : formatEuro(usage.cost_usd);
  return [
    `${nl(usage.notule_chars)} tekens`, `${nl(usage.words)} woorden`,
    `${nl(usage.requests)} ${usage.requests === 1 ? "verzoek" : "verzoeken"}`, cost, formatDuration(usage.duration_ms),
    `${PROVIDER_NAMES[usage.provider] ?? usage.provider}, ${usage.model.split("/").pop()}`,
    ...(usage.content_check === "skipped" ? ["niet automatisch gecontroleerd"] : []),
  ].join(" · ");
}
