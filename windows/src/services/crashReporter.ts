import { invoke } from "@tauri-apps/api/core";
import { log, mask, readClickPath, scrubReportText } from "./appLog";
import { isSupportReportDurable, useSupportStore } from "../stores/supportStore";
import type { ReportStage } from "./supportRelay";
import type { TaskStatus } from "../types";

export { initCrashReporter } from "./localCrashReporter";

export function stageForStatus(status: TaskStatus): ReportStage | null {
  switch (status) {
    case "generating": return "notule";
    case "pending": case "queued": case "uploading": case "downloading":
    case "converting": case "transcribing": case "paused": return "transcriberen";
    default: return null;
  }
}

export function failureFromTransition(prev: TaskStatus, next: TaskStatus, message?: string): { stage: ReportStage; message: string } | null {
  if ((next !== "failed" && next !== "error") || prev === "failed" || prev === "error" || message === "Geannuleerd door gebruiker.") return null;
  return { stage: stageForStatus(prev) ?? "transcriberen", message: message || "Onbekende fout" };
}

// Recognize complete app-generated messages; never retain dynamic URL/model/body text.
export function processingDiagnostic(message: string): { shown: string; code: string } | null {
  if (/^Kan de notule-generator niet bereiken op [^\r\n]+ \(model "[^\r\n]+"\)\. Draait Ollama\/LM Studio en klopt de URL in Instellingen\?$/.test(message)) {
    return { shown: "Kan de notule-generator niet bereiken. Controleer of Ollama/LM Studio draait en controleer de URL bij Instellingen.", code: "notule_connection_failed" };
  }
  const http = message.match(/^(?:Ollama Cloud|OpenAI|Anthropic|Notule-generator op [^\r\n]+) gaf HTTP ([45][0-9]{2})(?: voor model "[^\r\n]+")?\.$/);
  if (http) {
    // Group HTTP failures by cause; volatile numeric details do not define repetition keys.
    const cause = http[1] === "401" ? "unauthorized" : http[1] === "429" ? "rate_limited" : http[1][0] === "5" ? "server_error" : "client_error";
    return { shown: `De notule-generator gaf HTTP ${http[1]}. Controleer de instellingen of probeer later opnieuw.`, code: `notule_http_${cause}` };
  }
  const fixed: Record<string, string> = {
    "Ollama Cloud API-sleutel geweigerd.": "ollama_unauthorized",
    "OpenAI API-sleutel geweigerd.": "openai_unauthorized",
    "Anthropic API-sleutel geweigerd.": "anthropic_unauthorized",
    "Ollama Cloud API-limiet bereikt. Probeer later opnieuw.": "ollama_rate_limited",
    "OpenAI API-limiet bereikt. Probeer later opnieuw.": "openai_rate_limited",
    "Anthropic API-limiet bereikt. Probeer later opnieuw.": "anthropic_rate_limited",
    "Ollama Cloud gaf een leeg antwoord.": "ollama_empty_response",
    "De aanbieder gaf een leeg antwoord.": "provider_empty_response",
    "De notule-generator gaf een leeg concept.": "notule_empty_response",
    "De notule-generator gaf een leeg concept. De transcriptie is bewaard.": "notule_empty_response",
    "De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw.": "notule_unusable_content",
    "De notule-generator verkort de lange transcriptie onvoldoende. De transcriptie is bewaard; kies een ander model en probeer opnieuw.": "notule_context_limit",
  };
  const code = Object.prototype.hasOwnProperty.call(fixed, message) ? fixed[message] : undefined;
  return code ? { shown: message, code } : null;
}

export async function fingerprint(stage: string, errorText: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${stage}|${errorText.replace(/[0-9]/g, "")}`));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

// Callers must supply audited error metadata, never provider response bodies or meeting text.
export async function enqueueFailure(stage: ReportStage, shown: string, error: string, id: string): Promise<"queued" | "discarded" | "failed"> {
  try {
    log.error("Fout", `${stage}: ${mask(error)}`);
    if (!useSupportStore.getState().auto_report) return "discarded";
    const [key, shownMessage, errorText, clickPath] = await Promise.all([
      fingerprint(stage, error), scrubReportText(shown), scrubReportText(error),
      readClickPath().then(lines => Promise.all(lines.map(line => scrubReportText(line)))),
    ]);
    const store = useSupportStore.getState();
    if (!store.auto_report) return "discarded";
    store.enqueue({ id, kind: "auto", category: "BUG", stage,
      shownMessage: Array.from(shownMessage).slice(0, 5000).join(""),
      errorText: Array.from(errorText).slice(0, 2000).join(""), fingerprint: key,
      clickPath: clickPath.slice(-30).map(line => Array.from(line).slice(0, 80).join("")), occurredAt: new Date().toISOString() });
    return isSupportReportDurable(id) ? "queued" : "failed";
  } catch { return "failed"; }
}

// Public callers retain the non-throwing three-argument API.
export async function reportFailure(stage: ReportStage, shown: string, error: string): Promise<void> {
  try {
    if (await enqueueFailure(stage, shown, error, crypto.randomUUID()) === "queued") {
      void useSupportStore.getState().flushQueue().catch(() => {});
    }
  } catch { /* Diagnostics must not interrupt the caller. */ }
}

export async function markStage(stage: ReportStage | null): Promise<void> {
  try { await invoke("session_stage", { stage }); }
  catch { /* Session diagnostics must not interrupt processing. */ }
}
