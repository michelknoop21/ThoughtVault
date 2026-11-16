import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  invoke: vi.fn(),
  loadCredential: vi.fn(async (): Promise<string | null> => null),
  storeCredential: vi.fn(async () => {}),
}));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke }));
vi.mock("@tauri-apps/plugin-shell", () => ({ open: vi.fn() }));
vi.mock("../../../services/tauriCommands", () => ({ loadCredential: mocks.loadCredential, storeCredential: mocks.storeCredential }));
vi.mock("../../ui/DesktopDialog", () => ({ DesktopDialog: ({ children }: { children: React.ReactNode }) => <div data-dialog>{children}</div> }));

import { NotulenStep, choiceFor } from "../NotulenStep";
import { useSettingsStore } from "../../../stores/settingsStore";
import { DEFAULT_SETTINGS } from "../../../types";

let host: HTMLDivElement;
let root: Root;
const onDone = vi.fn();
const button = (text: string) => {
  const all = [...host.querySelectorAll("button")];
  return all.find(b => b.textContent === text) ?? all.find(b => b.textContent?.startsWith(text))!;
};
const type = (input: HTMLInputElement, value: string) => {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
  setter.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
};

beforeEach(async () => {
  vi.clearAllMocks();
  mocks.loadCredential.mockResolvedValue(null);
  useSettingsStore.setState({ ...DEFAULT_SETTINGS });
  host = document.createElement("div");
  document.body.appendChild(host);
  root = createRoot(host);
  await act(async () => root.render(<NotulenStep onBack={vi.fn()} onDone={onDone} />));
});

afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
});

it("maps stored providers to the tiles", () => {
  expect(choiceFor("openrouter")).toBe("openrouter");
  expect(choiceFor("cloud")).toBe("openrouter");
  expect(choiceFor("lm-studio")).toBe("local");
  expect(choiceFor("anthropic")).toBe("other");
});

it("starts on OpenRouter with the default model filled in", () => {
  expect(button("OpenRouter").getAttribute("aria-checked")).toBe("true");
  expect(host.querySelector<HTMLInputElement>('[aria-label="Model van OpenRouter"]')!.value).toBe(DEFAULT_SETTINGS.openrouter_model);
});

it("asks once before skipping and leaves the provider alone", async () => {
  await act(async () => button("Overslaan").click());
  expect(host.textContent).toContain("Zonder taalmodel verder?");
  await act(async () => button("Model kiezen").click());
  expect(host.querySelector("[data-dialog]")).toBeNull();
  expect(onDone).not.toHaveBeenCalled();

  // Volgende without a key asks the same question.
  await act(async () => button("Volgende").click());
  expect(host.textContent).toContain("Zonder taalmodel verder?");
  await act(async () => button("Toch overslaan").click());
  expect(onDone).toHaveBeenCalledOnce();
  expect(useSettingsStore.getState().notulen_provider).toBe("openrouter");
});

it("shows a spinner while testing, then a working or a rejected key", async () => {
  let reply!: (value: { status: number }) => void;
  mocks.invoke.mockImplementationOnce(() => new Promise(resolve => { reply = resolve; }));
  await act(async () => type(host.querySelector<HTMLInputElement>("#onb-key-input")!, "sk-or-v1-voorbeeld"));
  await act(async () => button("Testen").click());
  expect(host.textContent).toContain("Sleutel testen");
  expect(mocks.storeCredential).toHaveBeenCalledWith("openrouter_api_key", "sk-or-v1-voorbeeld");
  expect(mocks.invoke).toHaveBeenCalledWith("proxy_request", expect.objectContaining({
    request: expect.objectContaining({ url: "https://openrouter.ai/api/v1/key", headers: { Authorization: "Bearer sk-or-v1-voorbeeld" } }),
  }));
  await act(async () => reply({ status: 200 }));
  expect(host.textContent).toContain("Sleutel werkt");

  mocks.loadCredential.mockResolvedValue("sk-or-v1-voorbeeld");
  mocks.invoke.mockResolvedValueOnce({ status: 401 });
  await act(async () => button("Testen").click());
  expect(host.textContent).toContain("OpenRouter weigert deze sleutel");

  mocks.invoke.mockRejectedValueOnce(new Error("offline"));
  await act(async () => button("Testen").click());
  expect(host.textContent).toContain("OpenRouter is niet bereikbaar");
});

it("installs the chosen provider on Volgende", async () => {
  await act(async () => type(host.querySelector<HTMLInputElement>("#onb-key-input")!, "sk-or-v1-voorbeeld"));
  await act(async () => button("Volgende").click());
  expect(mocks.storeCredential).toHaveBeenCalledWith("openrouter_api_key", "sk-or-v1-voorbeeld");
  expect(onDone).toHaveBeenCalledOnce();

  useSettingsStore.setState({ ollama_url: "https://ollama.com", ollama_model: "" });
  await act(async () => button("Op deze pc").click());
  expect(host.textContent).toContain("Ollama schrijft de notule");
  await act(async () => button("Volgende").click());
  expect(useSettingsStore.getState()).toMatchObject({ notulen_provider: "ollama", ollama_url: "http://localhost:11434", ollama_model: "llama3.2" });

  mocks.loadCredential.mockResolvedValue("sk-ant-voorbeeld");
  await act(async () => button("Andere aanbieder").click());
  await act(async () => button("Claude").click());
  await act(async () => button("Volgende").click());
  expect(useSettingsStore.getState().notulen_provider).toBe("anthropic");
  expect(onDone).toHaveBeenCalledTimes(3);
});
