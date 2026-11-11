import { invoke } from "@tauri-apps/api/core";
import { useSettingsStore } from "../stores/settingsStore";
import { loadCredential } from "./tauriCommands";

export const PROSPECTFLOW_KEY = "prospectflow_api_key";

export interface Candidate { id: number; naam: string; plaats?: string; treffers?: number }
export interface Customer { id: number; name: string; city?: string }
export interface OfferResult {
  offer_id: number; number: string; url: string;
  klant: { id: number | null; naam: string; nieuw: boolean };
  regels: number; te_controleren: number; bestaand: boolean; model?: string | null; terugval_gebruikt: boolean;
  /** Added by this client, so opening the result stays on the request instance. */
  instanceBaseUrl?: string;
}
/** Saved per notule; `pendingRequestId` lives from before the POST until success. */
export interface OfferRef { id?: number; number?: string; url?: string; pendingRequestId?: string; pendingCustomer?: string; pendingNewCustomerName?: string }

const refKey = (taskId: string, instance: string) => `prospectFlowOffer-${JSON.stringify([instance, taskId])}`;

export function loadOfferRef(taskId: string, instance?: string): OfferRef | null {
  try {
    const base = instance ?? baseUrl();
    const stored = localStorage.getItem(refKey(taskId, base));
    // Unscoped references were created by the first, Yinga-only version.
    const legacy = base === "https://prospectflow.yinga.ai" ? localStorage.getItem(`prospectFlowOffer-${taskId}`) : null;
    return JSON.parse(stored ?? legacy ?? "null");
  } catch { return null; }
}
function saveOfferRef(taskId: string, ref: OfferRef, instance: string): void {
  try { localStorage.setItem(refKey(taskId, instance), JSON.stringify(ref)); }
  catch { throw new Error("De offertelink kan niet worden bewaard. Controleer de lokale opslag en probeer opnieuw."); }
}

function baseUrl(value = useSettingsStore.getState().prospectflow_base_url): string {
  const base = value.trim().replace(/\/+$/, "");
  if (!base) return "";
  let url: URL;
  try { url = new URL(base); }
  catch { throw new Error("Vul een geldig Prospect Flow-adres in."); }
  if (url.username || url.password) throw new Error("Gebruik een Prospect Flow-adres zonder gebruikersgegevens.");
  if (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname))) {
    throw new Error("Gebruik een HTTPS-adres voor Prospect Flow. HTTP is alleen toegestaan op deze computer.");
  }
  return base;
}

function offerUrl(path: string, instance: string): string {
  const base = baseUrl(instance);
  if (!path.startsWith("/") || path.startsWith("//")) throw new Error("Prospect Flow gaf een ongeldige offertelink.");
  const url = new URL(base + path);
  if (url.origin !== new URL(base).origin || url.username || url.password) throw new Error("De offertelink hoort niet bij deze Prospect Flow-instance.");
  return url.href;
}

/** True when both the base URL and the API key are set. */
export async function isConfigured(): Promise<boolean> {
  try { return Boolean(baseUrl() && await loadCredential(PROSPECTFLOW_KEY)); } catch { return false; }
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

class ProspectFlowRequestError extends Error {
  constructor(message: string, readonly missingCustomer: boolean) { super(message); }
}

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
  if (res.status < 200 || res.status >= 300) {
    const detail = (data as { detail?: unknown } | null)?.detail;
    throw new ProspectFlowRequestError(
      typeof detail === "string" && detail ? detail : STATUS_TEXT[res.status] ?? `Prospect Flow gaf HTTP ${res.status}.`,
      res.status === 404 && detail === "Klant niet gevonden",
    );
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
  const instance = baseUrl();
  const stored = loadOfferRef(input.taskId, instance) ?? {};
  // Resolve an uncertain POST before allowing a different customer choice.
  const choice = input.customerId !== undefined ? `id:${input.customerId}` : `new:${input.newCustomerName!.toLowerCase()}`;
  if (stored.pendingRequestId && stored.pendingCustomer !== choice) {
    throw new Error("Er is nog een onbevestigde offerteaanvraag. Heropen dit venster en rond die eerst af voordat je een andere klant kiest.");
  }
  const requestId = stored.pendingCustomer === choice && stored.pendingRequestId ? stored.pendingRequestId : crypto.randomUUID();
  saveOfferRef(input.taskId, { ...stored, pendingRequestId: requestId, pendingCustomer: choice, pendingNewCustomerName: input.newCustomerName }, instance);
  let result: OfferResult;
  try {
    result = await request<OfferResult>("/api/ai/offers/from-conversation", "POST", {
      request_id: requestId, transcript_id: input.taskId, title: input.title, recorded_at: input.recordedAt,
      notule_html: input.notuleHtml, transcript: input.transcript,
      ...(input.customerId !== undefined ? { customer_id: input.customerId } : { new_customer_name: input.newCustomerName }),
    }, 300);
  } catch (error) {
    // The API checks this request ID before returning a missing-customer error.
    if (error instanceof ProspectFlowRequestError && error.missingCustomer) {
      saveOfferRef(input.taskId, { id: stored.id, number: stored.number, url: stored.url }, instance);
    }
    throw error;
  }
  if (!result || typeof result !== "object" || !Number.isSafeInteger(result.offer_id) || result.offer_id <= 0
    || typeof result.number !== "string" || !result.number.trim() || typeof result.url !== "string"
    || !result.klant || typeof result.klant.naam !== "string" || !result.klant.naam.trim()
    || !(result.klant.id === null || (Number.isSafeInteger(result.klant.id) && result.klant.id > 0))
    || typeof result.klant.nieuw !== "boolean" || !Number.isSafeInteger(result.regels) || result.regels < 0
    || !Number.isSafeInteger(result.te_controleren) || result.te_controleren < 0 || typeof result.bestaand !== "boolean"
    || typeof result.terugval_gebruikt !== "boolean" || !(result.model == null || typeof result.model === "string")
    || (result.terugval_gebruikt && !result.model?.trim())) {
    throw new Error("Prospect Flow gaf een onvolledig offerteantwoord. De aanvraag is bewaard; probeer opnieuw.");
  }
  offerUrl(result.url, instance);
  saveOfferRef(input.taskId, { id: result.offer_id, number: result.number, url: result.url }, instance);
  return { ...result, instanceBaseUrl: instance };
}

export async function openOffer(url: string, instance = baseUrl()): Promise<void> {
  const target = offerUrl(url, instance);
  const { open } = await import("@tauri-apps/plugin-shell");
  await open(target);
}
