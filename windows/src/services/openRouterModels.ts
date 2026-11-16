import { invoke } from "@tauri-apps/api/core";

/** the provider's public model list; no key needed. Same source as the routed providerModels.swift on macOS. */
export const OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models";
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
  for (const entry of (JSON.parse(body).data ?? []) as ListEntry[]) {
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
