import { describe, expect, it } from "vitest";
import { isModelAllowed, modelChoices, modelProvider, pricePerToken, suggestedModels } from "../suggestedModels";

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

  it("caps routed model ids by their last part", () => {
    expect(isModelAllowed("anthropic/claude-opus-5-5", "openrouter")).toBe(false);
    expect(modelChoices("openrouter", "mistralai/mistral-large-4-0")[0]).toBe("mistralai/mistral-large-4-0");
  });

  it("treats Ollama on ollama.com as the flat-rate cloud", () => {
    expect(modelProvider({ notulen_provider: "ollama", ollama_url: "https://ollama.com" })).toBe("ollama-cloud");
    expect(modelProvider({ notulen_provider: "ollama", ollama_url: "http://localhost:11434" })).toBe("ollama");
  });
});
