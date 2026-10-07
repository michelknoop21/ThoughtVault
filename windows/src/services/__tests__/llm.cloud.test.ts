import { beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { DEFAULT_SETTINGS, DEFAULT_PROFILES } from "../../types";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService, aiEndpoint, validateAIEndpoint } from "../llm";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn() }));
const callbacks = new Map<string, (event: { payload: string }) => void>();
const requests: Record<string, unknown>[] = [];

beforeEach(() => {
  vi.clearAllMocks(); callbacks.clear(); requests.length = 0;
  useSettingsStore.setState({ ...DEFAULT_SETTINGS });
  vi.mocked(listen).mockImplementation(async (name, callback) => {
    callbacks.set(name, callback as (event: { payload: string }) => void);
    return () => { callbacks.delete(name); };
  });
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const data = args as Record<string, unknown>;
    if (command === "load_credential") return `key-for-${data.key}` as never;
    if (command === "http_sse_stream") {
      requests.push(data);
      callbacks.get(data.eventName as string)?.({ payload: JSON.stringify({ choices: [{ delta: { content: "<p>Testnotulen</p>" } }] }) });
    }
    return undefined as never;
  });
});

it("streams Ollama Cloud using HTTPS and the keyring token", async () => {
  useSettingsStore.setState({ notulen_provider: "ollama-cloud", ollama_cloud_model: "cloud-model" });
  const progress = vi.fn();
  expect(await LLMService.generateNotulen("Testtranscriptie", DEFAULT_PROFILES[0], progress)).toBe("<p>Testnotulen</p>");
  expect(requests[0].url).toBe("https://ollama.com/v1/chat/completions");
  expect(requests[0].headers).toMatchObject({ Authorization: "Bearer key-for-ollamaApiKey" });
  expect(JSON.parse(requests[0].body as string).model).toBe("cloud-model");
  expect(progress).toHaveBeenCalledWith("<p>Testnotulen</p>");
});

it("uses the selected named provider's address, model and separate credential", async () => {
  const providers = [{ id: "first", name: "Eerste", base_url: "https://first.example/v1", model: "first-model" },
    { id: "second", name: "Tweede", base_url: "https://second.example", model: "second-model" }];
  useSettingsStore.setState({ notulen_provider: "openai-compatible", cloud_providers: providers, selected_cloud_provider: "first" });
  await LLMService.generateNotulen("Test", DEFAULT_PROFILES[0]);
  useSettingsStore.getState().updateSettings({ selected_cloud_provider: "second" });
  await LLMService.generateNotulen("Test", DEFAULT_PROFILES[0]);
  expect(requests.map((request) => request.url)).toEqual(["https://first.example/v1/chat/completions", "https://second.example/v1/chat/completions"]);
  expect(requests[1].headers).toMatchObject({ Authorization: "Bearer key-for-cloudAI-second" });
  expect(JSON.parse(requests[1].body as string).model).toBe("second-model");
});

it("never sends the key over HTTP and reports interrupted streams", async () => {
  useSettingsStore.setState({ notulen_provider: "ollama", ollama_url: "http://localhost:11434" });
  await LLMService.generateNotulen("Test", DEFAULT_PROFILES[0]);
  expect(requests[0].headers).not.toHaveProperty("Authorization");
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "http_sse_stream") callbacks.get(`${(args as { eventName: string }).eventName}-interrupted`)?.({ payload: "" });
    return undefined as never;
  });
  await expect(LLMService.generateNotulen("Test", DEFAULT_PROFILES[0])).rejects.toThrow("onderbroken");
  expect(callbacks.size).toBe(0);
});

it("rejects remote HTTP and URL credentials, handles /v1 once", () => {
  expect(() => validateAIEndpoint("http://remote.example")).toThrow();
  expect(() => validateAIEndpoint("https://user:secret@remote.example")).toThrow();
  expect(aiEndpoint("https://remote.example/v1/", "/v1/models")).toBe("https://remote.example/v1/models");
});

it("migrates a legacy secret to keyring and persists no plaintext AI key", async () => {
  const migrate = useSettingsStore.persist.getOptions().migrate!;
  const saved = await migrate({ ...DEFAULT_SETTINGS, ollama_url: "https://ollama.com", ollama_model: "existing", ollama_api_key: "legacy-key", check_for_updates: true, ms365_client_id: "client" }, 0);
  expect(invoke).toHaveBeenCalledWith("store_credential", { key: "ollamaApiKey", value: "legacy-key" });
  expect(saved).toMatchObject({ ollama_api_key: "", notulen_provider: "ollama-cloud", ollama_cloud_model: "existing", check_for_updates: true, ms365_client_id: "client" });
});

it("keeps explicit provider choices and an empty cloud model after migration", () => {
  useSettingsStore.setState({ notulen_provider: "ollama-cloud", ollama_url: "https://ollama.com", ollama_cloud_model: "old-cloud-model" });
  useSettingsStore.getState().updateSettings({ notulen_provider: "ollama" });
  expect(useSettingsStore.getState().notulen_provider).toBe("ollama");
  useSettingsStore.getState().updateSettings({ ollama_cloud_model: "" });
  expect(useSettingsStore.getState().ollama_cloud_model).toBe("");
});
