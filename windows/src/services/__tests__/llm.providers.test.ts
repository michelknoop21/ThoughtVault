import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService, MAX_OUTPUT_TOKENS, TIME_LIMIT_MESSAGE, TRUNCATED_MESSAGE, auditNoteConcurrency, rateLimitWaitMs } from "../llm";
import { auditFixture, sourceFixture } from "./notuleAuditFixtures";

const corrections = vi.hoisted(() => ({entries:[] as import("../personalCorrections").PersonalCorrection[]}));
const { loadCredential } = vi.hoisted(() => ({ loadCredential: vi.fn() }));
const { invoke, auditInvoke } = vi.hoisted(() => ({ invoke: vi.fn(), auditInvoke: vi.fn() }));
vi.mock("../../stores/personalCorrectionsStore", () => ({ usePersonalCorrectionsStore: { getState: () => ({hydrate:async () => {},entries:corrections.entries}) }, loadCorrectionsOrEmpty: async () => corrections.entries }));
vi.mock("../tauriCommands", () => ({ loadCredential }));
// Keep generation transport assertions separate from the source and factual audits.
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => {
  // Log lines per model request are tested in modelRequestLog.test.ts; `invoke` counts model requests here.
  if (args[0] === "log_write") return Promise.resolve();
  const request = (args[1] as { request?: { body?: string } })?.request;
  const messages = request?.body ? JSON.parse(request.body).messages : [];
  if (messages.at(-1)?.content.startsWith("Broncontrole")) {
    const content = sourceFixture(messages.at(-1).content);
    return Promise.resolve({ status: 200, body: JSON.stringify({ choices: [{ message: { content } }], content: [{ type: "text", text: content }] }) });
  }
  return messages.at(-1)?.content.startsWith("Inhoudsaudit (geen generatie):") ? auditInvoke(...args) : invoke(...args);
} }));

const profile = {
  id: "custom",
  name: "Test",
  system_prompt: "Maak nauwkeurige notulen.",
  notule_prompt: "Notuleer: {{TRANSCRIPTION}}\n{{OUTPUT_TEMPLATE}}",
  output_template: "<h1>Titel</h1>",
};

beforeEach(() => {
  vi.resetAllMocks();
  corrections.entries = [];
  auditInvoke.mockImplementation(async (_command, args) => {
    const content = auditFixture(JSON.parse(args.request.body).messages.at(-1).content);
    return { status: 200, body: JSON.stringify({ choices: [{ message: { content } }], content: [{ type: "text", text: content }] }) };
  });
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama" });
});

it.each(["ollama", "lm-studio"] as const)("uses the native route for %s when WebView CORS is denied", async provider => {
  useSettingsStore.setState({ notulen_provider: provider, ollama_url: "http://localhost:11434/v1/", ollama_model: "hermes3:8b", lm_studio_url: "http://localhost:1234/v1/", lm_studio_model: "local-model" });
  const fetchMock = vi.fn().mockRejectedValue(new TypeError("Failed to fetch"));
  vi.stubGlobal("fetch", fetchMock);
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Het overleg is afgerond.</p>" } }] }) });
  const progress = vi.fn();
  try {
    expect(await LLMService.generateNotulen("Het overleg is afgerond.", profile, progress)).toBe("<p>Het overleg is afgerond.</p>");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(loadCredential).not.toHaveBeenCalled();
    expect(invoke).toHaveBeenCalledWith("proxy_request", expect.objectContaining({ request: expect.objectContaining({
      url: provider === "ollama" ? "http://localhost:11434/v1/chat/completions" : "http://localhost:1234/v1/chat/completions",
      headers: { "Content-Type": "application/json" }, timeout_seconds: 900,
    }) }));
    expect(progress).toHaveBeenCalledWith("<p>Het overleg is afgerond.</p>");
  } finally { vi.unstubAllGlobals(); }
});

it("generates Ollama Cloud notes through the native proxy instead of WebView fetch", async () => {
  useSettingsStore.setState({ ollama_url: "https://ollama.com/v1/", ollama_model: "gpt-oss:120b" });
  loadCredential.mockResolvedValue("test-cloud-key");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>QA besluit</p>" } }] }) });
  expect(await LLMService.generateNotulen("QA test.", profile)).toBe("<p>QA besluit</p>");
  const request = invoke.mock.calls[0][1].request;
  expect(request.url).toBe("https://ollama.com/v1/chat/completions");
  expect(request.headers.Authorization).toBe("Bearer test-cloud-key");
  expect(JSON.parse(request.body).stream).toBe(false);
});

it.each([401, 500])("keeps local provider HTTP %s visible without reporting completed notes", async status => {
  useSettingsStore.setState({ ollama_url: "http://localhost:11434", ollama_model: "hermes3:8b" });
  invoke.mockResolvedValue({ status, body: "{}" });
  const progress = vi.fn();
  await expect(LLMService.generateNotulen("QA bron.", profile, progress)).rejects.toThrow(`HTTP ${status}`);
  expect(invoke).toHaveBeenCalledTimes(1);
  expect(progress).not.toHaveBeenCalled();
});

it("names the configured local provider when its native request fails", async () => {
  useSettingsStore.setState({ ollama_url: "http://localhost:11434", ollama_model: "hermes3:8b" });
  invoke.mockRejectedValue("connection refused");
  await expect(LLMService.generateNotulen("QA bron.", profile)).rejects.toThrow('http://localhost:11434 (model "hermes3:8b")');
  expect(invoke).toHaveBeenCalledTimes(1);
});

describe("HTTP 429", () => {
  const notes = { status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Akkoord</p>" } }] }) };
  beforeEach(() => {
    vi.useFakeTimers();
    vi.spyOn(Math, "random").mockReturnValue(0);
    useSettingsStore.setState({ notulen_provider: "openai" as never });
    loadCredential.mockResolvedValue("openai-secret");
  });
  afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

  it("retries once after the Retry-After wait, within the same time limit", async () => {
    invoke.mockResolvedValueOnce({ status: 429, body: "{}", headers: { "retry-after": "7" } }).mockResolvedValueOnce(notes);
    const result = LLMService.generateNotulen("Akkoord.", profile);
    await vi.advanceTimersByTimeAsync(6_999);
    expect(invoke).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    await expect(result).resolves.toBe("<p>Akkoord</p>");
    expect(invoke).toHaveBeenCalledTimes(2);
    expect(invoke.mock.calls[1][1].request.timeout_seconds).toBe(893);
  });

  it("fails on a second 429 with the rate-limit message", async () => {
    invoke.mockResolvedValue({ status: 429, body: "{}" });
    const result = expect(LLMService.generateNotulen("Akkoord.", profile)).rejects.toThrow("OpenAI API-limiet bereikt (429), ook na een nieuwe poging");
    await vi.advanceTimersByTimeAsync(2_000);
    await result;
    expect(invoke).toHaveBeenCalledTimes(2);
  });

  it("does not wait for a Retry-After above the cap", async () => {
    invoke.mockResolvedValueOnce({ status: 429, body: "{}", headers: { "Retry-After": "120" } }).mockResolvedValueOnce(notes);
    await expect(LLMService.generateNotulen("Akkoord.", profile)).rejects.toThrow("API-limiet bereikt (429)");
    expect(invoke).toHaveBeenCalledTimes(1);
  });

  it("does not retry a server error", async () => {
    invoke.mockResolvedValueOnce({ status: 500, body: "{}" }).mockResolvedValueOnce(notes);
    await expect(LLMService.generateNotulen("Akkoord.", profile)).rejects.toThrow("HTTP 500");
    expect(invoke).toHaveBeenCalledTimes(1);
  });

  it("reads Retry-After as seconds or as an HTTP date", () => {
    const now = Date.parse("Wed, 21 Oct 2015 07:28:00 GMT");
    expect(rateLimitWaitMs("Wed, 21 Oct 2015 07:28:10 GMT", now)).toBe(10_000);
    expect(rateLimitWaitMs("Wed, 21 Oct 2015 07:27:00 GMT", now)).toBe(0);
    expect(rateLimitWaitMs("30")).toBe(30_000);
    expect(rateLimitWaitMs("31")).toBeNull();
    for (const value of [undefined, "soon", "-5", "1.5"]) expect(rateLimitWaitMs(value)).toBe(2_000);
  });
});

it("gives only hosted providers the higher step-2 limit", () => {
  expect(auditNoteConcurrency("openai", "http://localhost:1234")).toBe(8);
  expect(auditNoteConcurrency("anthropic", "http://localhost:1234")).toBe(8);
  expect(auditNoteConcurrency("ollama", "https://ollama.com")).toBe(8);
  expect(auditNoteConcurrency("lm-studio", "https://llm.example.com/v1")).toBe(8);
  expect(auditNoteConcurrency("ollama", "http://localhost:11434")).toBe(4);
  expect(auditNoteConcurrency("lm-studio", "https://192.168.1.10:1234")).toBe(4);
});

it("names a timeout as the time limit instead of an unreachable generator", async () => {
  useSettingsStore.setState({ ollama_url: "http://localhost:11434", ollama_model: "hermes3:8b" });
  invoke.mockRejectedValue("Tijdslimiet bereikt: geen volledig antwoord binnen 900 seconden.");
  await expect(LLMService.generateNotulen("QA bron.", profile)).rejects.toThrow(TIME_LIMIT_MESSAGE);
});

it("caps the output and rejects an answer cut off at the cap", async () => {
  useSettingsStore.setState({ ollama_url: "http://localhost:11434", ollama_model: "hermes3:8b" });
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ finish_reason: "length", message: { content: "<p>Het overleg is afgerond en</p>" } }] }) });
  await expect(LLMService.generateNotulen("Het overleg is afgerond.", profile)).rejects.toThrow(TRUNCATED_MESSAGE);
  expect(JSON.parse(invoke.mock.calls[0][1].request.body).max_tokens).toBe(MAX_OUTPUT_TOKENS);

  useSettingsStore.setState({ notulen_provider: "openai" as never });
  loadCredential.mockResolvedValue("openai-secret");
  invoke.mockClear();
  await expect(LLMService.generateNotulen("Het overleg is afgerond.", profile)).rejects.toThrow(TRUNCATED_MESSAGE);
  const body = JSON.parse(invoke.mock.calls[0][1].request.body);
  expect(body.max_completion_tokens).toBe(MAX_OUTPUT_TOKENS);
  expect(body.max_tokens).toBeUndefined();

  useSettingsStore.setState({ notulen_provider: "anthropic" as never });
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ stop_reason: "max_tokens", content: [{ type: "text", text: "<p>Het overleg is afgerond en</p>" }] }) });
  await expect(LLMService.generateNotulen("Het overleg is afgerond.", profile)).rejects.toThrow(TRUNCATED_MESSAGE);
});

it("reports a rejected Ollama Cloud key and never masks it as a local server failure", async () => {
  useSettingsStore.setState({ ollama_url: "https://ollama.com" });
  loadCredential.mockResolvedValue("test-cloud-key");
  invoke.mockResolvedValue({ status: 401, body: "{}" });
  await expect(LLMService.generateNotulen("QA test.", profile)).rejects.toThrow("API-sleutel geweigerd");
  invoke.mockClear(); loadCredential.mockResolvedValue(null);
  await expect(LLMService.generateNotulen("QA test.", profile)).rejects.toThrow("Vul je Ollama Cloud API-sleutel");
  expect(invoke).not.toHaveBeenCalled();
});

it("uses the user's OpenAI API key for the selected profile and transcript", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" as never });
  loadCredential.mockResolvedValue("openai-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<h1>Besluit</h1>" } }] }) });

  const html = await LLMService.generateNotulen("De planning is goedgekeurd.", profile);

  expect(html).toBe("<h1>Besluit</h1>");
  expect(loadCredential).toHaveBeenCalledWith("openai_api_key");
  const request = invoke.mock.calls[0][1].request;
  expect(request.url).toBe("https://api.openai.com/v1/chat/completions");
  expect(request.headers.Authorization).toBe("Bearer openai-secret");
  expect(JSON.parse(request.body).messages[1].content).toContain("De planning is goedgekeurd.");
  expect(JSON.parse(request.body).messages[1].content).toContain("<h1>Titel</h1>");
});

it("uses the user's Anthropic API key through the Messages API", async () => {
  useSettingsStore.setState({ notulen_provider: "anthropic" as never });
  loadCredential.mockResolvedValue("anthropic-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ content: [{ type: "text", text: "<p>Akkoord</p>" }] }) });

  const html = await LLMService.generateNotulen("Akkoord.", profile);

  expect(html).toBe("<p>Akkoord</p>");
  expect(loadCredential).toHaveBeenCalledWith("anthropic_api_key");
  const request = invoke.mock.calls[0][1].request;
  expect(request.url).toBe("https://api.anthropic.com/v1/messages");
  expect(request.headers["x-api-key"]).toBe("anthropic-secret");
  expect(JSON.parse(request.body).messages[0].content).toContain("Akkoord.");
});

it("does not send a hosted request without the selected provider's key", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" as never });
  loadCredential.mockResolvedValue(null);

  await expect(LLMService.generateNotulen("Akkoord.", profile)).rejects.toThrow("API-sleutel");
  expect(invoke).not.toHaveBeenCalled();
});

it("passes quick notes as separate user context while preserving the transcript", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("openai-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Besluit</p>" } }] }) });
  await LLMService.generateNotulen("De planning is goedgekeurd.", profile, undefined, [], "Let op het budget.");
  const content = JSON.parse(invoke.mock.calls[0][1].request.body).messages[1].content;
  expect(content).toContain("context, geen onderdeel van de transcriptie");
  expect(content).toContain("Let op het budget.");
  expect(content).toContain("De planning is goedgekeurd.");
  expect(content).toContain("<h2>Notities</h2>");
});

it("appends the raw note as a Notities section when the model left it out", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("openai-secret");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Besluit</p>" } }] }) });
  const html = await LLMService.generateNotulen("Akkoord.", profile, undefined, [], "Let op het budget.");
  expect(html).toBe("<p>Besluit</p><h2>Notities</h2><p>Let op het budget.</p>");
});

it("corrects derived provider input and returned HTML without changing the raw transcript", async () => {
  corrections.entries = [{id:"brand",canonical:"Yinga",variants:["Jengo","Django"],scope:"custom",enabled:true}];
  useSettingsStore.setState({notulen_provider:"openai"});
  loadCredential.mockResolvedValue("test-key");
  invoke.mockResolvedValue({status:200,body:JSON.stringify({choices:[{message:{content:'<p title="Django">Django</p><code>Django</code>'}}]})});
  const raw = "Jengo bespreekt de planning.";
  const html = await LLMService.generateNotulen(raw,profile);
  const messages = JSON.parse(invoke.mock.calls[0][1].request.body).messages;
  expect(messages[1].content).toContain("- Yinga (ook gehoord als: Jengo, Django)");
  expect(messages[1].content).toContain("Yinga bespreekt de planning.");
  expect(html).toBe('<p title="Django">Yinga</p><code>Django</code>');
  expect(raw).toBe("Jengo bespreekt de planning.");
});

it("summarizes every part of a long meeting before applying the profile without splitting Unicode", async () => {
  useSettingsStore.setState({ ollama_url: "http://localhost:11434", ollama_model: "unknown-small-context" });
  loadCredential.mockResolvedValue("test-key");
  const raw = "START " + "a".repeat(7993) + "😀 MIDDLE " + "b".repeat(8000) + " END";
  invoke.mockImplementation(async (_command, args) => {
    const content = JSON.parse(args.request.body).messages[1].content;
    const summary = content.includes("Vat dit deel compact samen:")
      ? ["START", "MIDDLE", "END"].filter(marker => content.includes(marker)).join(" ")
      : "<p>START MIDDLE END</p>";
    return { status: 200, body: JSON.stringify({ choices: [{ message: { content: summary } }] }) };
  });
  const progress = vi.fn();
  expect(await LLMService.generateNotulen(raw, profile, progress, ["Alex"], "Budget controleren")).toContain("START MIDDLE END");
  const messages = invoke.mock.calls.map(call => JSON.parse(call[1].request.body).messages);
  expect(messages.slice(0, -1).every(pair => pair[0].content.includes("ontkenningen, verboden, voorwaarden en vervallen afspraken"))).toBe(true);
  const contents = messages.map(pair => pair[1].content);
  const chunks = contents.slice(0, -1).map(content => content.split("Vat dit deel compact samen:\n\n")[1]);
  expect(chunks.join("")).toBe(raw);
  expect(chunks.every(chunk => Array.from(chunk).length <= 8000)).toBe(true);
  expect(contents.at(-1)).toContain("Alex");
  expect(contents.at(-1)).toContain("Budget controleren");
  expect(contents.at(-1)).toContain("<h1>Titel</h1>");
  expect(progress).toHaveBeenCalledTimes(1);
});

it("retains the hosted GPT-OSS context allowance instead of creating unnecessary chunk requests", async () => {
  useSettingsStore.setState({ ollama_url: "https://ollama.com", ollama_model: "gpt-oss:120b" });
  loadCredential.mockResolvedValue("test-key");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Akkoord</p>" } }] }) });
  await LLMService.generateNotulen("a".repeat(9000), profile);
  expect(invoke).toHaveBeenCalledTimes(1);
  expect(invoke.mock.calls.every(call => !JSON.parse(call[1].request.body).messages[1].content.includes("Vat dit deel compact samen:"))).toBe(true);
});

it("gives every hosted model the large context allowance, not only GPT-OSS", async () => {
  useSettingsStore.setState({ ollama_url: "https://ollama.com", ollama_model: "mistral-large-4" });
  loadCredential.mockResolvedValue("test-key");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Akkoord</p>" } }] }) });
  await LLMService.generateNotulen("a".repeat(9000), profile);
  expect(invoke).toHaveBeenCalledTimes(1);
});

it("stops without silently truncating a long meeting when the model does not shorten its chunks", async () => {
  useSettingsStore.setState({ ollama_url: "http://localhost:11434", ollama_model: "unknown-small-context" });
  loadCredential.mockResolvedValue("test-key");
  invoke.mockImplementation(async (_command, args) => ({ status: 200, body: JSON.stringify({ choices: [{ message: {
    content: JSON.parse(args.request.body).messages[1].content.split("Vat dit deel compact samen:\n\n")[1],
  } }] }) }));
  await expect(LLMService.generateNotulen("a".repeat(9000), profile)).rejects.toThrow("transcriptie is bewaard");
  expect(invoke).toHaveBeenCalledTimes(2);
});


it.each(["ollama", "lm-studio", "openai", "anthropic"] as const)("preserves decision constraints in the %s generation request", async provider => {
  useSettingsStore.setState({ notulen_provider: provider, ollama_url: "https://ollama.com", ollama_model: "gpt-oss:120b" });
  loadCredential.mockResolvedValue("test-key");
  const raw = "Het onderhoudscontract is niet verlengd. Tot akkoord geen bestelling plaatsen. De datum van donderdag vervalt. Uitgenodigde Kim was afwezig. Over wissen is niets besloten.";
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: `<p>${raw}</p>` } }], content: [{ type: "text", text: `<p>${raw}</p>` }] }) });
  const fetchMock = vi.fn(async (_url: string, _options?: RequestInit) => new Response(`data: ${JSON.stringify({choices:[{delta:{content:`<p>${raw}</p>`}}]})}\n\n`));
  vi.stubGlobal("fetch", fetchMock);
  try {
    await LLMService.generateNotulen(raw, profile);
    const request = JSON.parse(invoke.mock.calls[0][1].request.body);
    const prompt = request.messages.at(-1).content;
    const system = provider === "anthropic" ? request.system : request.messages[0].content;
    expect(system).toContain(profile.system_prompt);
    expect(system).toContain("Brongetrouwheid gaat vóór beknoptheid");
    expect(system).toContain("Vermeld ieder expliciet vervallen tijdstip");
    expect(system).toContain("geen besluit over uitvoering");
    expect(prompt).toContain(raw);
    expect(prompt).toContain("ontkenningen, verboden, voorwaarden en vervallen afspraken");
    expect(prompt).toContain("uitnodiging is geen aanwezigheid");
    expect(prompt).toContain("open vraag is geen besluit");
    expect(prompt).toContain("Controleer vóór het antwoorden");
  } finally { vi.unstubAllGlobals(); }
});

it.each(["ollama", "lm-studio", "openai", "anthropic"] as const)("flags an audited contradictory %s draft in the notule (DEC-063)", async provider => {
  useSettingsStore.setState({ notulen_provider: provider, ollama_url: "https://ollama.com", ollama_model: "gpt-oss:120b" });
  loadCredential.mockResolvedValue("test-key");
  const raw = "Het contract is niet verlengd. De datum van donderdag vervalt. Kim was afwezig.";
  const draft = "<p>Het contract loopt door. Donderdag blijft staan. Kim was aanwezig.</p>";
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: draft } }], content: [{ type: "text", text: draft }] }) });
  auditInvoke.mockImplementation(async (_command, args) => {
    const content = auditFixture(JSON.parse(args.request.body).messages.at(-1).content, "contradiction");
    return { status: 200, body: JSON.stringify({ choices: [{ message: { content } }], content: [{ type: "text", text: content }] }) };
  });
  const progress = vi.fn();
  expect(await LLMService.generateNotulen(raw, profile, progress)).toContain("<h2>Even nalopen</h2>");
  expect(progress).toHaveBeenCalledOnce();
  expect(JSON.parse(invoke.mock.calls[0][1].request.body).messages.at(-1).content).toContain(raw);
});

it("returns the notule with the general warning when the factual audit is unavailable", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("test-key");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Concept</p>" } }] }) });
  auditInvoke.mockResolvedValue({ status: 500, body: "{}" });
  const progress = vi.fn();
  expect(await LLMService.generateNotulen("QA bron.", profile, progress)).toContain("<h2>Even nalopen</h2>");
  expect(progress).toHaveBeenCalledOnce();
  expect(invoke).toHaveBeenCalledTimes(1);
});

it("does not ask the checker to invent notes from an empty draft", async () => {
  useSettingsStore.setState({ notulen_provider: "lm-studio" });
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "" } }] }) });
  await expect(LLMService.generateNotulen("QA bron.", profile)).rejects.toThrow("leeg concept");
  expect(invoke).toHaveBeenCalledTimes(1);
});

it("flags a checked note that still omits an explicit constraint", async () => {
  auditInvoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: JSON.stringify({ source: [], notes: [], uncertain: true }) } }] }) });
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("test-key");
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Het overleg is afgerond.</p>" } }] }) });
  const progress = vi.fn();
  expect(await LLMService.generateNotulen("De afspraak voor donderdag vervalt.", profile, progress)).toContain("<h2>Even nalopen</h2>");
  expect(progress).toHaveBeenCalledOnce();
});

it("flags constraints hidden in CSS as unchecked note content", async () => {
  auditInvoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: JSON.stringify({ source: [], notes: [], uncertain: true }) } }] }) });
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("test-key");
  const raw = "Er is geen besluit over archivering genomen.";
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: `<style>/* ${raw} */</style><p>De archivering is besloten.</p>` } }] }) });
  expect(await LLMService.generateNotulen(raw, profile)).toContain("<h2>Even nalopen</h2>");
});

describe("fallback provider", () => {
  const okAnthropic = { status: 200, body: JSON.stringify({ content: [{ type: "text", text: "<p>Terugval besluit</p>" }] }) };
  const setup = (fallback: "" | "anthropic") => {
    useSettingsStore.setState({ notulen_provider: "ollama", notulen_fallback_provider: fallback, ollama_url: "http://localhost:11434", ollama_model: "hermes3:8b" });
    loadCredential.mockResolvedValue("key");
    invoke.mockImplementation(async (_c, args) => String(args.request.url).includes("anthropic")
      ? okAnthropic : { status: 500, body: "{}" });
  };

  it("retries once with the fallback provider and clears streamed text", async () => {
    setup("anthropic");
    const progress = vi.fn();
    expect(await LLMService.generateNotulen("Het overleg is afgerond.", profile, progress)).toBe("<p>Terugval besluit</p>");
    expect(progress).toHaveBeenCalledWith("");
  });

  it("surfaces the original error without a fallback", async () => {
    setup("");
    await expect(LLMService.generateNotulen("Het overleg is afgerond.", profile)).rejects.toThrow("HTTP 500");
  });

  it("does not fall back on abort", async () => {
    setup("anthropic");
    useSettingsStore.setState({ notulen_provider: "openai", notulen_fallback_provider: "anthropic" });
    invoke.mockRejectedValue(new DOMException("aborted", "AbortError"));
    await expect(LLMService.generateNotulen("Het overleg is afgerond.", profile)).rejects.toThrow("aborted");
    expect(invoke).toHaveBeenCalledTimes(1);
  });
});
