import { invoke } from "@tauri-apps/api/core";
import { OPENROUTER_API_URL, rememberReportedPrices } from "./suggestedModels";
import { loadCredential } from "./tauriCommands";

/** the provider's public model list; no key needed. Same source as the routed providerModels.swift on macOS. */
export const OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models";
/** Only the models the key may use, under the workspace's model access; needs the key. */
export const OPENROUTER_KEY_MODELS_URL = "https://openrouter.ai/api/v1/models/user";
/** Output cap for a model that thinks by default. Thinking and the reply share max_tokens, and the provider's notes
 * for adaptive-thinking models name 64k as the size that worked for long turns; at 32k a 43k-character meeting ended
 * truncated. Only generated tokens are billed, so the higher cap costs only when a model needs it. */
export const REASONING_OUTPUT_TOKENS = 65_536;

/** What the model list says about one model. */
export interface OpenRouterModel {
  /** Thinks when the request names no reasoning: mandatory, default_enabled, or a default effort without a switch. */
  reasonsByDefault: boolean;
  lowEffort: boolean;
  /** top_provider.max_completion_tokens */
  maxCompletionTokens?: number;
}

type ListEntry = {
  id?: string;
  top_provider?: { max_completion_tokens?: number | null };
  reasoning?: { mandatory?: boolean; default_enabled?: boolean; default_effort?: string; supported_efforts?: string[] };
};

export function parseModelList(body: string): Map<string, OpenRouterModel> {
  const models = new Map<string, OpenRouterModel>();
  const entries = JSON.parse(body).data ?? [];
  rememberReportedPrices(OPENROUTER_API_URL, entries);
  for (const entry of entries as ListEntry[]) {
    if (!entry.id) continue;
    const r = entry.reasoning;
    const max = entry.top_provider?.max_completion_tokens;
    models.set(entry.id, {
      reasonsByDefault: !!r && (r.mandatory === true || r.default_enabled === true || (r.default_enabled === undefined && !!r.default_effort)),
      lowEffort: r?.supported_efforts?.includes("low") ?? false,
      ...(typeof max === "number" && max > 0 ? { maxCompletionTokens: max } : {}),
    });
  }
  return models;
}

/** Request fields per model. An effort is only sent to a model that thinks anyway, because for any other model it
 * switches thinking on. A model that only offers high or none keeps its default. Unknown model: the plain cap. */
export function openRouterRequestFields(model: OpenRouterModel | undefined, baseCap: number): { max_tokens: number; reasoning?: { effort: "low" } } {
  const cap = model?.reasonsByDefault ? REASONING_OUTPUT_TOKENS : baseCap;
  const max_tokens = Math.min(cap, model?.maxCompletionTokens ?? cap);
  return model?.reasonsByDefault && model.lowEffort ? { max_tokens, reasoning: { effort: "low" } } : { max_tokens };
}

let catalog: Promise<Map<string, OpenRouterModel>> | null = null;

/** The model's entry, fetched once per app session; undefined when the list is unreachable (retried next call). */
export async function openRouterModel(id: string): Promise<OpenRouterModel | undefined> {
  catalog ??= invoke<{ status: number; body: string }>("proxy_request", { request: { url: OPENROUTER_MODELS_URL, method: "GET", timeout_seconds: 30 } })
    .then(response => {
      if (response.status !== 200) throw new Error(`HTTP ${response.status}`);
      return parseModelList(response.body);
    });
  try {
    return (await catalog).get(id);
  } catch {
    catalog = null;
    return undefined;
  }
}

/** Test seam: forget the fetched list. */
export function resetOpenRouterModels(): void {
  catalog = null;
}

/**
 * Ids of the models the stored key may use; [] without a key or answer. Text models by default, with their
 * prices remembered for the cap; `"transcription"` asks for the transcription models instead (DEC-080).
 */
export async function openRouterKeyModels(output?: "transcription"): Promise<string[]> {
  try {
    const key = await loadCredential("openrouter_api_key");
    if (!key) return [];
    const url = output ? `${OPENROUTER_KEY_MODELS_URL}?output_modalities=${output}` : OPENROUTER_KEY_MODELS_URL;
    const response = await invoke<{ status: number; body: string }>("proxy_request", {
      request: { url, method: "GET", headers: { Authorization: `Bearer ${key}` }, body: null, timeout_seconds: 30 },
    });
    if (response.status !== 200) return [];
    const rows: unknown = JSON.parse(response.body).data;
    if (!Array.isArray(rows)) return [];
    if (!output) rememberReportedPrices(OPENROUTER_API_URL, rows);
    const outputs = (row: unknown) => (row as { architecture?: { output_modalities?: unknown } })?.architecture?.output_modalities;
    return rows.filter(row => { const kinds = outputs(row); return !output || !Array.isArray(kinds) || kinds.includes(output); })
      .map(row => (row as { id?: unknown })?.id).filter((id): id is string => typeof id === "string" && id.length > 0);
  } catch {
    return [];
  }
}
