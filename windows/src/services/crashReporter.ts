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
