import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService } from "../llm";

const { loadCredential } = vi.hoisted(() => ({ loadCredential: vi.fn() }));
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("../tauriCommands", () => ({ loadCredential }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));

const profile = {
  id: "custom",
  name: "Test",
  system_prompt: "Maak nauwkeurige notulen.",
  notule_prompt: "Notuleer: {{TRANSCRIPTION}}\n{{OUTPUT_TEMPLATE}}",
  output_template: "<h1>Titel</h1>",
};

beforeEach(() => {
  vi.resetAllMocks();
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama" });
});

it("uses the user's OpenAI API key for the selected profile and transcript", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" as never });
  loadCredential.mockResolvedValue("openai-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<h1>Besluit</h1>" } }] }) });

  const html = await LLMService.generateNotulen("De planning is goedgekeurd.", profile);

  expect(html).toBe("<h1>Besluit</h1>");
  expect(loadCredential).toHaveBeenCalledWith("openai_api_key");
  const request = invoke.mock.calls[0][1].request;
  expect(request.url).toBe("https://api.openai.com/v1/chat/completions");
  expect(request.headers.Authorization).toBe("Bearer openai-secret");
  expect(JSON.parse(request.body).messages[1].content).toContain("De planning is goedgekeurd.");
  expect(JSON.parse(request.body).messages[1].content).toContain("<h1>Titel</h1>");
});

it("uses the user's Anthropic API key through the Messages API", async () => {
  useSettingsStore.setState({ notulen_provider: "anthropic" as never });
  loadCredential.mockResolvedValue("anthropic-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ content: [{ type: "text", text: "<p>Akkoord</p>" }] }) });

  const html = await LLMService.generateNotulen("Akkoord.", profile);

  expect(html).toBe("<p>Akkoord</p>");
  expect(loadCredential).toHaveBeenCalledWith("anthropic_api_key");
  const request = invoke.mock.calls[0][1].request;
  expect(request.url).toBe("https://api.anthropic.com/v1/messages");
  expect(request.headers["x-api-key"]).toBe("anthropic-secret");
  expect(JSON.parse(request.body).messages[0].content).toContain("Akkoord.");
});

it("does not send a hosted request without the selected provider's key", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" as never });
  loadCredential.mockResolvedValue(null);

  await expect(LLMService.generateNotulen("Akkoord.", profile)).rejects.toThrow("API-sleutel");
  expect(invoke).not.toHaveBeenCalled();
});

it("passes quick notes as separate user context while preserving the transcript", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("openai-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Besluit</p>" } }] }) });
  await LLMService.generateNotulen("De planning is goedgekeurd.", profile, undefined, [], "Let op het budget.");
  const content = JSON.parse(invoke.mock.calls[0][1].request.body).messages[1].content;
  expect(content).toContain("context, geen onderdeel van de transcriptie");
  expect(content).toContain("Let op het budget.");
  expect(content).toContain("De planning is goedgekeurd.");
  expect(content).toContain("<h2>Notities</h2>");
});

it("appends the raw note as a Notities section when the model left it out", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("openai-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Besluit</p>" } }] }) });
  const html = await LLMService.generateNotulen("Akkoord.", profile, undefined, [], "Let op het budget.");
  expect(html).toBe("<p>Besluit</p><h2>Notities</h2><p>Let op het budget.</p>");
});
