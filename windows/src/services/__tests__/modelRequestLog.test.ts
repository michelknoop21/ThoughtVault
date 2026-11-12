import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService } from "../llm";
import { auditNotule } from "../notuleAudit";
import { stepLabel, type ModelStep } from "../modelRequestLog";

// Same checks as ModelRequestLogTests.swift.
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("../tauriCommands", () => ({ loadCredential: vi.fn() }));

const system = "Geheime systeeminstructie";
const user = "Transcriptie: Jan de Vries belt vrijdag de klant over het contract van 40.000 euro.";
let replies: { status: number; headers?: Record<string, string> }[] = [];

/** Lines written to the log file by `log_write`. */
const logged = () => invoke.mock.calls.filter(([command]) => command === "log_write").map(([, args]) => (args as { message: string }).message);

beforeEach(() => {
  invoke.mockReset();
  replies = [];
  invoke.mockImplementation(async (command: string) => {
    if (command !== "proxy_request") return undefined;
    const reply = replies.shift() ?? { status: 200 };
    return { ...reply, body: JSON.stringify({ choices: [{ message: { content: "klaar" } }] }) };
  });
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama", ollama_url: "http://localhost:11434", ollama_model: "test-model:7b" });
});

it("logs metadata per model request and never the text", async () => {
  await LLMService.complete(system, user, { kind: "sentence-check", index: 12, total: 61 });
  const lines = logged();
  expect(lines).toHaveLength(2);
  const head = `step=sentence-check 12/61 provider=local model=test-model:7b input_chars=${system.length + user.length}`;
  expect(lines[0]).toBe(`model request start ${head}`);
  expect(lines[1]).toMatch(new RegExp(`^model request end ${head} ms=\\d+ outcome=ok$`));
  // Only metadata leaves the device in a support report (DEC-064).
  for (const line of lines) {
    for (const word of ["Geheime", "systeeminstructie", "Transcriptie", "Jan", "Vries", "klant", "40.000", "klaar", "11434"]) {
      expect(line, `"${word}" leaked`).not.toContain(word);
    }
  }
});

it("names a failed request's HTTP status and a rate limit retry", async () => {
  replies = [{ status: 503 }];
  await expect(LLMService.complete(system, user, { kind: "draft" })).rejects.toThrow();
  expect(logged().at(-1)).toMatch(/^model request end step=draft .* outcome=HTTP 503$/);

  invoke.mockClear();
  vi.spyOn(Math, "random").mockReturnValue(0);
  replies = [{ status: 429, headers: { "Retry-After": "0" } }];
  await LLMService.complete(system, user, { kind: "coverage", index: 2, total: 3 });
  const lines = logged();
  expect(lines).toHaveLength(3);
  expect(lines[1]).toBe("model request retry step=coverage 2/3 after HTTP 429 wait_ms=0");
  expect(lines[2]).toMatch(/ outcome=ok$/);
  vi.restoreAllMocks();
});

it("counts finished checks of a long audit, rising to the total, and names each request", async () => {
  // Ten notule sentences preserve T391 to T400 of 401 source sentences: two coverage parts, ten checks.
  const source = Array.from({ length: 401 }, (_, i) => `Punt ${i + 1} is besproken.`).join(" ");
  const html = `<p>${Array.from({ length: 10 }, (_, i) => `Punt ${i + 391} is besproken.`).join(" ")}</p>`;
  const named: string[] = [];
  const request = async (_system: string, message: string, step?: ModelStep) => {
    named.push(step ? `${step.kind} ${step.index}/${step.total}` : "none");
    // Random delays make checks finish out of order.
    await new Promise(resolve => setTimeout(resolve, Math.random() * 30));
    const input = JSON.parse(message.slice(message.indexOf("\n") + 1));
    const ids = (key: string) => ((input[key] ?? []) as { id: string }[]).map(unit => unit.id);
    if (message.startsWith("Inhoudsaudit deel")) {
      return JSON.stringify({ uncertain: false, source: ids("source").map(id => {
        const number = Number(id.slice(1));
        return id.startsWith("T") && number >= 391 && number <= 400
          ? { id, status: "covered", evidence: [`N${number - 390}`] } : { id, status: "non_factual", evidence: [] };
      }) });
    }
    return JSON.stringify({ uncertain: false, notes: [{ id: ids("notes")[0], status: "supported", evidence: ids("evidence") }] });
  };
  const progress: ModelStep[] = [];
  await auditNotule(source, html, "", request, [], false, 8, step => progress.push(step));
  expect(progress.filter(step => step.kind === "coverage").map(step => `${step.index}/${step.total}`)).toEqual(["0/2", "1/2", "2/2"]);
  expect(progress.filter(step => step.kind === "sentence-check").map(step => `${step.index}/${step.total}`))
    .toEqual(Array.from({ length: 11 }, (_, i) => `${i}/10`));
  expect(new Set(named)).toEqual(new Set(["coverage 1/2", "coverage 2/2", ...Array.from({ length: 10 }, (_, i) => `sentence-check ${i + 1}/10`)]));
  expect(named).toHaveLength(12);
  expect(stepLabel({ kind: "sentence-check", index: 12, total: 61 })).toBe("Controle 12 van 61");
});
