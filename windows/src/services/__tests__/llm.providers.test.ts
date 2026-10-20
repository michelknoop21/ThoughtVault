import { beforeEach, expect, it, vi } from "vitest";
import { useSettingsStore } from "../../stores/settingsStore";
import { LLMService } from "../llm";

const corrections = vi.hoisted(() => ({entries:[] as import("../personalCorrections").PersonalCorrection[]}));
const { loadCredential } = vi.hoisted(() => ({ loadCredential: vi.fn() }));
const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("../../stores/personalCorrectionsStore", () => ({ usePersonalCorrectionsStore: { getState: () => ({hydrate:async () => {},entries:corrections.entries}) } }));
vi.mock("../tauriCommands", () => ({ loadCredential }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));

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
  useSettingsStore.setState({ processing_mode: "local", notulen_provider: "ollama" });
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
  expect(messages[1].content).toContain("Jengo, Django -> Yinga");
  expect(messages[1].content).toContain("Yinga bespreekt de planning.");
  expect(html).toBe('<p title="Django">Yinga</p><code>Django</code>');
  expect(raw).toBe("Jengo bespreekt de planning.");
});

it("summarizes every part of a long meeting before applying the profile without splitting Unicode", async () => {
  useSettingsStore.setState({ ollama_url: "https://ollama.com", ollama_model: "unknown-small-context" });
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
  const chunks = contents.slice(0, -2).map(content => content.split("Vat dit deel compact samen:\n\n")[1]);
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
  expect(invoke).toHaveBeenCalledTimes(2);
  expect(invoke.mock.calls.every(call => !JSON.parse(call[1].request.body).messages[1].content.includes("Vat dit deel compact samen:"))).toBe(true);
});

it("stops without silently truncating a long meeting when the model does not shorten its chunks", async () => {
  useSettingsStore.setState({ ollama_url: "https://ollama.com", ollama_model: "unknown-small-context" });
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
  invoke.mockResolvedValue({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Besluit</p>" } }], content: [{ type: "text", text: "<p>Besluit</p>" }] }) });
  const fetchMock = vi.fn(async (_url: string, _options?: RequestInit) => new Response('data: {"choices":[{"delta":{"content":"<p>Besluit</p>"}}]}\n\n'));
  vi.stubGlobal("fetch", fetchMock);
  const raw = "Het onderhoudscontract is niet verlengd. Tot akkoord geen bestelling plaatsen. De datum van donderdag vervalt. Uitgenodigde Kim was afwezig. Over wissen is niets besloten.";
  try {
    await LLMService.generateNotulen(raw, profile);
    const request = provider === "lm-studio" ? JSON.parse(fetchMock.mock.calls[0][1]!.body as string) : JSON.parse(invoke.mock.calls[0][1].request.body);
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

it.each(["ollama", "lm-studio", "openai", "anthropic"] as const)("checks the %s draft against its source before returning notes", async provider => {
  useSettingsStore.setState({ notulen_provider: provider, ollama_url: "https://ollama.com", ollama_model: "gpt-oss:120b" });
  loadCredential.mockResolvedValue("test-key");
  const raw = "Het contract is niet verlengd. De datum van donderdag vervalt. Kim was afwezig.";
  const draft = "<p>Het contract loopt door. Donderdag blijft staan. Kim was aanwezig.</p>";
  const checked = "<p>Het contract is niet verlengd. Donderdag vervalt. Kim was afwezig.</p>";
  const requests: { messages: { content: string }[] }[] = [];
  const answer = (request: { messages: { content: string }[] }) => {
    requests.push(request);
    return requests.length === 1 ? draft : checked;
  };
  invoke.mockImplementation(async (_command, args) => {
    const content = answer(JSON.parse(args.request.body));
    return { status: 200, body: JSON.stringify({ choices: [{ message: { content } }], content: [{ type: "text", text: content }] }) };
  });
  vi.stubGlobal("fetch", vi.fn(async (_url: string, options: RequestInit) => {
    const content = answer(JSON.parse(options.body as string));
    return new Response(`data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`);
  }));
  const progress = vi.fn();
  try {
    expect(await LLMService.generateNotulen(raw, profile, progress)).toBe(checked);
    expect(requests).toHaveLength(2);
    expect(requests[1].messages.at(-1)?.content).toContain(raw);
    expect(requests[1].messages.at(-1)?.content).toContain(draft);
    expect(progress.mock.calls.flat().join("")).toBe(checked);
  } finally { vi.unstubAllGlobals(); }
});

it("fails rather than returning the draft when source checking is unavailable", async () => {
  useSettingsStore.setState({ notulen_provider: "openai" });
  loadCredential.mockResolvedValue("test-key");
  invoke.mockResolvedValueOnce({ status: 200, body: JSON.stringify({ choices: [{ message: { content: "<p>Concept</p>" } }] }) })
    .mockResolvedValueOnce({ status: 500, body: "{}" });
  const progress = vi.fn();
  await expect(LLMService.generateNotulen("QA bron.", profile, progress)).rejects.toThrow("HTTP 500");
  expect(progress).not.toHaveBeenCalled();
  expect(invoke).toHaveBeenCalledTimes(2);
});

it("does not ask the checker to invent notes from an empty draft", async () => {
  useSettingsStore.setState({ notulen_provider: "lm-studio" });
  const fetchMock = vi.fn(async () => new Response("data: [DONE]\n\n"));
  vi.stubGlobal("fetch", fetchMock);
  try {
    await expect(LLMService.generateNotulen("QA bron.", profile)).rejects.toThrow("leeg concept");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  } finally { vi.unstubAllGlobals(); }
});
