import { beforeEach, expect, it, vi } from "vitest";
import { LLMService } from "../llm";
import { NotuleReviewError } from "../notuleAudit";
import { useSettingsStore } from "../../stores/settingsStore";
import { auditFixture, sourceFixture } from "./notuleAuditFixtures";
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential: async () => "fixture-key" }));
vi.mock("../../stores/personalCorrectionsStore", () => ({ usePersonalCorrectionsStore: { getState: () => ({ hydrate: async () => {}, entries: [] }) } }));
const profile = { id: "standaard", name: "Standaard" };
const answer = (content: string) => ({ status: 200, body: JSON.stringify({ choices: [{ message: { content } }], content: [{ type: "text", text: content }] }) });

beforeEach(() => { vi.resetAllMocks(); useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama", ollama_url: "http://localhost:11434", ollama_model: "fixture" }); });

it.each(["ollama", "lm-studio", "openai", "anthropic"] as const)("audits correct conditional and negative paraphrases through %s without literal-only rejection", async provider => {
  useSettingsStore.setState({ notulen_provider: provider });
  const raw = "Fatima stuurt de offerte vrijdag. Als de test slaagt, geeft Bram maandag akkoord. Er is nog niet over uitvoering besloten.";
  const html = "<p>De offerte wordt vrijdag door Fatima verstuurd. Bram geeft maandag uitsluitend bij een geslaagde test akkoord. Over uitvoering bestaat nog geen besluit.</p>";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(sourceFixture(user));
    return answer(user.startsWith("Inhoudsaudit") ? auditFixture(user) : html);
  });
  const progress = vi.fn();
  expect(await LLMService.generateNotulen(raw, profile, progress)).toBe(html);
  expect(invoke).toHaveBeenCalledTimes(4);
  expect(progress).toHaveBeenCalledExactlyOnceWith(html);
  const auditRequest = JSON.parse(invoke.mock.calls[3][1].request.body);
  expect(auditRequest.messages.at(-1).content).toContain("Fatima stuurt de offerte vrijdag.");
  expect(auditRequest.messages.at(-1).content).toContain("Over uitvoering bestaat nog geen besluit.");
});

it.each(["Emma", "Youssef", "Robin"])("fails closed when the structured audit reports the omitted %s action", async owner => {
  const raw = `Sam belt dinsdag. ${owner} controleert woensdag de offerte.`;
  const html = "<p>Sam neemt dinsdag telefonisch contact op.</p>";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(sourceFixture(user));
    if (!user.startsWith("Inhoudsaudit")) return answer(html);
    const report = JSON.parse(auditFixture(user)); report.source[1].status = "missing"; report.source[1].evidence = [];
    return answer(JSON.stringify(report));
  });
  const progress = vi.fn();
  const failure = await LLMService.generateNotulen(raw, profile, progress).catch(error => error);
  expect(failure).toBeInstanceOf(NotuleReviewError);
  expect(failure.draftHtml).toBe(html);
  expect(invoke).toHaveBeenCalledTimes(4);
  expect(progress).not.toHaveBeenCalled();
});

it("rejects contradictory permission with valid JSON evidence, not merely malformed audit syntax", async () => {
  const raw = "Er mogen geen persoonsgegevens naar leveranciers. Alex controleert vrijdag.";
  const html = `<p>${raw} Persoonsgegevens delen met leveranciers is toegestaan.</p>`;
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(sourceFixture(user));
    return answer(user.startsWith("Inhoudsaudit") ? auditFixture(user, "contradiction") : html);
  });
  const progress = vi.fn();
  await expect(LLMService.generateNotulen(raw, profile, progress)).rejects.toBeInstanceOf(NotuleReviewError);
  expect(progress).not.toHaveBeenCalled();
  expect(invoke).toHaveBeenCalledTimes(4);
});

it("never labels a protected source condition non-factual to approve its omission", async () => {
  const raw = "Er is geen besluit genomen. Sam belt vrijdag.";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(sourceFixture(user));
    if (!user.startsWith("Inhoudsaudit")) return answer("<p>Sam neemt vrijdag contact op.</p>");
    const report = JSON.parse(auditFixture(user));
    report.source[0].status = "non_factual"; report.source[0].evidence = [];
    report.notes.forEach((n: { evidence: string[] }) => { n.evidence = ["T2"]; });
    return answer(JSON.stringify(report));
  });
  await expect(LLMService.generateNotulen(raw, profile)).rejects.toThrow("expliciete beperkingen");
});

it("retains the checked candidate when the audit service fails, with no success or retry", async () => {
  const html = "<p>Sam neemt vrijdag contact op.</p>";
  invoke.mockResolvedValueOnce(answer("<p>Eerste concept</p>")).mockResolvedValueOnce(answer(html)).mockResolvedValueOnce({ status: 500, body: "{}" });
  const progress = vi.fn();
  const failure = await LLMService.generateNotulen("Sam belt vrijdag.", profile, progress).catch(error => error);
  expect(failure).toBeInstanceOf(NotuleReviewError);
  expect(failure.draftHtml).toBe(html);
  expect(progress).not.toHaveBeenCalled();
  expect(invoke).toHaveBeenCalledTimes(3);
});

it("retains a readable draft when a separate source-only check cannot understand the transcript", async () => {
  const html = "<p>Een stellig verhaal over een pilot.</p>";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(JSON.stringify({ uncertain: true }));
    return answer(user.startsWith("Inhoudsaudit") ? auditFixture(user) : html);
  });
  const progress = vi.fn();
  const failure = await LLMService.generateNotulen("En mensen processen stok maken voorbij pilot zeker leeg.", profile, progress).catch(error => error);
  expect(failure).toBeInstanceOf(NotuleReviewError);
  expect(failure.draftHtml).toBe(html);
  expect(progress).not.toHaveBeenCalled();
});
