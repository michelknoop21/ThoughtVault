import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => null) }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async () => () => {}) }));
vi.mock("../../../services/tauriCommands", () => ({ loadCredential: vi.fn(async () => null) }));
vi.mock("../../../services/ollamaModels", () => ({
  OLLAMA_LOCAL_URL: "http://localhost:11434", OLLAMA_CLOUD_URL: "https://ollama.com", fetchOllamaModels: vi.fn(), isOllamaCloudURL: (url: string) => url === "https://ollama.com",
}));
import { ProcessingTab } from "../ProcessingTab";
import { fetchOllamaModels } from "../../../services/ollamaModels";
import { useSettingsStore } from "../../../stores/settingsStore";
it("prefills each Ollama location, loads its models and ignores a stale response", async () => {
  vi.useFakeTimers();
  let finishLocal!: (models: string[]) => void;
  vi.mocked(fetchOllamaModels).mockImplementationOnce(() => new Promise(resolve => { finishLocal = resolve; }))
    .mockResolvedValueOnce(["gpt-oss:120b"]);
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama", ollama_url: "http://localhost:11434", ollama_model: "" });
  const host = document.createElement("div"); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(<ProcessingTab />); });
  await act(async () => { await vi.advanceTimersByTimeAsync(350); });
  expect(fetchOllamaModels).toHaveBeenCalledWith("http://localhost:11434");
  const cloud = [...host.querySelectorAll<HTMLButtonElement>('[aria-label="Ollama locatie"] button')].find(b => b.textContent === "Cloud")!;
  await act(async () => { cloud.click(); });
  expect(useSettingsStore.getState().ollama_url).toBe("https://ollama.com");
  await act(async () => { await vi.advanceTimersByTimeAsync(350); });
  expect(host.querySelector<HTMLSelectElement>('[aria-label="Ollama model"]')?.value).toBe("gpt-oss:120b");
  await act(async () => { finishLocal(["stale-local-model"]); });
  expect(host.textContent).not.toContain("stale-local-model");
  expect(useSettingsStore.getState().ollama_model).toBe("gpt-oss:120b");
  await act(async () => { root.unmount(); }); host.remove(); vi.useRealTimers();
});
