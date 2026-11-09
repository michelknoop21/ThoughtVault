// Targeted acceptance regressions for the existing Mac test route.
// These must fail on the amount-only fix. No real provider/network calls.
import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService } from "../llm";
import { sourceFixture } from "./notuleAuditFixtures";

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => {
  const request = (args[1] as { request?: { body?: string } })?.request;
  const user = request?.body ? JSON.parse(request.body).messages.at(-1)?.content : "";
  if (user.startsWith("Broncontrole")) return Promise.resolve({ status: 200, body: JSON.stringify({ choices: [{ message: { content: sourceFixture(user) } }] }) });
  return invoke(...args);
} }));
vi.mock("../tauriCommands", () => ({ loadCredential: async () => null }));
vi.mock("../../stores/personalCorrectionsStore", () => ({
  usePersonalCorrectionsStore: { getState: () => ({ hydrate: async () => {}, entries: [] }) },
}));

const profile = { id: "standaard", name: "Standaard" };
const raw = "Dit is een fictieve acceptatieproef. Noor Bakker en Milan Vos bespreken project Dennenbrug. Het budget is 12.450 euro inclusief btw, niet 15.000 euro. We besluiten alleen een interne proef te doen. Er mogen geen klantgegevens naar externe diensten. Milan controleert de techniek op woensdag 11 november om 16 uur. Noor controleert de inhoud op donderdag 12 november. Zonder hun controle mag geen bredere uitrol plaatsvinden. Er is geen budgetverhoging goedgekeurd.";
const answer = (text: string) => ({ status: 200, body: JSON.stringify({
  choices: [{ message: { content: `<p>${text}</p>` } }],
}) });

beforeEach(() => {
  vi.resetAllMocks();
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama",
    ollama_url: "http://localhost:11434", ollama_model: "qa-fixture" });
});

it("passes the complete clean transcript to both requests and accepts complete factual output", async () => {
  invoke.mockResolvedValue(answer(raw));
  expect(await LLMService.generateNotulen(raw, profile)).toBe(`<p>${raw}</p>`);
  expect(invoke).toHaveBeenCalledTimes(2);
  for (const call of invoke.mock.calls) {
    expect(JSON.parse(call[1].request.body).messages[1].content).toContain(raw);
  }
});

it("rejects checked output that drops the explicit Noor action and deadline", async () => {
  const missing = raw.replace("Noor controleert de inhoud op donderdag 12 november. ", "");
  invoke.mockResolvedValue(answer(missing));
  const progress = vi.fn();
  await expect(LLMService.generateNotulen(raw, profile, progress)).rejects.toThrow();
  expect(progress).not.toHaveBeenCalled();
});

it("rejects contradictory permission even when the original prohibition is also present", async () => {
  invoke.mockResolvedValue(answer(`${raw} Klantgegevens mogen naar externe diensten worden verstuurd.`));
  const progress = vi.fn();
  await expect(LLMService.generateNotulen(raw, profile, progress)).rejects.toThrow();
  expect(progress).not.toHaveBeenCalled();
});
