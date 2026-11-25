import { beforeEach, expect, it, vi } from "vitest";
import { OPENROUTER_KEY_MODELS_URL, OPENROUTER_MODELS_URL, REASONING_OUTPUT_TOKENS, openRouterKeyModels, openRouterModel, openRouterRequestFields, parseModelList, resetOpenRouterModels } from "../openRouterModels";
import { modelListFixture } from "./openRouterModelsFixture";

const { invoke, loadCredential } = vi.hoisted(() => ({ invoke: vi.fn(), loadCredential: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential }));

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


it("keeps the catalog price for the request cap", async () => {
  const { modelRefusal } = await import("../suggestedModels");
  parseModelList(JSON.stringify({ data: [{ id: "openai/gpt-5.6-terra", pricing: { prompt: "0.000004", completion: "0.000020" } }] }));
  expect(modelRefusal("openai/gpt-5.6-terra", "https://openrouter.ai/api/v1")).toContain("prijsgrens");
});

it("lists only the models the stored key may use", async () => {
  loadCredential.mockResolvedValue("fixture-key");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ data: [
    { id: "openai/gpt-6.1-terra", pricing: { prompt: "0.000001", completion: "0.000005" } },
    { id: "mistralai/mistral-small-2603", pricing: { prompt: "0.00000015", completion: "0.0000006" } },
  ] }) });
  expect(await openRouterKeyModels()).toEqual(["openai/gpt-6.1-terra", "mistralai/mistral-small-2603"]);
  expect(invoke).toHaveBeenCalledWith("proxy_request", { request: expect.objectContaining({
    url: OPENROUTER_KEY_MODELS_URL, method: "GET", headers: { Authorization: "Bearer fixture-key" } }) });
  invoke.mockResolvedValue({ status: 403, body: "{}" });
  expect(await openRouterKeyModels()).toEqual([]);
  loadCredential.mockResolvedValue(null);
  invoke.mockClear();
  expect(await openRouterKeyModels()).toEqual([]);
  expect(invoke).not.toHaveBeenCalled();
  loadCredential.mockRejectedValue(new Error("no store"));
  expect(await openRouterKeyModels()).toEqual([]);
});

it("lists the transcription models the stored key may use", async () => {
  loadCredential.mockResolvedValue("fixture-key");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ data: [
    { id: "mistralai/voxtral-small-transcribe-3-0", architecture: { output_modalities: ["transcription"] } },
    { id: "openai/gpt-6.1-terra", architecture: { output_modalities: ["text"] } },
    { id: "deepgram/nova-3" },
  ] }) });
  expect(await openRouterKeyModels("transcription")).toEqual(["mistralai/voxtral-small-transcribe-3-0", "deepgram/nova-3"]);
  expect(invoke).toHaveBeenCalledWith("proxy_request", { request: expect.objectContaining({
    url: `${OPENROUTER_KEY_MODELS_URL}?output_modalities=transcription`, headers: { Authorization: "Bearer fixture-key" } }) });
});
