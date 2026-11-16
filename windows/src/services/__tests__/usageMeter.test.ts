import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService } from "../llm";
import { UsageMeter, parseUsage, addToLedger, usageLine, formatEuro } from "../usageMeter";
import type { NotuleUsage } from "../../types";

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential: vi.fn() }));

it("parses the three provider shapes", () => {
  expect(parseUsage({ prompt_tokens: 10, completion_tokens: 5, completion_tokens_details: { reasoning_tokens: 2 }, cost: 0.0123 }))
    .toEqual({ input: 10, output: 5, reasoning: 2, cost: 0.0123 });
  expect(parseUsage({ prompt_tokens: 10, completion_tokens: 5, completion_tokens_details: { reasoning_tokens: 2 } }))
    .toEqual({ input: 10, output: 5, reasoning: 2, cost: undefined });
  expect(parseUsage({ input_tokens: 7, output_tokens: 3 })).toMatchObject({ input: 7, output: 3, cost: undefined });
  expect(parseUsage(undefined)).toBeUndefined();
  expect(parseUsage({})).toBeUndefined();
});

it("totals parallel requests and counts a request without usage as unknown", async () => {
  const meter = new UsageMeter();
  await Promise.all([1, 2, 3].map(async i => { await Promise.resolve(); meter.record("sentence-check", { input: 100 * i, output: 10, reasoning: 1, cost: 0.01 }); }));
  meter.record("draft", undefined);
  const usage = meter.usageFor("abc", "<p>Een zin. Nog een zin.</p>");
  expect(usage).toMatchObject({ requests: 4, unknown_requests: 1, input_tokens: 600, output_tokens: 30, reasoning_tokens: 3, sentences: 2, words: 5, transcript_chars: 3 });
  expect(usage.steps["sentence-check"]).toEqual({ requests: 3, input_tokens: 600, output_tokens: 30 });
  // The request without a body has no cost either, so the total is unknown.
  expect(usage.cost_usd).toBeNull();
});

it("keeps the cost known when every request reports it, and free runs cost nothing", () => {
  const paid = new UsageMeter();
  paid.record("draft", { input: 1, output: 1, cost: 0.02 });
  paid.record("note-check", { input: 1, output: 1, cost: 0.03 });
  expect(paid.usageFor("t", "<p>x</p>").cost_usd).toBeCloseTo(0.05);
  paid.record("note-check", { input: 1, output: 1 });
  expect(paid.usageFor("t", "<p>x</p>").cost_usd).toBeNull();
  const local = new UsageMeter();
  local.billing = "free";
  local.record("draft", { input: 1, output: 1 });
  expect(local.usageFor("t", "<p>x</p>").cost_usd).toBe(0);
});

it("adds runs to the month ledger, rolls over and counts unknown cost", () => {
  const a = new UsageMeter(); a.record("draft", { input: 1, output: 1, cost: 1 });
  const b = new UsageMeter(); b.record("draft", { input: 1, output: 1 });
  let ledger = addToLedger({}, a, true, new Date(2026, 10, 3));
  ledger = addToLedger(ledger, b, true, new Date(2026, 10, 20));
  expect(ledger["2026-11"]).toEqual({ notules: 2, requests: 2, cost_usd: 1, unknown_cost_runs: 1 });
  ledger = addToLedger(ledger, a, false, new Date(2026, 11, 1));
  expect(ledger["2026-12"]).toEqual({ notules: 0, requests: 1, cost_usd: 1, unknown_cost_runs: 0 });
  expect(ledger["2026-11"].notules).toBe(2);
});

const base: NotuleUsage = { provider: "openrouter", model: "mistralai/mistral-large-4-0", billing: "metered", transcript_chars: 9000, notule_chars: 2430,
  words: 380, sentences: 30, requests: 33, unknown_requests: 0, input_tokens: 1, output_tokens: 1, reasoning_tokens: 0, cost_usd: 0.0814,
  duration_ms: 72_000, steps: {}, content_check: "ran" };

it("formats the footer per provider case", () => {
  expect(usageLine(base, "<p>x</p>")).toBe("2.430 tekens · 380 woorden · 33 verzoeken · ongeveer € 0,07 · 1 min 12 s · OpenRouter, mistral-large-4-0");
  expect(usageLine({ ...base, cost_usd: 0.001 }, "")).toContain("minder dan € 0,01");
  expect(usageLine({ ...base, provider: "openai", model: "gpt-x", billing: "unpriced", cost_usd: null }, "")).toContain("kosten niet bekend in de app");
  expect(usageLine({ ...base, provider: "lm-studio", model: "m", billing: "free", cost_usd: 0 }, "")).toContain("gratis, op deze pc");
  expect(usageLine({ ...base, provider: "ollama", model: "m", billing: "subscription", cost_usd: 0 }, "")).toContain("via je Ollama-abonnement");
  expect(usageLine({ ...base, content_check: "skipped" }, "")).toMatch(/niet automatisch gecontroleerd$/);
  expect(usageLine(undefined, "<p>Een twee drie</p>")).toBe("13 tekens · 3 woorden");
  expect(formatEuro(0)).toBe("minder dan € 0,01");
});

beforeEach(() => {
  invoke.mockReset();
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "lm-studio", lm_studio_url: "http://localhost:1234", lm_studio_model: "m", usage_ledger: {}, notulen_fallback_provider: "" });
});

it("counts a failed request as unknown usage and records the run in the ledger", async () => {
  invoke.mockImplementation(async (command: string) => {
    if (command !== "proxy_request") return undefined;
    return { status: 500, body: "" };
  });
  const meter = new UsageMeter();
  await expect(LLMService.generateNotulen("tekst", { id: "p", name: "P" }, undefined, [], "", undefined, meter)).rejects.toThrow();
  expect(meter.requestCount).toBeGreaterThan(0);
  const [month] = Object.values(useSettingsStore.getState().usage_ledger);
  expect(month).toMatchObject({ notules: 0 });
  expect(month.requests).toBe(meter.requestCount);
});

it("reads usage from the response and writes it to the log end line", async () => {
  invoke.mockImplementation(async (command: string) => {
    if (command !== "proxy_request") return undefined;
    return { status: 200, body: JSON.stringify({ choices: [{ message: { content: "klaar" } }], usage: { prompt_tokens: 12, completion_tokens: 4 } }) };
  });
  expect(await LLMService.complete("s", "u", { kind: "draft" })).toBe("klaar");
  const lines = invoke.mock.calls.filter(([c]) => c === "log_write").map(([, a]) => (a as { message: string }).message);
  expect(lines.at(-1)).toMatch(/outcome=ok in_tok=12 out_tok=4 reason_tok=0$/);
});
