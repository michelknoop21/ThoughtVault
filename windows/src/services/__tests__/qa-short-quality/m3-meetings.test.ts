// Opt-in recorder for the three fictional M3 meetings (ThoughtVaultTests/Fixtures/M3LiveContentGate.json).
// Runs the production LLMService.generateNotulen (draft, source check, content check) with only the Tauri
// proxy replaced by fetch. Start it through scripts/qa/record-m3-windows-meetings.sh; skipped otherwise.
//   TV_M3_MODE=dry-run  no network: replays the fixture's recorded answers and prints prompt hashes.
//   TV_M3_MODE=record   at most 3 requests per meeting (9 in total), no retries; key from VAULT_VALUE.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { expect, it, vi } from "vitest";
import { LLMService } from "../../llm";
import { SOURCE_WARNING_HEADING } from "../../titleExtractor";
import { useSettingsStore } from "../../../stores/settingsStore";

const mode = process.env.TV_M3_MODE;
const key = mode === "record" ? process.env.VAULT_VALUE ?? "" : "m3-dry-run-fake-key";
type ProxyRequest = { url: string; headers: Record<string, string>; body: string; timeout_seconds: number };
let transport: (request: ProxyRequest) => Promise<{ status: number; body: string }> = async () => { throw new Error("QA: no transport"); };
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (command: string, args: { request: ProxyRequest }) => command === "log_write" ? Promise.resolve()
    : command === "proxy_request" ? transport(args.request) : Promise.reject(new Error(`QA: unexpected ${command}`)),
}));
vi.mock("../../tauriCommands", () => ({ loadCredential: async () => key }));
vi.mock("../../../stores/personalCorrectionsStore", () => ({
  usePersonalCorrectionsStore: { getState: () => ({ hydrate: async () => {}, entries: [] }) }, loadCorrectionsOrEmpty: async () => [],
}));

const sha256 = (text: string) => createHash("sha256").update(text, "utf8").digest("hex");
/** Fixture order per meeting: draft, source check, content check. */
const KINDS = ["draft", "source", "content"] as const;
const kindOf = (user: string) => user.startsWith("Broncontrole") ? "source" : user.startsWith("Inhoudsaudit") ? "content" : "draft";
const PER_MEETING = 3;

it.runIf(mode === "dry-run" || mode === "record")("records the M3 meetings through the production Windows generator", async () => {
  const fixturePath = process.env.TV_M3_FIXTURE, dir = process.env.TV_M3_DIR;
  if (!fixturePath || !dir) throw new Error("TV_M3_FIXTURE and TV_M3_DIR are required");
  if (!key) throw new Error("VAULT_VALUE is empty: start via vault-exec OLLAMA_CLOUD_API");
  if (mode === "record" && existsSync(dir)) throw new Error(`${dir} exists; evidence is never overwritten`);
  const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));
  // TV_M3_ONLY re-records a single meeting; the other meetings keep their recorded exchanges.
  const only = process.env.TV_M3_ONLY;
  const meetings = fixture.meetings.filter((m: { name: string }) => !only || m.name === only);
  if (!meetings.length) throw new Error(`QA: no meeting named ${only}`);
  const cap = meetings.length * PER_MEETING;
  useSettingsStore.setState({ notulen_provider: "ollama", ollama_url: fixture.baseURL, ollama_model: fixture.model });
  // Same prompts as the macOS gate (Profile with the fixture prompts, no template). An id without a bundled
  // template keeps enrichProfile from replacing them.
  const profile = { id: "m3-fixture", name: "Standaard", system_prompt: fixture.profile.systemPrompt, notule_prompt: fixture.profile.notulePrompt };

  type Exchange = { meeting: string; n: number; kind: string; system: string; user: string; body: string; status?: number; response?: string; error?: string };
  const exchanges: Exchange[] = [];
  let current = { name: "", windows: [] as { response: string }[] };
  let stopped = false;
  transport = async request => {
    const body = JSON.parse(request.body);
    const [system, user] = body.messages.map((message: { content: string }) => message.content);
    const n = exchanges.filter(e => e.meeting === current.name).length + 1;
    const exchange: Exchange = { meeting: current.name, n, kind: kindOf(user), system, user, body: request.body };
    // Hard cap and no retries: after any failure nothing more leaves this machine.
    if (stopped || exchanges.length >= cap || n > PER_MEETING) throw new Error("QA: request cap or earlier failure, not sent");
    exchanges.push(exchange);
    if (mode === "dry-run") {
      const content = current.windows[KINDS.indexOf(exchange.kind as typeof KINDS[number])].response;
      exchange.status = 200;
      exchange.response = JSON.stringify({ model: fixture.model, choices: [{ index: 0, message: { role: "assistant", content }, finish_reason: "stop" }] });
      return { status: 200, body: exchange.response };
    }
    try {
      const response = await fetch(request.url, { method: "POST", headers: request.headers, body: request.body,
        signal: AbortSignal.timeout(request.timeout_seconds * 1000) });
      exchange.status = response.status;
      exchange.response = await response.text();
    } catch (error) {
      exchange.error = error instanceof Error ? error.message : String(error);
    }
    if (exchange.status !== 200) stopped = true;
    if (exchange.error) throw new Error(exchange.error);
    return { status: exchange.status!, body: exchange.response! };
  };

  const results = [];
  for (const meeting of meetings) {
    current = meeting;
    let html = "", error = "";
    try { html = await LLMService.generateNotulen(meeting.source, profile, undefined, [], ""); } catch (e) { error = e instanceof Error ? e.message : String(e); }
    results.push({ name: meeting.name, html, error, verdict: error ? "generation_failed" : html.includes(SOURCE_WARNING_HEADING) ? "review" : "accepted" });
  }

  const ordered = (name: string) => KINDS.map(kind => exchanges.find(e => e.meeting === name && e.kind === kind));
  if (mode === "dry-run") {
    const rows = meetings.flatMap((meeting: { name: string; windows: { systemSha256: string; userSha256: string }[] }) =>
      ordered(meeting.name).map((e, i) => e && {
        exchange: `${meeting.name}[${i}] ${e.kind}`, systemSha256: sha256(e.system), userSha256: sha256(e.user),
        systemChars: e.system.length, userChars: e.user.length,
        matchesFixture: sha256(e.system) === meeting.windows[i].systemSha256 && sha256(e.user) === meeting.windows[i].userSha256,
      }));
    process.stdout.write(`M3_DRY_RUN ${JSON.stringify({ requests: exchanges.length, cap, rows, verdicts: results.map(r => `${r.name}: ${r.verdict}`) }, null, 1)}` + "\n");
    expect(exchanges.length).toBe(cap);
    return;
  }

  // Raw evidence first, also after a failure: requests are bodies only (the key is a header and never stored).
  mkdirSync(dir, { recursive: true });
  const written: string[] = [];
  const write = (name: string, text: string) => { writeFileSync(resolve(dir, name), text, { flag: "wx" }); written.push(name); };
  const modelText = (raw?: string) => { try { return JSON.parse(raw ?? "").choices?.[0]?.message?.content; } catch { return undefined; } };
  const modelId = (raw?: string) => { try { return JSON.parse(raw ?? "").model; } catch { return undefined; } };
  for (const e of exchanges) {
    const label = `${e.meeting}-${e.n}`;
    write(`${label}.request.json`, e.body);
    write(`${label}.response.json`, e.error ? `TRANSPORT ERROR: ${e.error}\n` : e.response ?? "");
    const text = modelText(e.response);
    if (typeof text === "string") write(`${label}.response.txt`, text);
  }
  for (const r of results) {
    const meeting = fixture.meetings.find((m: { name: string }) => m.name === r.name);
    write(`${r.name}.result.json`, JSON.stringify({
      name: r.name, source: meeting.source, scope: "Production Windows LLMService.generateNotulen, Tauri proxy replaced by fetch; no native recording/UI acceptance",
      model: fixture.model, html: r.html, verdict: r.verdict, error: r.error,
      exchanges: exchanges.filter(e => e.meeting === r.name).map(e => ({ label: `${e.meeting}-${e.n}`, kind: e.kind, status: e.status ?? null, model: modelId(e.response) ?? null })),
    }, null, 2) + "\n");
  }
  write("artifact-manifest.json", JSON.stringify(written.map(path => {
    const data = readFileSync(resolve(dir, path));
    return { path, sha256: createHash("sha256").update(data).digest("hex"), length: data.length };
  }), null, 2) + "\n");

  // Never keep anything that contains the key.
  if (written.some(name => readFileSync(resolve(dir, name), "utf8").includes(key))) {
    rmSync(dir, { recursive: true, force: true });
    throw new Error("QA: evidence contained the API key and was deleted");
  }

  const problems = [
    ...(exchanges.length === cap ? [] : [`${exchanges.length} of ${cap} requests sent`]),
    ...exchanges.filter(e => e.status !== 200).map(e => `${e.meeting}-${e.n}: ${e.error ?? `HTTP ${e.status}`}`),
    ...exchanges.filter(e => modelId(e.response) !== fixture.model).map(e => `${e.meeting}-${e.n}: model ${modelId(e.response)}`),
    // An empty content (answer only in `reasoning`) is no usable model text, as in production.
    ...exchanges.filter(e => !modelText(e.response)?.trim()).map(e => `${e.meeting}-${e.n}: no model text`),
    ...results.filter(r => r.error).map(r => `${r.name}: ${r.error}`),
    ...meetings.filter((m: { name: string }) => ordered(m.name).some(e => !e)).map((m: { name: string }) => `${m.name}: not one draft, source and content check`),
  ];
  if (problems.length) throw new Error(`QA: fixture not updated: ${problems.join("; ")}`);

  for (const meeting of meetings) {
    meeting.windows = ordered(meeting.name).map(e => ({ systemSha256: sha256(e!.system), userSha256: sha256(e!.user), response: modelText(e!.response) }));
  }
  const updated = JSON.stringify(fixture, null, 1);
  if (updated.includes(key)) throw new Error("QA: fixture would contain the API key");
  writeFileSync(fixturePath, updated);
  process.stdout.write(`M3_RECORDED ${JSON.stringify({ dir, requests: exchanges.length, verdicts: results.map(r => `${r.name}: ${r.verdict}`) })}` + "\n");
}, 100 * 60_000);
