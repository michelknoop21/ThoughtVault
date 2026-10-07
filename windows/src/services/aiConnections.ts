import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-shell";
import { create } from "zustand";
import { loadCredential, storeCredential, deleteCredential } from "./tauriCommands";

const BASE = "https://n8n.prezent.nl/tstudio/api";
const KEY = "mcp_device";
export type AIScope = "read" | "write" | "record";
export interface DeviceConnection { device_id: string; credential: string; scopes: AIScope[]; user_id: string; }
export interface AICommand {
  id: string; device_id: string; scope: AIScope; expires_at: number;
  tool: string; arguments: Record<string, unknown>;
}
export const useAIConnection = create<{
  connection: DeviceConnection | null; status: string; busy: boolean;
}>(() => ({ connection: null, status: "Niet gekoppeld", busy: false }));

export async function relayRequest<T>(path: string, method = "GET", body?: unknown, credential?: string): Promise<T> {
  const response = await invoke<{ status: number; body: string }>("proxy_request", { request: {
    url: BASE + path, method, headers: { "Content-Type": "application/json", ...(credential ? { Authorization: `Bearer ${credential}` } : {}) },
    body: body === undefined ? null : JSON.stringify(body),
  } });
  const data = JSON.parse(response.body);
  if (response.status < 200 || response.status >= 300) throw Error(data.detail ?? "AI-koppeling niet bereikbaar. Probeer opnieuw.");
  return data;
}

export async function loadAIConnection() {
  const raw = await loadCredential(KEY);
  const connection: DeviceConnection | null = raw ? JSON.parse(raw) : null;
  useAIConnection.setState({ connection, status: connection ? "Verbinding maken…" : "Niet gekoppeld" });
}

let pairingGeneration = 0;
export async function pairAIConnection(scopes: AIScope[]) {
  const generation = ++pairingGeneration;
  useAIConnection.setState({ busy: true, status: "Voltooi de koppeling in je browser" });
  try {
    const pending = await relayRequest<{ ticket: string; secret: string; verification_uri: string }>("/ai/devices/pair", "POST", { name: "ThoughtVault Windows", platform: "Windows", scopes });
    // Browser URL comes from the trusted relay; never open arbitrary command URLs.
    if (!pending.verification_uri.startsWith(BASE + "/ai/devices/verify?")) throw Error("Ongeldige koppel-URL.");
    await open(pending.verification_uri);
    const deadline = Date.now() + 300_000;
    while (generation === pairingGeneration && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      const ready = await relayRequest<DeviceConnection & { pending?: boolean }>("/ai/devices/pair-status", "POST", { ticket: pending.ticket, secret: pending.secret });
      if (!ready.pending) {
        await storeCredential(KEY, JSON.stringify(ready));
        if (await loadCredential(KEY) !== JSON.stringify(ready)) throw Error("Koppelgegevens opslaan mislukt.");
        useAIConnection.setState({ connection: ready, status: "Verbinding maken…" });
        return;
      }
    }
    throw Error("Koppelaanvraag verlopen. Probeer opnieuw.");
  } catch (error) {
    useAIConnection.setState({ status: error instanceof Error ? error.message : String(error) });
  } finally { useAIConnection.setState({ busy: false }); }
}

export async function updateAIPermissions(scopes: AIScope[]) {
  const connection = useAIConnection.getState().connection;
  if (!connection) return;
  useAIConnection.setState({ busy: true });
  try {
    // Narrow local permission checks immediately, before the outgoing request.
    const reduced = connection.scopes.filter((scope) => scopes.includes(scope));
    useAIConnection.setState({ connection: { ...connection, scopes: reduced } });
    await storeCredential(KEY, JSON.stringify({ ...connection, scopes: reduced }));
    await relayRequest(`/ai/devices/${connection.device_id}`, "PUT", { scopes }, connection.credential);
    const updated = { ...connection, scopes };
    await storeCredential(KEY, JSON.stringify(updated));
    useAIConnection.setState({ connection: updated });
  } catch (error) {
    useAIConnection.setState({ status: `Rechten wijzigen niet bevestigd. Probeer opnieuw. ${String(error)}` });
    throw error;
  } finally { useAIConnection.setState({ busy: false }); }
}

export async function disconnectAIConnection() {
  const connection = useAIConnection.getState().connection;
  if (!connection) return;
  useAIConnection.setState({ busy: true, connection: { ...connection, scopes: [] } });
  try {
    await storeCredential(KEY, JSON.stringify({ ...connection, scopes: [] }));
    await relayRequest(`/ai/devices/${connection.device_id}`, "DELETE", undefined, connection.credential);
    await deleteCredential(KEY);
    useAIConnection.setState({ connection: null, status: "Niet gekoppeld" });
  } catch (error) {
    useAIConnection.setState({ status: `Ontkoppelen niet bevestigd. Probeer opnieuw. ${String(error)}` });
  } finally { useAIConnection.setState({ busy: false }); }
}

export function commandAllowed(command: AICommand, connection: DeviceConnection): boolean {
  const scope: AIScope = ["start_recording", "pause_recording", "resume_recording", "stop_recording"].includes(command.tool)
    ? "record" : ["save_minutes", "update_transcript", "save_profile", "open_view"].includes(command.tool) ? "write" : "read";
  return command.device_id === connection.device_id && command.expires_at * 1000 > Date.now() &&
    command.scope === scope && connection.scopes.includes(scope);
}
