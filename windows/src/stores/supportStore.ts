import { create } from "zustand";
import { persist } from "zustand/middleware";
import { invoke } from "@tauri-apps/api/core";
import { loadCredential, storeCredential, getAppVersion } from "../services/tauriCommands";
import { log, readClickPath, readLogTail } from "../services/appLog";
import { registerInstallation, sendReport, unreadCount, RelayError } from "../services/supportRelay";
import type { Installation, ReportCategory, ReportStage, ReportPayload } from "../services/supportRelay";

export const SECRET_CREDENTIAL_KEY = "support_secret";
export interface QueuedReport {
  id: string; kind: "auto" | "manual"; category: ReportCategory; stage: ReportStage | "";
  shownMessage: string; errorText: string; fingerprint?: string; clickPath: string[]; occurredAt: string;
}
type Outcome = "sent" | "queued" | "failed";
interface SupportState {
  installation_id: string | null; name: string; email: string; auto_report: boolean;
  queue: QueuedReport[]; unread_count: number;
  setIdentity: (name: string, email: string) => void;
  setAutoReport: (value: boolean) => void;
  enqueue: (item: QueuedReport) => void;
  flushQueue: () => Promise<void>;
  refreshUnread: () => Promise<void>;
  submitManual: (category: ReportCategory, description: string) => Promise<Outcome>;
}
export function isValidEmail(value: string): boolean { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()); }
let registered: Installation | null = null;
let registration: Promise<Installation> | null = null;
let flushing: Promise<void> | null = null;
let activeId: string | null = null;
let retryAt = 0;
// shortcut: suppression survives this process only; restart after failed storage needs server idempotency.
const completed = new Set<string>();
const submissions = new Map<string, Outcome>();

function save(change: Partial<SupportState>): boolean {
  try { useSupportStore.setState(change); return true; }
  catch { log.warn("Melden", "De supportgegevens konden niet worden bewaard."); return false; }
}
export function isSupportReportDurable(id: string): boolean {
  try {
    const value = JSON.parse(localStorage.getItem("support-store") ?? "null");
    return value?.state?.queue?.some((item: QueuedReport) => item.id === id) === true;
  } catch { return false; }
}
function checkBackoff(): void {
  if (Date.now() < retryAt) throw new RelayError(429, "De supportserver vraagt even te wachten.", Math.ceil((retryAt - Date.now()) / 1000));
}
function backoff(error: unknown): void {
  if (error instanceof RelayError && (error.retryAfterSeconds !== undefined || error.status === 429)) {
    retryAt = Math.max(retryAt, Date.now() + (error.retryAfterSeconds ?? 60) * 1000);
  }
}
function secret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function installation(force?: Installation): Promise<Installation> {
  checkBackoff();
  if (registration) return registration;
  if (force && registered !== force && registered) return Promise.resolve(registered);
  if (force) registered = null;
  registration = (async () => {
    let id = useSupportStore.getState().installation_id;
    let value = await loadCredential(SECRET_CREDENTIAL_KEY);
    if (!value) { value = secret(); await storeCredential(SECRET_CREDENTIAL_KEY, value); }
    if (!id) {
      id = crypto.randomUUID();
      if (!save({ installation_id: id })) throw new Error("Support identity could not be stored");
    }
    if (registered?.id === id && registered.secret === value) return registered;
    checkBackoff();
    if (await registerInstallation(id, value) === "conflict") {
      id = crypto.randomUUID(); value = secret();
      await storeCredential(SECRET_CREDENTIAL_KEY, value);
      if (!save({ installation_id: id })) throw new Error("Support identity could not be stored");
      checkBackoff();
      if (await registerInstallation(id, value) === "conflict") throw new RelayError(409, "Supportaanmelding mislukt.");
    }
    registered = { id, secret: value };
    return registered;
  })().finally(() => { registration = null; });
  return registration;
}
export async function withInstallation<T>(call: (inst: Installation) => Promise<T>): Promise<T> {
  try {
    const inst = await installation();
    checkBackoff();
    try { return await call(inst); }
    catch (error) {
      if (!(error instanceof RelayError) || error.status !== 401) throw error;
      const recovered = await installation(inst);
      checkBackoff();
      return await call(recovered);
    }
  } catch (error) { backoff(error); throw error; }
}
function removeCompleted(): void {
  const queue = useSupportStore.getState().queue.filter(item => !completed.has(item.id));
  if (save({ queue })) completed.clear();
}
function finish(id: string, outcome: "sent" | "failed"): void {
  completed.add(id);
  if (submissions.has(id)) submissions.set(id, outcome);
  removeCompleted();
}
async function flush(): Promise<void> {
  removeCompleted();
  while (true) {
    const current = useSupportStore.getState();
    const item = current.queue.find(entry => !completed.has(entry.id));
    if (!item || !current.name.trim() || !isValidEmail(current.email)) return;
    if (item.kind === "auto" && !current.auto_report) { finish(item.id, "failed"); continue; }
    // A failed persist must not turn an in-memory entry into an apparent durable submission.
    if (!isSupportReportDurable(item.id)) return;
    activeId = item.id;
    try {
      const [logTail, appVersion, specs] = await Promise.all([
        readLogTail(), getAppVersion(), invoke<{ cpu: string; memory_gb: number; os_version: string }>("get_system_specs"),
      ]);
      const latest = useSupportStore.getState();
      if (!latest.name.trim() || !isValidEmail(latest.email)) return;
      if (!latest.queue.some(entry => entry.id === item.id) || (item.kind === "auto" && !latest.auto_report)) continue;
      const { id: _id, ...metadata } = item;
      const payload: ReportPayload = { ...metadata, log: logTail, appVersion, os: specs.os_version,
        device: `${specs.cpu}, ${specs.memory_gb} GB`, platform: "windows", name: latest.name, email: latest.email };
      const send = (reportLog: string) => withInstallation(async inst => {
        const current = useSupportStore.getState();
        if (!current.queue.some(entry => entry.id === item.id) || (item.kind === "auto" && !current.auto_report)) return "cancelled";
        if (!current.name.trim() || !isValidEmail(current.email)) return "hold";
        await sendReport(inst, { ...payload, log: reportLog, name: current.name, email: current.email });
        return "accepted";
      });
      let outcome: string;
      try { outcome = await send(logTail); }
      catch (error) {
        if (!(error instanceof RelayError) || error.status !== 413) throw error;
        outcome = await send("");
      }
      if (outcome === "hold") return;
      if (outcome === "accepted") finish(item.id, "sent");
    } catch (error) {
      if (!(error instanceof RelayError) || error.status === 0 || error.status === 429 || error.status >= 500) return;
      log.warn("Melden", `Supportmelding afgewezen (HTTP ${error.status}).`);
      finish(item.id, "failed");
    } finally { activeId = null; }
  }
}
export const useSupportStore = create<SupportState>()(persist((_set, get) => ({
  installation_id: null, name: "", email: "", auto_report: true, queue: [], unread_count: 0,
  setIdentity: (name, email) => { save({ name: name.trim(), email: email.trim() }); },
  setAutoReport: value => { save({ auto_report: value, queue: value ? get().queue : get().queue.filter(item => item.kind === "manual") }); },
  enqueue: item => {
    if (item.kind === "auto" && !get().auto_report) return;
    // Copy only metadata, even if an untyped caller supplies extra fields.
    const metadata: QueuedReport = { id: item.id, kind: item.kind, category: item.category, stage: item.stage,
      shownMessage: item.shownMessage, errorText: item.errorText, fingerprint: item.fingerprint,
      clickPath: [...item.clickPath], occurredAt: item.occurredAt };
    const queue = [...get().queue.filter(entry => entry.id !== item.id), metadata];
    const active = queue.find(entry => entry.id === activeId);
    save({ queue: active ? [active, ...queue.filter(entry => entry.id !== activeId).slice(-49)] : queue.slice(-50) });
  },
  flushQueue: () => {
    if (!flushing) flushing = flush().finally(() => { flushing = null; });
    return flushing;
  },
  refreshUnread: async () => {
    try { const unread_count = await withInstallation(unreadCount); save({ unread_count }); }
    catch { /* Keep the previous unread count while offline or throttled. */ }
  },
  submitManual: async (category, description) => {
    const id = crypto.randomUUID();
    const item: QueuedReport = { id, kind: "manual", category, stage: "", errorText: "",
      shownMessage: Array.from(description).slice(0, 5000).join(""), clickPath: await readClickPath(), occurredAt: new Date().toISOString() };
    get().enqueue(item);
    if (!isSupportReportDurable(id)) { save({ queue: get().queue.filter(entry => entry.id !== id) }); return "failed"; }
    submissions.set(id, "queued");
    await get().flushQueue();
    const outcome = submissions.get(id) ?? "failed";
    submissions.delete(id);
    await get().refreshUnread();
    return outcome === "queued" && !isSupportReportDurable(id) ? "failed" : outcome;
  },
}), {
  name: "support-store",
  partialize: state => ({ installation_id: state.installation_id, name: state.name, email: state.email,
    auto_report: state.auto_report, queue: state.queue, unread_count: state.unread_count }),
}));
