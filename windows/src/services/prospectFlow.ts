import { invoke } from "@tauri-apps/api/core";
import { useSettingsStore } from "../stores/settingsStore";
import { loadCredential } from "./tauriCommands";

export const PROSPECTFLOW_KEY = "prospectflow_api_key";

export interface Candidate { id: number; naam: string; plaats?: string; treffers?: number }
export interface Customer { id: number; name: string; city?: string }
export interface OfferResult {
  offer_id: number; number: string; url: string;
  klant: { id: number; naam: string; nieuw: boolean };
  regels: number; te_controleren: number; bestaand: boolean; model: string; terugval_gebruikt: boolean;
}
/** Saved per notule; `pendingRequestId` lives from before the POST until success. */
export interface OfferRef { id?: number; number?: string; url?: string; pendingRequestId?: string; pendingCustomer?: string }

const refKey = (taskId: string) => `prospectFlowOffer-${taskId}`;

export function loadOfferRef(taskId: string): OfferRef | null {
  try { return JSON.parse(localStorage.getItem(refKey(taskId)) ?? "null"); } catch { return null; }
}
function saveOfferRef(taskId: string, ref: OfferRef): void {
  try { localStorage.setItem(refKey(taskId), JSON.stringify(ref)); } catch { /* storage unavailable */ }
}

function baseUrl(): string {
  return useSettingsStore.getState().prospectflow_base_url.trim().replace(/\/+$/, "");
}

/** True when both the base URL and the API key are set. */
export async function isConfigured(): Promise<boolean> {
  if (!baseUrl()) return false;
  try { return Boolean(await loadCredential(PROSPECTFLOW_KEY)); } catch { return false; }
}

const STATUS_TEXT: Record<number, string> = {
  401: "API-sleutel geweigerd door Prospect Flow.",
  403: "AI-hulpen staan uit in Prospect Flow.",
  404: "Klant niet gevonden in Prospect Flow.",
  413: "Het transcript is te lang voor Prospect Flow.",
  429: "Prospect Flow is druk. Probeer het zo opnieuw.",
  502: "Prospect Flow kon het AI-antwoord niet lezen.",
  503: "Het AI-model van Prospect Flow is niet bereikbaar.",
};

async function request<T>(path: string, method: "GET" | "POST", body?: unknown, timeout = 30): Promise<T> {
  const base = baseUrl();
  if (!base) throw new Error("Vul eerst de Prospect Flow-URL in bij Instellingen.");
  const key = await loadCredential(PROSPECTFLOW_KEY);
  if (!key) throw new Error("Vul eerst de Prospect Flow API-sleutel in bij Instellingen.");
  let res: { status: number; body: string };
  try {
    res = await invoke("proxy_request", { request: {
      url: base + path, method, timeout_seconds: timeout,
      headers: { "X-API-Key": key, ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    } });
  } catch {
    throw new Error(`Prospect Flow is niet bereikbaar op ${base}.`);
  }
  let data: unknown = null;
  try { data = JSON.parse(res.body); } catch { /* non-JSON body */ }
  if (res.status >= 400) {
    const detail = (data as { detail?: unknown } | null)?.detail;
    throw new Error(typeof detail === "string" && detail ? detail : STATUS_TEXT[res.status] ?? `Prospect Flow gaf HTTP ${res.status}.`);
  }
  return data as T;
}

/** Cheap authenticated call; throws a Dutch message when URL, key or permissions are wrong. */
export async function testConnection(): Promise<void> {
  await request("/api/customers?search=", "GET");
}

export async function match(text: string): Promise<Candidate[]> {
  const res = await request<{ kandidaten?: Candidate[] }>("/api/ai/offers/from-conversation/match", "POST", { text }, 60);
  return res.kandidaten ?? [];
}

type RawCustomer = { id: number; company_name?: string; contact_name?: string; city?: string };

export async function searchCustomers(query: string): Promise<Customer[]> {
  const res = await request<RawCustomer[] | { items?: RawCustomer[]; customers?: RawCustomer[] }>(
    `/api/customers?search=${encodeURIComponent(query)}`, "GET");
  const list = Array.isArray(res) ? res : res.items ?? res.customers ?? [];
  return list.map((c) => ({ id: c.id, name: c.company_name || c.contact_name || `Klant ${c.id}`, city: c.city }));
}

export interface CreateOfferInput {
  taskId: string; title: string; recordedAt: string; notuleHtml: string; transcript: string;
  customerId?: number; newCustomerName?: string;
}

export async function createOffer(input: CreateOfferInput): Promise<OfferResult> {
  if ((input.customerId === undefined) === (input.newCustomerName === undefined)) {
    throw new Error("Kies een bestaande klant of geef een nieuwe klantnaam op.");
  }
  const stored = loadOfferRef(input.taskId) ?? {};
  // Same customer choice keeps its pending id (a retry after a timeout cannot make a second
  // offer); another choice is a new request.
  const choice = input.customerId !== undefined ? `id:${input.customerId}` : `new:${input.newCustomerName!.toLowerCase()}`;
  const requestId = stored.pendingCustomer === choice && stored.pendingRequestId ? stored.pendingRequestId : crypto.randomUUID();
  saveOfferRef(input.taskId, { ...stored, pendingRequestId: requestId, pendingCustomer: choice });
  const result = await request<OfferResult>("/api/ai/offers/from-conversation", "POST", {
    request_id: requestId, transcript_id: input.taskId, title: input.title, recorded_at: input.recordedAt,
    notule_html: input.notuleHtml, transcript: input.transcript,
    ...(input.customerId !== undefined ? { customer_id: input.customerId } : { new_customer_name: input.newCustomerName }),
  }, 300);
  saveOfferRef(input.taskId, { id: result.offer_id, number: result.number, url: result.url });
  return result;
}

export async function openOffer(url: string): Promise<void> {
  const { open } = await import("@tauri-apps/plugin-shell");
  await open(baseUrl() + url);
}
