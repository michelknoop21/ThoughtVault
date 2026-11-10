import { invoke } from "@tauri-apps/api/core";

export const SUPPORT_BASE_URL = "https://thoughtvault.yinga.ai/support";
export type ReportCategory = "BUG" | "FEATURE_REQUEST" | "QUESTION";
export type ReportStage = "opnemen" | "transcriberen" | "notule" | "crash";
export type HubStatus = "NEW" | "IN_PROGRESS" | "WAITING_FOR_USER" | "RESOLVED" | "CLOSED";
export interface Installation { id: string; secret: string }
export interface ReportPayload {
  kind: "auto" | "manual"; category: ReportCategory; stage: ReportStage | "";
  shownMessage: string; errorText: string; fingerprint?: string; clickPath: string[];
  appVersion: string; os: string; device: string; platform: "windows";
  name: string; email: string; occurredAt: string; log: string;
}
export interface ReportResult { ticketId: string; ref: string; repeated: boolean; count: number; logAttached: boolean }
export interface SupportLastMessage { senderRole: string; createdAt: string; excerpt: string }
export interface SupportTicket {
  id: string; ref: string; status: HubStatus; category: ReportCategory; description: string;
  createdAt: string; updatedAt?: string; unread: boolean; lastMessage?: SupportLastMessage | null;
}
export interface SupportMessage { id: string; body: string; senderRole: string; createdAt: string }
export class RelayError extends Error {
  constructor(public status: number, message: string, public retryAfterSeconds?: number, public errorCode?: string) {
    super(message.slice(0, 500));
    this.name = "RelayError";
  }
}

const categories = ["BUG", "FEATURE_REQUEST", "QUESTION"];
const stages = ["opnemen", "transcriberen", "notule", "crash"];
const statuses = ["NEW", "IN_PROGRESS", "WAITING_FOR_USER", "RESOLVED", "CLOSED"];
const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === "object" && !Array.isArray(value);
function text(value: unknown, max: number, min = 0): value is string {
  if (typeof value !== "string") return false;
  const length = Array.from(value).length;
  return length >= min && length <= max;
}
const count = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const ticketIdValid = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(value);
const date = (value: unknown): value is string => typeof value === "string" && Number.isFinite(Date.parse(value));

function requireInput(valid: boolean): void {
  if (!valid) throw new RelayError(422, "Ongeldig supportverzoek.");
}
function installationValid(inst: Installation): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(inst.id)
    && /^[A-Za-z0-9_-]{43}$/.test(inst.secret);
}
function invalidResponse(): never { throw new RelayError(502, "Ongeldig antwoord van de supportserver."); }
function parse(body: string): unknown {
  try { return JSON.parse(body); } catch { return invalidResponse(); }
}
function retryAfter(headers: Record<string, string> | undefined): number | undefined {
  const value = Object.entries(headers ?? {}).find(([key]) => key.toLowerCase() === "retry-after")?.[1];
  return value !== undefined && /^\d+$/.test(value) && Number.isSafeInteger(Number(value)) ? Number(value) : undefined;
}

async function call(method: "GET" | "POST", path: string, inst: Installation | null, body?: unknown): Promise<{ status: number; data: unknown }> {
  if (inst) requireInput(installationValid(inst));
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (inst) { headers["X-TV-Installation"] = inst.id; headers["X-TV-Secret"] = inst.secret; }
  let response: { status: number; body: string; headers?: Record<string, string> };
  try {
    response = await invoke("proxy_request", { request: {
      url: `${SUPPORT_BASE_URL}${path}`, method, headers,
      body: body === undefined ? null : JSON.stringify(body), timeout_seconds: 60,
    } });
  } catch {
    // Native errors can contain credentials or request URLs.
    throw new RelayError(0, "Kan de supportserver niet bereiken.");
  }
  if (response.status < 200 || response.status >= 300) {
    let detail: unknown;
    try { const data: unknown = JSON.parse(response.body); detail = object(data) ? data.detail : undefined; } catch { /* Never expose raw responses. */ }
    throw new RelayError(response.status,
      object(detail) && typeof detail.message === "string" ? detail.message : `Supportverzoek mislukt (HTTP ${response.status}).`,
      retryAfter(response.headers), object(detail) && text(detail.error_code, 100) ? detail.error_code : undefined);
  }
  // An accepted report must not be posted again when only its receipt is broken.
  if (path === "/reports") {
    try { return { status: response.status, data: JSON.parse(response.body) }; }
    catch { return { status: response.status, data: null }; }
  }
  return { status: response.status, data: parse(response.body) };
}

export async function registerInstallation(id: string, secret: string): Promise<"created" | "exists" | "conflict"> {
  requireInput(installationValid({ id, secret }));
  try {
    const { status } = await call("POST", "/installations", null, { installationId: id, secret });
    if (status !== 200 && status !== 201) return invalidResponse();
    return status === 201 ? "created" : "exists";
  } catch (error) {
    if (error instanceof RelayError && error.status === 409) return "conflict";
    throw error;
  }
}

export async function sendReport(inst: Installation, payload: ReportPayload): Promise<ReportResult | null> {
  requireInput(["auto", "manual"].includes(payload.kind) && categories.includes(payload.category) && payload.platform === "windows"
    && (payload.kind === "auto"
      ? payload.category === "BUG" && stages.includes(payload.stage) && typeof payload.fingerprint === "string" && /^[a-f0-9]{16,64}$/.test(payload.fingerprint)
      : payload.stage === "" && payload.fingerprint === undefined)
    && text(payload.shownMessage, 5000, 1) && text(payload.errorText, 2000)
    && Array.isArray(payload.clickPath) && payload.clickPath.length <= 30 && payload.clickPath.every(item => text(item, 80))
    && [payload.appVersion, payload.os, payload.device].every(item => text(item, 100))
    && text(payload.name, 200) && text(payload.email, 320) && text(payload.occurredAt, 40) && date(payload.occurredAt)
    && typeof payload.log === "string" && new TextEncoder().encode(payload.log).length <= 1_000_000);
  const { data } = await call("POST", "/reports", inst, payload);
  if (!object(data) || !ticketIdValid(data.ticketId) || !text(data.ref, 100, 1) || typeof data.repeated !== "boolean"
    || !count(data.count) || data.count < 1 || typeof data.logAttached !== "boolean") return null;
  return data as unknown as ReportResult;
}

function isTicket(value: unknown): value is SupportTicket {
  return object(value) && ticketIdValid(value.id) && text(value.ref, 100, 1) && typeof value.status === "string" && statuses.includes(value.status)
    && typeof value.category === "string" && categories.includes(value.category) && typeof value.description === "string"
    && date(value.createdAt) && typeof value.unread === "boolean"
    && (value.updatedAt === undefined || date(value.updatedAt))
    && (value.lastMessage == null || (object(value.lastMessage) && typeof value.lastMessage.senderRole === "string"
      && date(value.lastMessage.createdAt) && typeof value.lastMessage.excerpt === "string"));
}
function isMessage(value: unknown): value is SupportMessage {
  return object(value) && typeof value.id === "string" && typeof value.body === "string" && typeof value.senderRole === "string" && date(value.createdAt);
}
export async function listTickets(inst: Installation): Promise<SupportTicket[]> {
  const { data } = await call("GET", "/tickets", inst);
  if (!object(data) || !Array.isArray(data.data) || !data.data.every(isTicket)) return invalidResponse();
  return data.data;
}
export async function unreadCount(inst: Installation): Promise<number> {
  const { data } = await call("GET", "/unread-count", inst);
  if (!object(data) || !object(data.data) || !count(data.data.count)) return invalidResponse();
  return data.data.count;
}
export async function ticketMessages(inst: Installation, ticketId: string): Promise<SupportMessage[]> {
  requireInput(ticketIdValid(ticketId));
  const { data } = await call("GET", `/tickets/${ticketId}/messages`, inst);
  if (!object(data) || !Array.isArray(data.data) || !data.data.every(isMessage)) return invalidResponse();
  return data.data;
}
export async function postMessage(inst: Installation, ticketId: string, body: string): Promise<SupportMessage> {
  requireInput(ticketIdValid(ticketId) && text(body, 5000, 1));
  const { data } = await call("POST", `/tickets/${ticketId}/messages`, inst, { body });
  if (!isMessage(data)) return invalidResponse();
  return data;
}
