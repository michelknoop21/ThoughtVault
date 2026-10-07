import { invoke } from "@tauri-apps/api/core";
import { create } from "zustand";
import { loadCredential, storeCredential, deleteCredential } from "./tauriCommands";

const KEY = "local_mcp_connection";
export type AIScope = "read" | "write" | "record";
export interface DeviceConnection { device_id: string; credential: string; scopes: AIScope[]; user_id: string; }
export interface AICommand { id: string; device_id: string; scope: AIScope; expires_at: number; tool: string; arguments: Record<string, unknown>; }
export const useAIConnection = create<{ connection: DeviceConnection | null; status: string; busy: boolean }>(() => ({ connection: null, status: "Lokale MCP uitgeschakeld", busy: false }));
export async function loadAIConnection() {
  const raw = await loadCredential(KEY);
  if (!raw) return;
  const connection: DeviceConnection | null = JSON.parse(raw);
  if (!connection) return;
  await invoke("local_mcp_start", { token: connection.credential, scopes: connection.scopes });
  useAIConnection.setState({ connection, status: "Lokale MCP actief op http://127.0.0.1:11219/mcp" });
}
export async function pairAIConnection(scopes: AIScope[]) {
  useAIConnection.setState({ busy: true });
  try {
    const credential = Array.from(crypto.getRandomValues(new Uint8Array(32)), value => value.toString(16).padStart(2, "0")).join("");
    const connection: DeviceConnection = { device_id: "local", user_id: "local", scopes, credential };
    await storeCredential(KEY, JSON.stringify(connection));
    await invoke("local_mcp_start", { token: credential, scopes });
    useAIConnection.setState({ connection, status: "Lokale MCP actief op http://127.0.0.1:11219/mcp" });
  } catch (error) { useAIConnection.setState({ status: String(error) }); }
  finally { useAIConnection.setState({ busy: false }); }
}
export async function updateAIPermissions(scopes: AIScope[]) {
  const connection = useAIConnection.getState().connection;
  if (!connection) return;
  // Revoke in the UI immediately; native admission is checked before every action.
  useAIConnection.setState({ connection: { ...connection, scopes: [] }, busy: true });
  try {
    await invoke("local_mcp_stop");
    const updated = { ...connection, scopes };
    await storeCredential(KEY, JSON.stringify(updated));
    await invoke("local_mcp_start", { token: connection.credential, scopes });
    useAIConnection.setState({ connection: updated });
  } finally { useAIConnection.setState({ busy: false }); }
}
export async function disconnectAIConnection() {
  useAIConnection.setState({ connection: null, busy: true });
  try { await invoke("local_mcp_stop"); await storeCredential(KEY, "null"); await deleteCredential(KEY); useAIConnection.setState({ status: "Lokale MCP uitgeschakeld" }); }
  finally { useAIConnection.setState({ busy: false }); }
}
export function commandAllowed(command: AICommand, connection: DeviceConnection): boolean {
  const scope: AIScope = ["start_recording", "pause_recording", "resume_recording", "stop_recording"].includes(command.tool)
    ? "record" : ["save_minutes", "update_transcript", "save_profile", "open_view"].includes(command.tool) ? "write" : "read";
  return command.device_id === connection.device_id && command.expires_at * 1000 > Date.now() &&
    command.scope === scope && connection.scopes.includes(scope);
}
