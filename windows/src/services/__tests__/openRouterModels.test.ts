import { beforeEach, expect, it, vi } from "vitest";
import { OPENROUTER_MODELS_URL, REASONING_OUTPUT_TOKENS, openRouterModel, openRouterRequestFields, parseModelList, resetOpenRouterModels } from "../openRouterModels";
import { modelListFixture } from "./openRouterModelsFixture";

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));

beforeEach(() => {
  invoke.mockReset();
  resetOpenRouterModels();
});

const models = parseModelList(modelListFixture);

it("reads from the public model list whether a model reasons by default and whether it accepts low effort", () => {
  expect(models.get("anthropic/claude-sonnet-5.5")).toEqual({ reasonsByDefault: true, lowEffort: true, maxCompletionTokens: 128000 });
  expect(models.get("mistralai/mistral-large-4-0")).toEqual({ reasonsByDefault: true, lowEffort: false, maxCompletionTokens: 262144 });
  // No default_enabled, but a default effort: thinks at that effort when nothing is sent.
  expect(models.get("anthropic/claude-haiku-5.5")).toEqual({ reasonsByDefault: true, lowEffort: true, maxCompletionTokens: 128000 });
  expect(models.get("anthropic/claude-sonnet-4.5")).toEqual({ reasonsByDefault: false, lowEffort: false, maxCompletionTokens: 64000 });
  expect(models.get("anthropic/claude-opus-4.8")).toEqual({ reasonsByDefault: false, lowEffort: true, maxCompletionTokens: 128000 });
  expect(models.get("deepseek/deepseek-chat")).toEqual({ reasonsByDefault: false, lowEffort: false, maxCompletionTokens: 16000 });
});

it("asks for low effort only from a model that already reasons by default and accepts it", () => {
  expect(openRouterRequestFields(models.get("anthropic/claude-sonnet-5.5"), 32_768).reasoning).toEqual({ effort: "low" });
  expect(openRouterRequestFields(models.get("anthropic/claude-haiku-5.5"), 32_768).reasoning).toEqual({ effort: "low" });
  // Sending an effort would switch thinking on.
  expect(openRouterRequestFields(models.get("anthropic/claude-sonnet-4.5"), 32_768)).not.toHaveProperty("reasoning");
  expect(openRouterRequestFields(models.get("anthropic/claude-opus-4.8"), 32_768)).not.toHaveProperty("reasoning");
  expect(openRouterRequestFields(models.get("deepseek/deepseek-chat"), 32_768)).not.toHaveProperty("reasoning");
  // Only high or none: the provider default is left alone.
  expect(openRouterRequestFields(models.get("mistralai/mistral-large-4-0"), 32_768)).not.toHaveProperty("reasoning");
  // Unknown model or no list: nothing is switched on.
  expect(openRouterRequestFields(undefined, 32_768)).toEqual({ max_tokens: 32_768 });
});

it("leaves room for thinking within the model's published maximum", () => {
  expect(openRouterRequestFields(models.get("anthropic/claude-sonnet-5.5"), 32_768).max_tokens).toBe(REASONING_OUTPUT_TOKENS);
  expect(openRouterRequestFields(models.get("mistralai/mistral-large-4-0"), 32_768).max_tokens).toBe(REASONING_OUTPUT_TOKENS);
  expect(openRouterRequestFields(models.get("anthropic/claude-sonnet-4.5"), 32_768).max_tokens).toBe(32_768);
  expect(openRouterRequestFields(models.get("deepseek/deepseek-chat"), 32_768).max_tokens).toBe(16_000);
  expect(openRouterRequestFields({ reasonsByDefault: true, lowEffort: true, maxCompletionTokens: 40_000 }, 32_768).max_tokens).toBe(40_000);
});

it("fetches the list once without a key, and again after a failure", async () => {
  invoke.mockResolvedValue({ status: 200, body: modelListFixture, headers: {} });
  const [a, b] = await Promise.all([openRouterModel("anthropic/claude-sonnet-5.5"), openRouterModel("deepseek/deepseek-chat")]);
  expect(a?.reasonsByDefault).toBe(true);
  expect(b?.maxCompletionTokens).toBe(16000);
  expect(invoke).toHaveBeenCalledTimes(1);
  const request = invoke.mock.calls[0][1].request;
  expect(request).toEqual({ url: OPENROUTER_MODELS_URL, method: "GET", timeout_seconds: 30 });

  resetOpenRouterModels();
  invoke.mockReset();
  invoke.mockRejectedValueOnce("network down").mockResolvedValueOnce({ status: 200, body: modelListFixture, headers: {} });
  expect(await openRouterModel("anthropic/claude-sonnet-5.5")).toBeUndefined();
  expect(await openRouterModel("anthropic/claude-sonnet-5.5")).toBeDefined();
  expect(invoke).toHaveBeenCalledTimes(2);
});
