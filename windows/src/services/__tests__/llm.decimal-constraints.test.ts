import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService } from "../llm";
import { sourceFixture, auditFixture } from "./notuleAuditFixtures";

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => {
  // Log lines per model request are tested in modelRequestLog.test.ts; `invoke` counts model requests here.
  if (args[0] === "log_write") return Promise.resolve();
  const request = (args[1] as { request?: { body?: string } })?.request;
  const user = request?.body ? JSON.parse(request.body).messages.at(-1)?.content : "";
  if (user.startsWith("Broncontrole")) return Promise.resolve({ status: 200, body: JSON.stringify({ choices: [{ message: { content: sourceFixture(user) } }] }) });
  return invoke(...args);
} }));
vi.mock("../tauriCommands", () => ({ loadCredential: async () => null }));
vi.mock("../../stores/personalCorrectionsStore", () => ({
  usePersonalCorrectionsStore: { getState: () => ({ hydrate: async () => {}, entries: [] }) },
  loadCorrectionsOrEmpty: async () => [],
}));

const profile = {
  id: "qa-decimal", name: "Fictieve proef",
  system_prompt: "Maak brongetrouwe notulen.",
  notule_prompt: "Notuleer: {{TRANSCRIPTION}}\n{{OUTPUT_TEMPLATE}}",
  output_template: "<h2>Besluiten</h2>",
};
const response = (html: string) => ({
  status: 200, body: JSON.stringify({ choices: [{ message: { content: html } }] }),
});

beforeEach(() => {
  vi.resetAllMocks();
  useSettingsStore.setState({
    processing_mode: "local", notulen_provider: "ollama",
    ollama_url: "http://localhost:11434", ollama_model: "qa-fixture",
  });
});

// Red on 55ecb90: the checker is instructed to preserve only "Niet 15."
// and the final guard accepts that incomplete amount as the full constraint.
it("flags a checked note that truncates the negated 15.000 euro amount", async () => {
  const raw = "Het budget is 12.450 euro inclusief btw. Niet 15.000 euro.";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages[1].content;
    if (!user.startsWith("Inhoudsaudit")) return response("<p>Niet 15.</p>");
    const report = JSON.parse(auditFixture(user)); report.source[1].status = "missing";
    return response(JSON.stringify(report));
  });
  const progress = vi.fn();
  expect(await LLMService.generateNotulen(raw, profile, progress)).toContain("Dit is gezegd, maar staat misschien niet in de notule: “Niet 15.000 euro.”");
  expect(invoke).toHaveBeenCalledTimes(2);
  expect(progress).toHaveBeenCalledOnce();
});

it.each(["Niet 15.000 euro.", "Niet 1.500.000 euro.", "Niet 15.000,50 euro.", "Niet 15.5 euro."])(
  "keeps the complete numeric constraint in the generation request: %s", async constraint => {
    const raw = `Budgetcontrole. ${constraint} Milan controleert de techniek woensdag. Noor controleert de inhoud donderdag.`;
    const checked = `<p>${raw}</p>`;
    invoke.mockResolvedValue(response(checked));
    expect(await LLMService.generateNotulen(raw, profile)).toBe(checked);
    const prompts = invoke.mock.calls.map(call => JSON.parse(call[1].request.body).messages[1].content as string);
    expect(prompts).toHaveLength(1);
    expect(prompts.every(prompt => prompt.includes(raw))).toBe(true);
    const required = prompts[0].split("Verplicht te behouden bronzinnen")[1];
    expect(required).toContain(`1. ${constraint}`);
    expect(required).not.toContain("1. Niet 15.\n");
  },
);

it("still flags a prohibition after a normal sentence boundary", async () => {
  const raw = "Niet 15.000 euro. Geen klantgegevens naar externe diensten.";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages[1].content;
    if (!user.startsWith("Inhoudsaudit")) return response("<p>Niet 15.000 euro.</p>");
    const report = JSON.parse(auditFixture(user)); report.source[1].status = "missing";
    return response(JSON.stringify(report));
  });
  expect(await LLMService.generateNotulen(raw, profile)).toContain("<h2>Even nalopen</h2>");
  const prompt = JSON.parse(invoke.mock.calls[0][1].request.body).messages[1].content as string;
  expect(prompt).toContain("1. Niet 15.000 euro.\n2. Geen klantgegevens naar externe diensten.");
});
