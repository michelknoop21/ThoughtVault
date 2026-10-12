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
  const model = host.querySelector<HTMLSelectElement>('[aria-label="Ollama model"]')!;
  expect(model.value).toBe("");
  expect(model.textContent).toContain("gpt-oss:120b");
  await act(async () => { model.value = "gpt-oss:120b"; model.dispatchEvent(new Event("change", { bubbles: true })); });
  await act(async () => { finishLocal(["stale-local-model"]); });
  expect(host.textContent).not.toContain("stale-local-model");
  expect(useSettingsStore.getState().ollama_model).toBe("gpt-oss:120b");
  await act(async () => { root.unmount(); }); host.remove(); vi.useRealTimers();
});

it("does not call pending system advice unavailable or replace the selected model", async () => {
  const { invoke } = await import("@tauri-apps/api/core");
  let finish!: (value: unknown) => void;
  vi.mocked(invoke).mockImplementation(command => command === "get_system_specs"
    ? new Promise(resolve => { finish = resolve; }) : Promise.resolve(null) as never);
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "openai", whisper_model: "small" });
  const host = document.createElement("div"); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(<ProcessingTab />); });
  expect(host.textContent).toContain("Systeemadvies wordt geladen");
  expect(host.textContent).not.toContain("Systeemadvies niet beschikbaar");
  await act(async () => { finish({ cpu: "QA", architecture: "AMD64", memory_gb: 48, threads: 16, os_version: "Windows", free_storage_gb: 770 }); });
  expect(host.textContent).toContain("Whisper Medium");
  expect(useSettingsStore.getState().whisper_model).toBe("small");
  const model = host.querySelector<HTMLSelectElement>('[aria-label="Transcriptiemodel"]')!;
  expect([...model.options].map(option => option.value)).toContain("base");
  await act(async () => { model.value = "base"; model.dispatchEvent(new Event("change", { bubbles: true })); });
  expect(useSettingsStore.getState().whisper_model).toBe("base");
  await act(async () => { root.unmount(); }); host.remove();
});
