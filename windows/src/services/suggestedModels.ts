import type { AppSettings, NotulenProvider } from "../types";
import { isOllamaCloudURL } from "./ollamaModels";

/** List price in USD per million tokens. */
export interface ModelPrice { input: number; output: number }

/** Mid-tier ceiling: USD 3 per million input tokens and USD 15 per million output tokens. */
export const PRICE_CAP: ModelPrice = { input: 3, output: 15 };

/** List prices of the hosted models the app knows (list prices checked November 2026). */
export const KNOWN_PRICES: Record<string, ModelPrice> = {
  "claude-haiku-5-5": { input: 0.1, output: 0.5 },
  "claude-haiku-4-5": { input: 1, output: 5 },
  "claude-sonnet-5-5": { input: 2, output: 10 },
  "claude-sonnet-5": { input: 2, output: 10 },
  "claude-sonnet-4-6": { input: 3, output: 15 },
  "claude-opus-5-5": { input: 4, output: 20 },
  "claude-opus-5": { input: 5, output: 25 },
  "claude-opus-4-8": { input: 5, output: 25 },
  "claude-fable-5-2": { input: 8, output: 40 },
  "claude-fable-5-1": { input: 10, output: 50 },
  "gpt-5.6-luna": { input: 0.2, output: 1.2 },
  "gpt-5.6-terra": { input: 2, output: 12 },
  "gpt-5.6-sol": { input: 4, output: 20 },
  "mistral-large-4-0": { input: 0.7, output: 2.1 },
};

/** Provider as the model choice sees it: the hosted flat-rate endpoint counts as its own provider. */
export type ModelProvider = Exclude<NotulenProvider, "cloud"> | "ollama-cloud";

export function modelProvider(settings: Pick<AppSettings, "notulen_provider" | "ollama_url">): ModelProvider {
  if (settings.notulen_provider === "ollama" && isOllamaCloudURL(settings.ollama_url)) return "ollama-cloud";
  return settings.notulen_provider === "cloud" ? "ollama" : settings.notulen_provider;
}

const SUGGESTED: Partial<Record<ModelProvider, string[]>> = {
  openrouter: ["mistralai/mistral-large-4-0", "anthropic/claude-sonnet-5.5", "openai/gpt-5.6-terra"],
  anthropic: ["claude-sonnet-5-5", "claude-haiku-5-5"],
  openai: ["gpt-5.6-terra", "gpt-5.6-luna"],
  "ollama-cloud": ["mistral-large-4", "gpt-oss:120b"],
};

export function suggestedModels(provider: ModelProvider): string[] {
  return SUGGESTED[provider] ?? [];
}

/** Providers that bill every token to the user's own API key. */
export function isMetered(provider: ModelProvider): boolean {
  return provider === "openai" || provider === "anthropic" || provider === "openrouter";
}

/**
 * Known price; a routed id such as `vendor/model` falls back to its last part, and a version
 * written with a dot (`x-5.5`) also matches the dashed spelling (`x-5-5`).
 */
export function priceOf(model: string): ModelPrice | undefined {
  const last = model.split("/").pop() ?? model;
  return [model, last, last.replace(/\./g, "-")].map(id => KNOWN_PRICES[id]).find(Boolean);
}

export function isWithinCap(price: ModelPrice): boolean {
  return price.input <= PRICE_CAP.input && price.output <= PRICE_CAP.output;
}

/** Metered providers only allow a model with a known price within the cap; local and flat-rate ones are free. */
export function isModelAllowed(model: string, provider: ModelProvider, reportedPrice?: ModelPrice): boolean {
  if (!isMetered(provider)) return true;
  const price = reportedPrice ?? priceOf(model);
  return !!price && isWithinCap(price);
}

/**
 * The model a notule request uses: a model a metered provider does not allow (above the cap or
 * without a known price) becomes the provider's first suggestion.
 */
export function usableModel(model: string, provider: ModelProvider): string {
  return isModelAllowed(model, provider) ? model : suggestedModels(provider)[0] ?? model;
}

/** Short notice for the task details when usableModel replaced `model`. */
export function capNotice(model: string, provider: ModelProvider): string | undefined {
  const used = usableModel(model, provider);
  return used === model ? undefined : `${model} valt boven de prijsgrens, daarom is ${used} gebruikt.`;
}

/** Picker choices: suggestions first, then the current and listed models that pass the cap. */
export function modelChoices(provider: ModelProvider, current: string, available: string[] = []): string[] {
  return [...new Set([...suggestedModels(provider), current, ...available])]
    .filter(model => model && isModelAllowed(model, provider));
}

/**
 * A models endpoint that reports `pricing.prompt` / `pricing.completion` gives USD per token as
 * strings; negative values mean variable pricing and count as unknown.
 */
export function pricePerToken(pricing?: { prompt?: string; completion?: string }): ModelPrice | undefined {
  const input = Number(pricing?.prompt), output = Number(pricing?.completion);
  if (pricing?.prompt == null || pricing?.completion == null || !Number.isFinite(input) || !Number.isFinite(output) || input < 0 || output < 0) return undefined;
  return { input: input * 1_000_000, output: output * 1_000_000 };
}

/** "<model> · $2 / $10 per mln tokens" for models with a known price. */
export function modelLabel(model: string): string {
  const price = priceOf(model);
  return price ? `${model} · $${price.input.toLocaleString("nl-NL")} / $${price.output.toLocaleString("nl-NL")} per mln tokens` : model;
}

type ModelSettingKey = "openai_model" | "anthropic_model" | "openrouter_model" | "ollama_model" | "lm_studio_model";

/** Settings field that holds the model of `provider`. */
export function modelSettingKey(provider: ModelProvider): ModelSettingKey {
  switch (provider) {
    case "openai": return "openai_model";
    case "anthropic": return "anthropic_model";
    case "openrouter": return "openrouter_model";
    case "lm-studio": return "lm_studio_model";
    default: return "ollama_model";
  }
}
