import { invoke } from "@tauri-apps/api/core";
import { loadCredential } from "./tauriCommands";

export const OLLAMA_LOCAL_URL = "http://localhost:11434";
export const OLLAMA_CLOUD_URL = "https://ollama.com";

export function isOllamaCloudURL(baseURL: string): boolean {
  try { return new URL(baseURL).origin === OLLAMA_CLOUD_URL; } catch { return false; }
}

export async function fetchOllamaModels(baseURL: string): Promise<string[]> {
  const url = new URL(baseURL);
  if (!["http:", "https:"].includes(url.protocol)) throw new Error("Vul een HTTP- of HTTPS-adres in.");
  const base = baseURL.trim().replace(/\/+$/, "").replace(/\/v1$/, "");
  const key = url.protocol === "https:" ? await loadCredential("ollama_api_key") : null;
  for (const path of ["/v1/models", "/api/tags"]) {
    try {
      const response = await invoke<{ status: number; body: string }>("proxy_request", {
        request: { url: `${base}${path}`, method: "GET", headers: key ? { Authorization: `Bearer ${key}` } : {}, body: null, timeout_seconds: 10 },
      });
      if (response.status !== 200) continue;
      const body = JSON.parse(response.body);
      const rows: unknown[] = path === "/v1/models" ? body.data : body.models;
      if (!Array.isArray(rows)) continue;
      const names = rows.map(row => typeof row === "object" && row !== null ? (row as Record<string, unknown>)[path === "/v1/models" ? "id" : "name"] : null)
        .filter((name): name is string => typeof name === "string" && name.trim().length > 0);
      if (names.length) return [...new Set(names)].sort();
    } catch { /* The native Ollama list is the fallback for older servers. */ }
  }
  throw new Error("Geen modellen opgehaald. Controleer het adres, de server en voor cloud je API-sleutel.");
}
