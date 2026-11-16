// Notule evaluation: runs the app's real LLMService (OpenRouter path incl. audit) per model x conversation x rep.
// Started through eval.mjs; arguments arrive as JSON in EVAL_ARGS. See README.md.
import { readFileSync, readdirSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { it, vi } from "vitest";
import { LLMService } from "../../windows/src/services/llm";
import { UsageMeter } from "../../windows/src/services/usageMeter";
import { useSettingsStore } from "../../windows/src/stores/settingsStore";
import { DEFAULT_PROFILES } from "../../windows/src/types";
import { assertOutsideRepo, htmlToText, loadFacts, nalopenCount, scoreFacts, secureDir, secureWrite, summaryTable, type RunResult } from "./lib";

const state = vi.hoisted(() => ({ dry: false, key: "", dryCost: 0.01, calls: 0, flaky: "" }));

(globalThis as { __evalInvoke?: unknown }).__evalInvoke = async (command: string, args: { request?: { url: string; headers: Record<string, string>; body: string; timeout_seconds: number } }) => {
  if (command !== "proxy_request" || !args.request) return undefined; // log_write and the like
  const { url, headers, body, timeout_seconds } = args.request;
  if (state.dry) return dryResponse(JSON.parse(body));
  const res = await fetch(url, { method: "POST", headers, body, signal: AbortSignal.timeout(timeout_seconds * 1000) });
  return { status: res.status, body: await res.text(), headers: Object.fromEntries(res.headers) };
};
vi.mock("../../windows/src/services/tauriCommands", async importOriginal => ({
  ...(await importOriginal<object>()),
  loadCredential: async (key: string) => (key === "openrouter_api_key" ? state.key : null),
}));
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

  if (a.detail) console.log(`Detailniveau "${a.detail}" genegeerd: de pijplijn kent die optie nog niet (n.v.t.).`);
  const profile = DEFAULT_PROFILES.find(p => p.id === useSettingsStore.getState().default_profile_id) ?? DEFAULT_PROFILES[0];
  const runs: RunResult[] = [];
  let total = 0, stopped = "";
  outer: for (let rep = 1; rep <= reps; rep++) for (const conversation of conversations) for (const model of models) {
    if (total >= budget) { stopped = `Budget bereikt (USD ${total.toFixed(4)} van ${budget}); resterende runs overgeslagen.`; break outer; }
    useSettingsStore.setState({ notulen_provider: "openrouter", openrouter_model: model, notulen_fallback_provider: "", processing_mode: "local" });
    const meter = new UsageMeter();
    const started = Date.now();
    let html = "", error: string | null = null;
    try { html = await LLMService.generateNotulen(data[conversation].transcript, profile, undefined, [], "", undefined, meter); }
    catch (e) { error = e instanceof Error ? e.message : String(e); }
    const text = htmlToText(html), score = scoreFacts(text, data[conversation].facts);
    const run: RunResult = { model, conversation, rep, detail: "n.v.t.", ...score, chars: text.length, words: text.split(" ").filter(Boolean).length,
      nalopen: nalopenCount(html), durationMs: Date.now() - started, costUsd: meter.totalCost, costKnown: meter.costKnown, error };
    runs.push(run); total += run.costUsd;
    secureWrite(join(resultsDir, `${model.replace(/\//g, "_")}__${conversation}__r${rep}.html`), html);
    secureWrite(join(resultsDir, "runs.jsonl"), JSON.stringify(run) + "\n", true);
    console.log(`${model} ${conversation} r${rep}: ${error ? "FOUT" : `${run.found}/${run.total} feiten`}, USD ${run.costUsd.toFixed(4)}, ${(run.durationMs / 1000).toFixed(1)}s`);
    // A failed run counts as an error and the comparison goes on; only a successful run
    // without a reported cost stops it, because then the budget can no longer be tracked.
    if (!meter.costKnown && !error && !state.dry) { stopped = "Kosten van een verzoek onbekend; gestopt om het budget te bewaken."; break outer; }
  }
  const summary = summaryTable(runs, total) + (stopped ? `\n${stopped}\n` : "") + `\nDetailniveau: n.v.t. (pijplijn kent het niet)\n`;
  secureWrite(join(resultsDir, "summary.md"), summary);
  console.log(`\n${summary}\nResultaten: ${resultsDir}`);
});
