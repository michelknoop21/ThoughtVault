import { describe, expect, it } from "vitest";
import { OPENROUTER_API_URL, capNotice, isModelAllowed, modelChoices, modelProvider, priceOf, pricePerToken, rememberReportedPrices, suggestedModels, usableModel } from "../suggestedModels";

/** Ids from the routed provider's public model list (November 2026), kept here so the test needs no network. */
const ROUTED_LIST_FIXTURE = new Set([
  "mistralai/mistral-large-4-0", "anthropic/claude-sonnet-5.5", "anthropic/claude-haiku-5.5",
  "anthropic/claude-opus-5.5", "anthropic/claude-fable-5.2", "openai/gpt-5.6-terra", "openai/gpt-6.1-terra",
  "openai/gpt-5.6-luna", "openai/gpt-5.6-sol",
]);

describe("suggested models and price cap", () => {
  it("keeps every suggestion of a metered provider within the cap", () => {
    for (const provider of ["openai", "anthropic", "openrouter"] as const) {
      expect(suggestedModels(provider).length).toBeGreaterThan(0);
      for (const model of suggestedModels(provider)) expect(isModelAllowed(model, provider)).toBe(true);
    }
  });

  it("blocks expensive and unknown models for metered providers", () => {
    expect(isModelAllowed("claude-opus-5-5", "anthropic")).toBe(false);
    expect(isModelAllowed("gpt-5.6-sol", "openai")).toBe(false);
    expect(isModelAllowed("unknown-model", "openai")).toBe(false);
    expect(isModelAllowed("claude-sonnet-4-6", "anthropic")).toBe(true); // exactly on the cap
  });

  it("does not cap local or flat-rate providers", () => {
    expect(isModelAllowed("anything", "ollama")).toBe(true);
    expect(isModelAllowed("anything", "ollama-cloud")).toBe(true);
    expect(isModelAllowed("anything", "lm-studio")).toBe(true);
  });

  it("drops a current model above the cap from the choices", () => {
    expect(modelChoices("anthropic", "claude-opus-5-5", ["claude-haiku-4-5"]))
      .toEqual(["claude-sonnet-5-5", "claude-haiku-5-5", "claude-haiku-4-5"]);
  });

  it("converts reported per-token prices and applies the cap", () => {
    const cheap = pricePerToken({ prompt: "0.000002", completion: "0.00001" });
    expect(cheap?.input).toBeCloseTo(2);
    expect(cheap?.output).toBeCloseTo(10);
    expect(isModelAllowed("x/new", "openai", cheap)).toBe(true);
    expect(isModelAllowed("x/big", "openai", pricePerToken({ prompt: "0.000005", completion: "0.000025" }))).toBe(false);
    expect(pricePerToken({ prompt: "-1", completion: "-1" })).toBeUndefined();
    expect(pricePerToken({ completion: "0.1" })).toBeUndefined();
  });

  it("suggests only routed ids that exist in the provider list", () => {
    for (const model of suggestedModels("openrouter")) {
      expect(model).toMatch(/^[a-z0-9-]+\/[a-z0-9.:-]+$/);
      expect(ROUTED_LIST_FIXTURE.has(model)).toBe(true);
    }
  });

  it("gives dotted and dashed versions the same price", () => {
    expect(priceOf("anthropic/claude-sonnet-5.5")).toEqual(priceOf("claude-sonnet-5-5"));
    expect(isModelAllowed("anthropic/claude-opus-5.5", "openrouter")).toBe(false);
    expect(isModelAllowed("openai/gpt-5.6-sol", "openrouter")).toBe(false);
    expect(isModelAllowed("openai/gpt-5.6-luna", "openrouter")).toBe(true);
  });

  it("caps routed model ids by their last part", () => {
    expect(isModelAllowed("anthropic/claude-opus-5.5", "openrouter")).toBe(false);
    expect(modelChoices("openrouter", "mistralai/mistral-large-4-0")[0]).toBe("mistralai/mistral-large-4-0");
  });

  it("treats Ollama on ollama.com as the flat-rate cloud", () => {
    expect(modelProvider({ notulen_provider: "ollama", ollama_url: "https://ollama.com" })).toBe("ollama-cloud");
    expect(modelProvider({ notulen_provider: "ollama", ollama_url: "http://localhost:11434" })).toBe("ollama");
  });

  it("replaces a model above the cap with the first suggestion and says so", () => {
    expect(usableModel("anthropic/claude-opus-5", "openrouter")).toBe("mistralai/mistral-large-4-0");
    expect(capNotice("anthropic/claude-opus-5", "openrouter")).toBe("anthropic/claude-opus-5 valt boven de prijsgrens, daarom is mistralai/mistral-large-4-0 gebruikt.");
    expect(usableModel("gpt-oss:120b", "ollama-cloud")).toBe("gpt-oss:120b");
    expect(capNotice("openai/gpt-5.6-luna", "openrouter")).toBeUndefined();
  });
});


it("uses a higher fresh endpoint price and ignores expired reports", async () => {
  const { rememberReportedPrices, modelRefusal } = await import("../suggestedModels");
  const rows = [{ id: "gpt-5.6-terra", pricing: { prompt: "0.000004", completion: "0.000020" } }];
  rememberReportedPrices("https://prices.example/v1", rows);
  expect(modelRefusal("gpt-5.6-terra", "https://prices.example")).toContain("prijsgrens");
  expect(modelRefusal("gpt-5.6-terra", "https://other.example")).toBeUndefined();
  rememberReportedPrices("https://prices.example", rows, Date.now() - 8 * 86400_000);
  expect(modelRefusal("gpt-5.6-terra", "https://prices.example")).toBeUndefined();
});

it("shows the models an OpenRouter key may use and keeps them at request time", () => {
  const allowed = ["anthropic/claude-haiku-5.5", "anthropic/claude-sonnet-5.5", "mistralai/mistral-large-4-0", "mistralai/mistral-medium-3-5",
    "mistralai/mistral-small-2603", "openai/gpt-6-luna", "openai/gpt-6-sol", "openai/gpt-6.1-sol", "openai/gpt-6.1-terra"];
  const choices = modelChoices("openrouter", "", allowed);
  expect([...choices].sort()).toEqual([...allowed].sort());
  expect(choices.slice(0, 3)).toEqual(["mistralai/mistral-large-4-0", "anthropic/claude-sonnet-5.5", "openai/gpt-6.1-terra"]);
  // A suggestion the key may not use is left out once the list is loaded.
  expect(modelChoices("openrouter", "", ["mistralai/mistral-small-2603"])).toEqual(["mistralai/mistral-small-2603"]);
  for (const model of allowed) expect(usableModel(model, "openrouter")).toBe(model);
  // A model only priced by the list is allowed through the remembered price.
  rememberReportedPrices(OPENROUTER_API_URL, [{ id: "vendor/new-model", pricing: { prompt: "0.000001", completion: "0.000002" } }]);
  expect(usableModel("vendor/new-model", "openrouter")).toBe("vendor/new-model");
  rememberReportedPrices(OPENROUTER_API_URL, [{ id: "vendor/new-model", pricing: { prompt: "0.00001", completion: "0.00005" } }]);
  expect(usableModel("vendor/new-model", "openrouter")).toBe("mistralai/mistral-large-4-0");
});
