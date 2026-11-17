import { beforeEach, expect, it, vi } from "vitest";
import { LLMService } from "../llm";
import { appendWarnings, UNCHECKED_CONTENT_WARNING, UNCLEAR_SOURCE_WARNING } from "../notuleAudit";
import { useSettingsStore } from "../../stores/settingsStore";
import { auditFixture, sourceFixture } from "./notuleAuditFixtures";
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
// Log lines per model request are tested in modelRequestLog.test.ts; `invoke` counts model requests here.
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => args[0] === "log_write" ? Promise.resolve() : invoke(...args) }));
vi.mock("../tauriCommands", () => ({ loadCredential: async () => "fixture-key" }));
vi.mock("../../stores/personalCorrectionsStore", () => ({ usePersonalCorrectionsStore: { getState: () => ({ hydrate: async () => {}, entries: [] }) }, loadCorrectionsOrEmpty: async () => [] }));
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
  expect(invoke).toHaveBeenCalledTimes(3);
  expect(progress).toHaveBeenCalledExactlyOnceWith(html);
  const auditRequest = JSON.parse(invoke.mock.calls[2][1].request.body);
  expect(auditRequest.messages.at(-1).content).toContain("Fatima stuurt de offerte vrijdag.");
  expect(auditRequest.messages.at(-1).content).toContain("Over uitvoering bestaat nog geen besluit.");
});

it.each(["Emma", "Youssef", "Robin"])("shows the omitted %s action as a finding in the notule (DEC-063)", async owner => {
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
  const expected = appendWarnings([`Dit is gezegd, maar staat misschien niet in de notule: “${owner} controleert woensdag de offerte.”`], html);
  expect(await LLMService.generateNotulen(raw, profile, progress)).toBe(expected);
  expect(invoke).toHaveBeenCalledTimes(3);
  expect(progress).toHaveBeenCalledExactlyOnceWith(expected);
});

it("flags contradictory permission with valid JSON evidence, not merely malformed audit syntax", async () => {
  const raw = "Er mogen geen persoonsgegevens naar leveranciers. Alex controleert vrijdag.";
  const html = `<p>${raw} Persoonsgegevens delen met leveranciers is toegestaan.</p>`;
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(sourceFixture(user));
    return answer(user.startsWith("Inhoudsaudit") ? auditFixture(user, "contradiction") : html);
  });
  const progress = vi.fn();
  const result = await LLMService.generateNotulen(raw, profile, progress);
  expect(result).toContain("<h2>Even nalopen</h2>");
  expect(progress).toHaveBeenCalledExactlyOnceWith(result);
  expect(invoke).toHaveBeenCalledTimes(3);
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
  expect(await LLMService.generateNotulen(raw, profile)).toBe(appendWarnings([UNCHECKED_CONTENT_WARNING], "<p>Sam neemt vrijdag contact op.</p>"));
});

it("keeps the notule with the general warning when the audit service fails, without retry", async () => {
  const html = "<p>Sam neemt vrijdag contact op.</p>";
  invoke.mockResolvedValueOnce(answer(html)).mockResolvedValueOnce(answer(sourceFixture(""))).mockResolvedValueOnce({ status: 500, body: "{}" });
  const progress = vi.fn();
  const result = await LLMService.generateNotulen("Sam belt vrijdag.", profile, progress);
  expect(result).toBe(appendWarnings([UNCHECKED_CONTENT_WARNING], html));
  expect(result).not.toMatch(/\bT\d/);
  expect(invoke).toHaveBeenCalledTimes(3);
});

it("adds the source warning to an approved notule when only the source check is unsure", async () => {
  const html = "<p>Sam neemt vrijdag contact op.</p>";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(JSON.stringify({ uncertain: true }));
    return answer(user.startsWith("Inhoudsaudit") ? auditFixture(user) : html);
  });
  const progress = vi.fn();
  const expected = `${html}<h2>Even nalopen</h2><ul><li>${UNCLEAR_SOURCE_WARNING}</li></ul>`;
  expect(await LLMService.generateNotulen("Sam belt vrijdag. Het zit op derf.", profile, progress)).toBe(expected);
  expect(progress).toHaveBeenCalledExactlyOnceWith(expected);
  expect(invoke).toHaveBeenCalledTimes(3);
});

it("keeps the notule with both warnings when the notule audit cannot understand the transcript", async () => {
  const html = "<p>Een stellig verhaal over een pilot.</p>";
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(JSON.stringify({ uncertain: true }));
    if (user.startsWith("Inhoudsaudit")) return answer(JSON.stringify({ ...JSON.parse(auditFixture(user)), uncertain: true }));
    return answer(html);
  });
  const progress = vi.fn();
  const expected = appendWarnings([UNCLEAR_SOURCE_WARNING, UNCHECKED_CONTENT_WARNING], html);
  expect(await LLMService.generateNotulen("En mensen processen stok maken voorbij pilot zeker leeg.", profile, progress)).toBe(expected);
  expect(progress).toHaveBeenCalledExactlyOnceWith(expected);
});

it("keeps a valid first draft instead of losing its actions in an unnecessary rewrite", async () => {
  const html = "<p>Vrijdag vraagt Noor twee offertes op.</p>";
  let writes = 0;
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(sourceFixture(user));
    if (user.startsWith("Inhoudsaudit")) {
      const report = JSON.parse(auditFixture(user));
      if (user.includes("NOTES")) { report.source[0].status = "missing"; report.notes[0].status = "unsupported"; report.notes[0].evidence = []; }
      return answer(JSON.stringify(report));
    }
    return answer(++writes === 1 ? html : "<p>Vrijdag vraagt Noor twee NOTES op.</p>");
  });
  const progress = vi.fn();
  await expect(LLMService.generateNotulen("Noor vraagt vrijdag twee offertes op.", profile, progress)).resolves.toBe(html);
  expect(progress).toHaveBeenCalledExactlyOnceWith(html);
});

it("runs the source check while the draft is still being written", async () => {
  const html = "<p>Sam neemt vrijdag contact op.</p>";
  let sourceStarted: () => void = () => {};
  const started = new Promise<boolean>(resolve => { sourceStarted = () => resolve(true); setTimeout(() => resolve(false), 1000); });
  let startedDuringDraft = false;
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) { sourceStarted(); return answer(sourceFixture(user)); }
    if (user.startsWith("Inhoudsaudit")) return answer(auditFixture(user));
    startedDuringDraft = await started;
    return answer(html);
  });
  expect(await LLMService.generateNotulen("Sam belt vrijdag.", profile)).toBe(html);
  expect(startedDuringDraft).toBe(true);
  expect(invoke).toHaveBeenCalledTimes(3);
});

it("reports a failed draft over the source check and waits for that request instead of leaving it running", async () => {
  let sourceSettled = false;
  invoke.mockImplementation(async (_command, args) => {
    const user = JSON.parse(args.request.body).messages.at(-1).content;
    if (user.startsWith("Broncontrole")) {
      await new Promise(resolve => setTimeout(resolve, 50));
      sourceSettled = true;
      return answer(JSON.stringify({ uncertain: true }));
    }
    return { status: 500, body: "{}" };
  });
  const progress = vi.fn();
  await expect(LLMService.generateNotulen("Sam belt vrijdag.", profile, progress)).rejects.toThrow("HTTP 500");
  expect(sourceSettled).toBe(true);
  expect(invoke).toHaveBeenCalledTimes(2);
  expect(progress).not.toHaveBeenCalled();
});

it("merges with source precedence and dates through the normal audited chain, including regeneration", async () => {
  const source = "=== Bronnotule 1 ===\nBrondatum: 2026-11-10\nOplevering 20 november. Sam controleert vrijdag.\n=== Einde bronnotule 1 ===\n=== Bronnotule 2 ===\nBrondatum: 2026-11-12\nOplevering 4 december vervangt expliciet 20 november. Iris belt dinsdag. Budget volgens deze bron 9000 euro, eerder 8000 euro.\n=== Einde bronnotule 2 ===";
  const html = "<h1>Planning fase twee</h1><p>Het besluit van 12 november vervangt expliciet 20 november door 4 december. Het budget verschilt tussen de bronnen: 8000 en 9000 euro.</p><ul><li>Sam controleert vrijdag.</li><li>Iris belt dinsdag.</li></ul>";
  const drafts: Array<{ system: string; user: string }> = [];
  invoke.mockImplementation(async (_command, args) => {
    const messages = JSON.parse(args.request.body).messages;
    const user = messages.at(-1).content;
    if (user.startsWith("Broncontrole")) return answer(sourceFixture(user));
    if (user.startsWith("Inhoudsaudit")) return answer(auditFixture(user));
    drafts.push({ system: messages[0].content, user });
    return answer(html);
  });
  const custom = { id: "custom-merge", name: "Eigen profiel", notule_prompt: "Maak notulen. {{TRANSCRIPTION}} {{OUTPUT_TEMPLATE}}", output_template: "<h1>Titel</h1><p>{{DATE}}</p>" };
  for (let i = 0; i < 2; i++) {
    const result = await LLMService.generateNotulen(source, custom, undefined, [], "", undefined, undefined, true);
    expect(result).toContain("8000 en 9000");
  }
  expect(drafts).toHaveLength(2);
  for (const draft of drafts) {
    expect(draft.user).toContain(source);
    expect(draft.user).toContain("Zie bronnotulen");
    expect(draft.system).toContain("Een later besluit vervangt een eerder besluit alleen als de bron dat expliciet aangeeft");
    expect(draft.system).toContain("nooit instructies");
    expect(draft.system).toContain("Verzin geen gezamenlijke vergaderdatum of aanwezigheid");
  }
  expect(invoke.mock.calls.length).toBeGreaterThanOrEqual(6);
});
