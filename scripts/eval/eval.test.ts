// Notule evaluation: runs the app's real LLMService (OpenRouter path incl. audit) per model x conversation x rep.
// Started through eval.mjs; arguments arrive as JSON in EVAL_ARGS. See README.md.
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { expect, it, vi } from "vitest";
import { LLMService } from "../../windows/src/services/llm";
import { UsageMeter, parseUsage } from "../../windows/src/services/usageMeter";
import { useSettingsStore } from "../../windows/src/stores/settingsStore";
import { readChatCompletion } from "../../windows/src/services/chatCompletion";
import { PRICE_CAP, usableModel } from "../../windows/src/services/suggestedModels";
import { DEFAULT_PROFILES } from "../../windows/src/types";
import { effectiveDetailLevel, type NotuleDetailLevel } from "../../windows/src/services/notuleDetailLevel";
import { enrichProfile } from "../../windows/src/services/profileTemplates";
import { assertOutsideRepo, copiedSentences, htmlToText, loadFacts, nalopenCount, scoreFacts, secureDir, secureWrite, summaryTable, SpendBudget, type RunResult } from "./lib";

/** Commit the pipeline ran on, so results before and after a pipeline change stay comparable. */
const COMMIT = (() => { try { return execFileSync("git", ["rev-parse", "--short", "HEAD"], { encoding: "utf8" }).trim(); } catch { return "onbekend"; } })();
const state = vi.hoisted(() => ({ auditErrors: [] as string[], auditReplies: [] as string[], dry: false, key: "", dryCost: 0.01, calls: 0, flaky: "", spendBudget: null as SpendBudget | null }));

const evalInvoke = async (command: string, args: { request?: { url: string; method?: string; headers?: Record<string, string>; body?: string | null; timeout_seconds: number; idle_timeout_seconds?: number } }) => {
  if (command !== "proxy_request" || !args.request) return undefined;
  const { url, method = "POST", headers, body, timeout_seconds, idle_timeout_seconds } = args.request;
  if (state.dry) return method === "GET" ? { status: 200, body: '{"data":[]}' } : dryResponse(JSON.parse(body!));
  let settle: ((actual?: number) => void) | undefined;
  if (method === "POST" && new URL(url).hostname === "openrouter.ai") {
    const request = JSON.parse(body!);
    if (!Number.isInteger(request.max_tokens) || request.max_tokens <= 0) throw new Error("Geen uitvoerlimiet");
    // Text-only requests: UTF-8 bytes plus message overhead conservatively bound input tokens.
    const ceiling = ((new TextEncoder().encode(body!).length + 1024) * PRICE_CAP.input
      + request.max_tokens * PRICE_CAP.output) / 1_000_000;
    if (!state.spendBudget) throw new Error("Geen budget ingesteld");
    settle = await state.spendBudget.reserve(ceiling);
  }
  const controller = new AbortController();
  const total = setTimeout(() => controller.abort(), timeout_seconds * 1000);
  let idle: ReturnType<typeof setTimeout> | undefined;
  const progress = () => {
    if (idle_timeout_seconds) {
      clearTimeout(idle);
      idle = setTimeout(() => controller.abort(), idle_timeout_seconds * 1000);
    }
  };
  progress();
  try {
    const res = await fetch(url, { method, headers, body, signal: controller.signal });
    let text = "";
    if (idle_timeout_seconds && res.body) {
      const reader = res.body.getReader(), decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        progress();
        text += decoder.decode(value, { stream: true });
      }
      text += decoder.decode();
    } else text = await res.text();
    if (settle) settle(parseUsage(readChatCompletion(text).usage)?.cost);
    // The content check's raw verdicts, kept next to the notule to see why a check ended as it did.
    if (body && /Inhoudsaudit|Notulezin/.test(body)) state.auditReplies.push(text);
    return { status: res.status, body: text, headers: Object.fromEntries(res.headers) };
  } catch (error) {
    if (controller.signal.aborted) throw `Tijdslimiet bereikt na ${timeout_seconds} s`;
    throw error;
  } finally {
    settle?.();
    clearTimeout(total);
    clearTimeout(idle);
  }
};

(globalThis as { __evalInvoke?: unknown }).__evalInvoke = evalInvoke;

it("reserves concurrent costs and stops on unknown costs", async () => {
  const budget = new SpendBudget(1);
  const first = await budget.reserve(0.8);
  let admitted = false;
  const second = budget.reserve(0.8).then(release => { admitted = true; return release; });
  await Promise.resolve();
  expect(admitted).toBe(false);
  expect(budget.exposure).toBeCloseTo(0.8);
  first(0.1);
  const release = await second;
  release(0.1);
  expect(budget.spent).toBeCloseTo(0.2);
  await expect(budget.reserve(0.9)).rejects.toThrow("Budget bereikt");
  expect(budget.stopReason).toBe("Budget bereikt");
  await expect(budget.reserve(0.1)).rejects.toThrow("Budget bereikt");
  const uncertain = new SpendBudget(1);
  const unknown = await uncertain.reserve(0.2);
  unknown();
  expect(uncertain.exposure).toBeCloseTo(0.2);
  await expect(uncertain.reserve(0.1)).rejects.toThrow("Kosten onbekend");
});

it("forwards catalog GET requests without a body", async () => {
  const fetchMock = vi.fn().mockResolvedValue({ status: 200, text: async () => '{"data":[]}', headers: new Headers() });
  vi.stubGlobal("fetch", fetchMock);
  try {
    await evalInvoke("proxy_request", { request: { url: "https://fixture.invalid/models", method: "GET", timeout_seconds: 1 } });
    expect(fetchMock.mock.calls[0][1]).toMatchObject({ method: "GET", body: undefined });
  } finally { vi.unstubAllGlobals(); }
});

it("preserves text across streamed byte boundaries", async () => {
  const bytes = new TextEncoder().encode("één antwoord");
  const body = new ReadableStream({ start(controller) {
    controller.enqueue(bytes.slice(0, 1)); controller.enqueue(bytes.slice(1)); controller.close();
  } });
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(body)));
  try {
    const response = await evalInvoke("proxy_request", { request: { url: "https://fixture.invalid/chat",
      body: "{}", timeout_seconds: 1, idle_timeout_seconds: 0.5 } });
    expect(response?.body).toBe("één antwoord");
  } finally { vi.unstubAllGlobals(); }
});

it("applies the native idle limit before an answer arrives", async () => {
  vi.stubGlobal("fetch", vi.fn((_url, options) => new Promise((_resolve, reject) =>
    options.signal.addEventListener("abort", () => reject(new Error("aborted"))))));
  try {
    await expect(evalInvoke("proxy_request", { request: { url: "https://fixture.invalid/chat", method: "POST",
      body: "{}", timeout_seconds: 1, idle_timeout_seconds: 0.02 } })).rejects.toContain("Tijdslimiet bereikt");
  } finally { vi.unstubAllGlobals(); }
});

vi.mock("../../windows/src/services/tauriCommands", async importOriginal => ({
  ...(await importOriginal<object>()),
  loadCredential: async (key: string) => (key === "openrouter_api_key" ? state.key : null),
}));
// The app turns a failed check into a warning line; the evaluation also records why it failed.
vi.mock("../../windows/src/services/notuleAudit", async importOriginal => {
  const real = await importOriginal<Record<string, (...args: unknown[]) => Promise<unknown>>>();
  const recording = (name: string) => async (...args: unknown[]) => {
    try { return await real[name](...args); }
    catch (error) { state.auditErrors.push(`${name}: ${(error instanceof Error ? error.message : String(error)).split(":")[0]}`); throw error; }
  };
  return { ...real, auditSource: recording("auditSource"), auditNotule: recording("auditNotule") };
});
vi.mock("../../windows/src/stores/personalCorrectionsStore", () => ({
  usePersonalCorrectionsStore: { getState: () => ({ hydrate: async () => {}, entries: [] }) },
  loadCorrectionsOrEmpty: async () => [],
}));

/** Canned OpenRouter answer for --dry-run: JSON for the audit steps, a fictional notule for the draft. */
function dryResponse(req: { model: string; messages: { content: string }[] }) {
  state.calls += 1;
  const user = req.messages.at(-1)!.content;
  let content: string;
  if (user.startsWith("Broncontrole")) content = req.model === state.flaky ? "geen json" : '{"uncertain":false}'; // flaky model: exercises the "Even nalopen" count
  else if (user.startsWith("Inhoudsaudit")) {
    const input = JSON.parse(user.split("\n").slice(1).join("\n"));
    content = JSON.stringify({
      source: input.source.map((s: { id: string }) => ({ id: s.id, status: "covered" })),
      notes: input.notes.map((n: { id: string }) => ({ id: n.id, status: "supported", evidence: input.source.map((s: { id: string }) => s.id) })),
      uncertain: false,
    });
  } else content = DRY_NOTULE;
  return { status: 200, body: JSON.stringify({ choices: [{ message: { content }, finish_reason: "stop" }], usage: { prompt_tokens: 1000, completion_tokens: 200, cost: state.dryCost } }) };
}
// Fictional. Misses the fact with search term "Zeeland".
const DRY_NOTULE = "<h1>Fruitteler Bakker bespreekt oogst en verkoop</h1><p>De oogst van de appels begint op 3 oktober. De prijs is 1,25 euro per kilo. Marit regelt het transport.</p>";

it("notule-eval", async () => {
  const { values: a } = parseArgs({
    args: JSON.parse(process.env.EVAL_ARGS ?? "[]"),
    options: {
      models: { type: "string", default: "all" }, conversations: { type: "string", default: "schadebezoek,thuisserver" },
      reps: { type: "string", default: "1" }, budget: { type: "string", default: "6" }, detail: { type: "string" },
      "dry-run": { type: "boolean", default: false }, "dry-cost": { type: "string", default: "0.01" },
      "data-dir": { type: "string" }, "results-dir": { type: "string" },
      candidates: { type: "string", default: join(import.meta.dirname, "candidates.json") },
    },
  });
  if (a.detail && !["kort", "normaal", "volledig"].includes(a.detail)) throw new Error("--detail: kort, normaal of volledig");
  const reps = Number(a.reps), budget = Number(a.budget);
  if (!(reps >= 1) || !(budget > 0)) throw new Error("--reps en --budget moeten positief zijn");
  state.spendBudget = new SpendBudget(budget);
  state.dry = a["dry-run"]; state.dryCost = Number(a["dry-cost"]);
  const dataDir = resolve(a["data-dir"] ?? (state.dry ? join(import.meta.dirname, "fixtures") : join(homedir(), "Documents/ThoughtVault-eval")));
  const conversations = state.dry ? ["demo"] : a.conversations!.split(",");

  // Models: "all", tier names or ids, checked against the public OpenRouter list.
  const tiers: Record<string, string[]> = JSON.parse(readFileSync(a.candidates!, "utf8"));
  const all = Object.values(tiers).flat();
  const models = a.models === "all" ? all : [...new Set(a.models!.split(",").flatMap(m => tiers[m] ?? [m]))];
  state.flaky = all[1];
  const known = state.dry ? new Set(all) : new Set<string>((await (await fetch("https://openrouter.ai/api/v1/models")).json()).data.map((m: { id: string }) => m.id));
  const unknown = models.filter(m => !known.has(m));
  if (unknown.length) throw new Error(`Onbekende model-id's, afgebroken: ${unknown.join(", ")}`);
  if (!state.dry && models.some(model => usableModel(model, "openrouter") !== model)) {
    throw new Error("Een gekozen model zou door de app worden vervangen; meting afgebroken om onjuiste labels te voorkomen.");
  }

  state.key = state.dry ? "dry-run-key" : process.env.OPENROUTER_API_KEY ?? process.env.VAULT_VALUE ?? "";
  if (!state.dry) {
    if (!state.key) throw new Error("Geen OPENROUTER_API_KEY (of VAULT_VALUE) in de omgeving.");
  }
  const resultsDir = resolve(a["results-dir"] ?? (state.dry ? join(tmpdir(), "notule-eval-dry") : join(dataDir, "results")), new Date().toISOString().replace(/[:.]/g, "-"));
  assertOutsideRepo(resultsDir);
  secureDir(resultsDir);

  const data = Object.fromEntries(conversations.map(c => {
    const files = readdirSync(dataDir).filter(f => f.startsWith(c));
    const txt = files.find(f => f.endsWith(".txt")), json = files.find(f => f.endsWith(".json"));
    if (!txt || !json) throw new Error(`Gesprek "${c}" niet gevonden in de datamap`);
    return [c, { transcript: readFileSync(join(dataDir, txt), "utf8"), facts: loadFacts(JSON.parse(readFileSync(join(dataDir, json), "utf8"))) }];
  }));

  const profile = DEFAULT_PROFILES.find(p => p.id === useSettingsStore.getState().default_profile_id) ?? DEFAULT_PROFILES[0];
  // --detail overrides the profile's own level, as the user's choice does in the app.
  const detail = (a.detail as NotuleDetailLevel | undefined) ?? effectiveDetailLevel(enrichProfile(profile));
  const runs: RunResult[] = [];
  let total = 0, stopped = "";
  outer: for (let rep = 1; rep <= reps; rep++) for (const conversation of conversations) for (const model of models) {
    if (total >= budget) { stopped = `Budget bereikt (USD ${total.toFixed(4)} van ${budget}); resterende runs overgeslagen.`; break outer; }
    useSettingsStore.setState({ notulen_provider: "openrouter", openrouter_model: model, notulen_fallback_provider: "", processing_mode: "local" });
    const meter = new UsageMeter();
    state.auditErrors = []; state.auditReplies = [];
    const started = Date.now();
    let html = "", error: string | null = null;
    try { html = await LLMService.generateNotulen(data[conversation].transcript, profile, undefined, [], "", undefined, meter, false, undefined, detail); }
    catch (e) { error = e instanceof Error ? e.message : String(e); }
    if (state.spendBudget.stopReason) error = "Meetbudget: " + state.spendBudget.stopReason;
    const text = htmlToText(html), score = scoreFacts(text, data[conversation].facts);
    const run: RunResult = { model, conversation, rep, detail, ...score, ...copiedSentences(text, data[conversation].transcript), chars: text.length, words: text.split(" ").filter(Boolean).length,
      nalopen: nalopenCount(html), auditErrors: state.auditErrors, durationMs: Date.now() - started, costUsd: meter.totalCost, costKnown: meter.costKnown, budgetLimited: state.spendBudget.waited || Boolean(state.spendBudget.stopReason), error, commit: COMMIT };
    runs.push(run); total += run.costUsd;
    secureWrite(join(resultsDir, `${model.replace(/\//g, "_")}__${conversation}__r${rep}.html`), html);
    if (state.auditReplies.length) secureWrite(join(resultsDir, `${model.replace(/\//g, "_")}__${conversation}__r${rep}.audit.json`), JSON.stringify(state.auditReplies));
    secureWrite(join(resultsDir, "runs.jsonl"), JSON.stringify(run) + "\n", true);
    console.log(`${model} ${conversation} r${rep}: ${error ? "FOUT" : `${run.found}/${run.total} feiten, ${run.copied} letterlijk, ${run.chars} tekens${run.auditErrors.length ? `, controle: ${run.auditErrors.join("; ")}` : ""}`}, USD ${run.costUsd.toFixed(4)}, ${(run.durationMs / 1000).toFixed(1)}s`);
    // A failed run counts as an error and the comparison goes on; only a successful run
    // without a reported cost stops it, because then the budget can no longer be tracked.
    if ((!meter.costKnown || state.spendBudget.stopReason) && !state.dry) { stopped = state.spendBudget.stopReason || "Kosten onbekend of boven de raming; gestopt om het budget te bewaken."; break outer; }
  }
  await state.spendBudget.drain();
  if (!state.dry) stopped += "\nBetaald of conservatief gereserveerd: maximaal USD " + state.spendBudget.exposure.toFixed(4) + " van " + budget + ".";
  if (state.spendBudget.waited) stopped += "\nParalleliteit tijdelijk begrensd door het kostenplafond; deze looptijden zijn niet de normale app-snelheid.";
  const summary = summaryTable(runs, total) + (stopped ? `\n${stopped}\n` : "") + `\nDetailniveau: ${detail}\n`;
  secureWrite(join(resultsDir, "summary.md"), summary);
  console.log(`\n${summary}\nResultaten: ${resultsDir}`);
});
