import { beforeEach, expect, it, vi } from "vitest";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../tauriCommands", () => ({ loadCredential: vi.fn(async () => "private-test-key") }));
import { invoke } from "@tauri-apps/api/core";
import { loadCredential } from "../tauriCommands";
import { fetchOllamaModels } from "../ollamaModels";
beforeEach(() => vi.clearAllMocks());
it("discovers local models, deduplicates and never sends the cloud key over HTTP", async () => {
  vi.mocked(invoke).mockResolvedValueOnce({ status: 200, body: JSON.stringify({ data: [{ id: "z" }, { id: "a" }, { id: "a" }, { id: 7 }] }) });
  expect(await fetchOllamaModels("http://localhost:11434/")).toEqual(["a", "z"]);
  expect(loadCredential).not.toHaveBeenCalled();
  expect(invoke).toHaveBeenCalledWith("proxy_request", { request: expect.objectContaining({ url: "http://localhost:11434/v1/models", headers: {} }) });
});
it("uses the stored HTTPS key and falls back to native tags", async () => {
  vi.mocked(invoke).mockResolvedValueOnce({ status: 404, body: "" }).mockResolvedValueOnce({ status: 200, body: JSON.stringify({ models: [{ name: "gpt-oss:120b" }] }) });
  expect(await fetchOllamaModels("https://ollama.com")).toEqual(["gpt-oss:120b"]);
  expect(invoke).toHaveBeenLastCalledWith("proxy_request", { request: expect.objectContaining({ url: "https://ollama.com/api/tags", headers: { Authorization: "Bearer private-test-key" } }) });
});
it("reports malformed or unavailable lists and rejects unsupported URLs", async () => {
  vi.mocked(invoke).mockResolvedValue({ status: 200, body: '{"models":"not-a-list"}' });
  await expect(fetchOllamaModels("http://localhost:11434")).rejects.toThrow("Geen modellen");
  vi.clearAllMocks();
  await expect(fetchOllamaModels("file:///private/file")).rejects.toThrow("HTTP");
  expect(invoke).not.toHaveBeenCalled();
});
