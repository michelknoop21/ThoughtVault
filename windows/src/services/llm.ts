import { useSettingsStore } from "../stores/settingsStore";
import { enrichProfile } from "./profileTemplates";
import { loadCredential } from "./tauriCommands";
import { quickNotePrompt, ensureNotesSection } from "./quickNotes";
import { invoke } from "@tauri-apps/api/core";
import { DEFAULT_SETTINGS } from "../types";
import type { Profile, NotulenProvider } from "../types";
import { isHostedURL, isOllamaCloudURL } from "./ollamaModels";

import { loadCorrectionsOrEmpty } from "../stores/personalCorrectionsStore";
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import { correctText, correctHTML, contextBlock, CONTEXT_BUDGET, type PersonalCorrection } from "./personalCorrections";
import { auditSource, auditNotule, appendWarnings, AuditFinding, constraintSentences, UNCHECKED_CONTENT_WARNING, AUDIT_CONCURRENCY, HOSTED_AUDIT_CONCURRENCY } from "./notuleAudit";
import { logModelRequest, logRetry, TIME_LIMIT_MESSAGE, TRUNCATED_MESSAGE, type ModelStep, type RequestTrace } from "./modelRequestLog";

export { TIME_LIMIT_MESSAGE, TRUNCATED_MESSAGE };

interface LLMConfig {
  provider: NotulenProvider;
  ollamaUrl: string;
  ollamaModel: string;
  lmStudioUrl: string;
  lmStudioModel: string;
  openAIModel: string;
  anthropicModel: string;
}

type ProgressCallback = (chunk: string) => void;

/** Total time per model request, as on macOS. A cold local model plus a long non-streamed draft can need it. */
const LLM_TIME_LIMIT_SECONDS = 900;
/** Output cap per model request, as on macOS (llmMaxOutputTokens). The largest legitimate output is the
 * single-request audit: one JSON item of about 25 tokens per unit for up to 400 units, so about 10,000 tokens.
 * A long notule draft is several thousand. Reasoning models count their thinking against it, hence 3x headroom. */
export const MAX_OUTPUT_TOKENS = 32_768;
/** Prefix of the proxy_request error for a timeout (http.rs). */
const PROXY_TIMEOUT = "Tijdslimiet bereikt";

/** Wait before retrying an HTTP 429 when the provider sends no usable Retry-After, as on macOS. */
export const RATE_LIMIT_DEFAULT_WAIT_MS = 2_000;
/** Longest Retry-After that is waited for; a provider asking more is reported as rate limiting right away. */
export const RATE_LIMIT_MAX_WAIT_MS = 30_000;
const RATE_LIMIT_MESSAGE = "API-limiet bereikt (429), ook na een nieuwe poging. Probeer het later opnieuw of verwerk minder opnames tegelijk.";

/** Milliseconds to wait before retrying a 429: Retry-After as delta-seconds or HTTP date, else the default.
 * null when the provider asks for more than RATE_LIMIT_MAX_WAIT_MS. */
export function rateLimitWaitMs(retryAfter: string | undefined, now = Date.now()): number | null {
  const value = (retryAfter ?? "").trim();
  const wait = /^\d+$/.test(value) ? Number(value) * 1000 : /[a-z]/i.test(value) && !Number.isNaN(Date.parse(value))
    ? Math.max(0, Date.parse(value) - now) : RATE_LIMIT_DEFAULT_WAIT_MS;
  return wait <= RATE_LIMIT_MAX_WAIT_MS ? wait : null;
}

type ProxyResponse = { status: number; body: string; headers?: Record<string, string> };

async function proxy(request: { url: string; headers: Record<string, string>; body: string }, timeoutSeconds: number): Promise<ProxyResponse> {
  try {
    return await invoke("proxy_request", { request: { ...request, method: "POST", timeout_seconds: timeoutSeconds } });
  } catch (error) {
    throw String(error).startsWith(PROXY_TIMEOUT) ? new Error(TIME_LIMIT_MESSAGE) : error;
  }
}

/** Every model request goes through here: one total time limit, a timeout named as such, and one retry on HTTP 429
 * after the provider's Retry-After plus up to one second of jitter, so requests that were rate limited together do
 * not collide again. The wait and the retry count against the same time limit. A wait that is too long, and a
 * second 429, return the 429 to the caller, which reports it. Windows requests take no abort signal, so there is
 * no cancellation during the wait. */
async function modelRequest(request: { url: string; headers: Record<string, string>; body: string }, trace: RequestTrace): Promise<ProxyResponse> {
  const started = Date.now();
  const first = await proxy(request, LLM_TIME_LIMIT_SECONDS);
  trace.status = first.status;
  const header = Object.entries(first.headers ?? {}).find(([name]) => name.toLowerCase() === "retry-after")?.[1];
  const wait = first.status === 429 ? rateLimitWaitMs(header) : null;
  if (wait === null) return first;
  const jittered = wait + Math.random() * 1000;
  const remainingSeconds = Math.floor((LLM_TIME_LIMIT_SECONDS * 1000 - (Date.now() - started) - jittered) / 1000);
  if (remainingSeconds < 1) return first;
  logRetry(trace, jittered);
  await new Promise(resolve => setTimeout(resolve, jittered));
  const second = await proxy(request, remainingSeconds);
  trace.status = second.status;
  return second;
}

// These constraints must survive both chunk summaries and the final profile.
const FACTUALITY_RULES = "Behoud expliciete ontkenningen, verboden, voorwaarden en vervallen afspraken bij het bijbehorende besluit of de actie, ook in een compacte notule. Behoud ook de aard en status van het besprokene: een fictief of hypothetisch voorbeeld mag geen echte afspraak worden, een voorgenomen proef geen uitgevoerd project. Noem een expliciet fictieve of hypothetische status ook expliciet in de kern van het verslag. Leid daaruit geen ongenoemde uitvoeringsstatus af: zeg alleen dat iets al wel of nog niet is uitgevoerd als de bron dat expliciet vermeldt. Een uitnodiging is geen aanwezigheid; vermeld expliciete afwezigheid. Een open vraag is geen besluit: presenteer onbesliste onderwerpen niet als opdracht of afgesproken vervolg. Voeg geen vervolgafspraken toe die niet zijn genoemd. Een toestemmingsvoorwaarde is geen opdracht of toezegging om die toestemming te geven; maak daar geen actie van. Controleer vóór het antwoorden alle besluiten en acties tegen de transcriptie op deze beperkingen en herstel weglatingen.";

function getConfig(): LLMConfig {
  const settings = useSettingsStore.getState();
  // In local mode the cloud provider is unreachable, so a leftover "cloud"
  // selection would transcribe locally and then throw. Coerce to Ollama.
  let provider = settings.notulen_provider || "cloud";
  if (settings.processing_mode === "local" && provider === "cloud") {
    provider = "ollama";
  }
  return {
    provider,
    ollamaUrl: settings.ollama_url || "http://localhost:11434",
    ollamaModel: settings.ollama_model || "llama3.2",
    lmStudioUrl: settings.lm_studio_url || "http://localhost:1234",
    lmStudioModel: settings.lm_studio_model || "local-model",
    openAIModel: settings.openai_model || DEFAULT_SETTINGS.openai_model,
    anthropicModel: settings.anthropic_model || "claude-sonnet-5-5",
  };
}

/** Glossary and directory people for the minutes AI, within the provider budget. */
export function minutesContext(entries: PersonalCorrection[], transcript: string, profileId: string | undefined, includeRoles = false): string {
  // Sorted by name, like the macOS directoryPeople().
  const people = usePeopleDirectoryStore.getState().people.filter(p => !p.isSelf).sort((a, b) => a.name.localeCompare(b.name)).map(p => ({
    name: p.name, role: p.role, organization: p.organization, responsibilities: p.responsibilities ?? [], aliases: p.aliases,
  }));
  return contextBlock(entries, people, transcript, profileId, CONTEXT_BUDGET, [], includeRoles);
}

function todayNL(): string {
  return new Date().toLocaleDateString("nl-NL", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

/**
 * Assembles the user message from the profile's notule prompt. Supports the
 * macOS/backend placeholder convention ({{TRANSCRIPTION}}, {{OUTPUT_TEMPLATE}},
 * {{DATE}}, {{PARTICIPANTS}}); falls back to plain concatenation otherwise.
 */
function buildUserContent(
  notulePrompt: string,
  transcription: string,
  outputTemplate: string | undefined,
  participants: string[]
): string {
  const template = (outputTemplate ?? "").replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "");
  let content: string;
  if (notulePrompt.includes("{{TRANSCRIPTION}}")) {
    // Substitute template first, transcription last (transcription may itself
    // contain literal brace sequences we don't want to re-expand).
    content = notulePrompt
      .split("{{OUTPUT_TEMPLATE}}").join(template)
      .split("{{TRANSCRIPTION}}").join(transcription);
  } else {
    content = `${notulePrompt}\n\nTranscriptie:\n${transcription}`;
    if (template) content += `\n\nGebruik dit outputformaat:\n${template}`;
  }
  const names = participants.filter(Boolean).join(", ");
  content = content.split("{{DATE}}").join(todayNL());
  content = content.split("{{PARTICIPANTS}}").join(names);
  if (names && !notulePrompt.includes("{{PARTICIPANTS}}")) {
    content += `\n\nDeelnemers aan dit gesprek: ${names}`;
  }
  return content + `\n\nLaatste inhoudsregels: volg de gekozen template en laat lege secties weg. Begin met één h1 die in 4 tot 10 woorden het doel of de uitkomst van het gesprek noemt; nooit alleen een genre-woord als Verslag, Notulen, Meeting, Gesprek of Overleg. Verzin geen feiten, besluiten, eigenaren of termijnen. ${FACTUALITY_RULES} Schrijf eenvoudige HTML zonder CSS, style-blok of code fences.`;
}

function generateWithOpenAICompatible(
  baseUrl: string,
  model: string,
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  onProgress?: ProgressCallback,
  step?: ModelStep,
): Promise<string> {
  // Provider kind as on macOS, without the host of a self-configured endpoint.
  const provider = isOllamaCloudURL(baseUrl) ? "ollama-cloud" : baseUrl.startsWith("https://") ? "hosted" : "local";
  const trace: RequestTrace = { step, provider, model, system: systemPrompt, user: userPrompt };
  return logModelRequest(trace, () => openAICompatibleRequest(baseUrl, model, systemPrompt, userPrompt, apiKey, trace, onProgress));
}

async function openAICompatibleRequest(
  baseUrl: string,
  model: string,
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  trace: RequestTrace,
  onProgress?: ProgressCallback
): Promise<string> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  // Bearer only over HTTPS (e.g. Ollama Cloud). Never leak a token to a plain
  // http://localhost endpoint.
  if (apiKey && baseUrl.startsWith("https://")) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }

  // Local Ollama and LM Studio can reject WebView CORS just like Ollama Cloud.
  const cloud = isOllamaCloudURL(baseUrl);
  if (cloud && !apiKey) throw new Error("Vul je Ollama Cloud API-sleutel in bij Instellingen.");
  const base = baseUrl.trim().replace(/\/+$/, "").replace(/\/v1$/, "");
  let response: { status: number; body: string };
  try {
    response = await modelRequest({ url: `${base}/v1/chat/completions`, headers,
      body: JSON.stringify({ model, messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }], stream: false, max_tokens: MAX_OUTPUT_TOKENS }) }, trace);
  } catch (error) {
    if (error instanceof Error && error.message === TIME_LIMIT_MESSAGE) throw error;
    throw new Error(`Kan de notule-generator niet bereiken op ${baseUrl} (model "${model}"). Draait Ollama/LM Studio en klopt de URL in Instellingen?`);
  }
  if (cloud && response.status === 401) throw new Error("Ollama Cloud API-sleutel geweigerd.");
  if (cloud && response.status === 429) throw new Error(`Ollama Cloud ${RATE_LIMIT_MESSAGE}`);
  if (response.status >= 400) throw new Error(`${cloud ? "Ollama Cloud" : `Notule-generator op ${baseUrl}`} gaf HTTP ${response.status} voor model "${model}".`);
  const choice = JSON.parse(response.body).choices?.[0];
  // A capped answer is incomplete; never parse it as a short one.
  if (choice?.finish_reason === "length") throw new Error(TRUNCATED_MESSAGE);
  const text = choice?.message?.content;
  if (typeof text !== "string" || !text.trim()) throw new Error(cloud ? "Ollama Cloud gaf een leeg antwoord." : "De notule-generator gaf een leeg concept.");
  onProgress?.(text);
  return text;
}

function generateWithHostedAPI(
  provider: "openai" | "anthropic",
  model: string,
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  onProgress?: ProgressCallback,
  step?: ModelStep,
): Promise<string> {
  const trace: RequestTrace = { step, provider, model, system: systemPrompt, user: userPrompt };
  return logModelRequest(trace, () => hostedRequest(provider, model, systemPrompt, userPrompt, apiKey, trace, onProgress));
}

async function hostedRequest(
  provider: "openai" | "anthropic",
  model: string,
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  trace: RequestTrace,
  onProgress?: ProgressCallback,
): Promise<string> {
  const openAI = provider === "openai";
  const url = openAI ? "https://api.openai.com/v1/chat/completions" : "https://api.anthropic.com/v1/messages";
  // api.openai.com rejects `max_tokens` for newer models.
  const body = openAI
    ? { model, messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }], max_completion_tokens: MAX_OUTPUT_TOKENS }
    : { model, max_tokens: 16000, system: systemPrompt, messages: [{ role: "user", content: userPrompt }] };
  const response = await modelRequest({
    url,
    headers: openAI
      ? { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` }
      : { "Content-Type": "application/json", "anthropic-version": "2023-06-01", "x-api-key": apiKey },
    body: JSON.stringify(body),
  }, trace);
  if (response.status === 401) throw new Error(`${openAI ? "OpenAI" : "Anthropic"} API-sleutel geweigerd.`);
  if (response.status === 429) throw new Error(`${openAI ? "OpenAI" : "Anthropic"} ${RATE_LIMIT_MESSAGE}`);
  if (response.status >= 400) throw new Error(`${openAI ? "OpenAI" : "Anthropic"} gaf HTTP ${response.status}.`);
  const result = JSON.parse(response.body);
  if (openAI ? result.choices?.[0]?.finish_reason === "length" : result.stop_reason === "max_tokens") throw new Error(TRUNCATED_MESSAGE);
  const text = openAI ? result.choices?.[0]?.message?.content : result.content?.filter((part: { type: string }) => part.type === "text").map((part: { text: string }) => part.text).join("");
  if (typeof text !== "string" || !text.trim()) throw new Error("De aanbieder gaf een leeg antwoord.");
  onProgress?.(text);
  return text;
}

/** Step-2 audit checks in flight for a long meeting: 8 for a hosted provider, 4 for a local model (DEC-065).
 * Ollama and LM Studio count as hosted only with an https URL to a public host, as on macOS. */
export function auditNoteConcurrency(provider: NotulenProvider, compatibleBaseURL: string): number {
  const hosted = provider === "openai" || provider === "anthropic"
    || ((provider === "ollama" || provider === "lm-studio") && isHostedURL(compatibleBaseURL));
  return hosted ? HOSTED_AUDIT_CONCURRENCY : AUDIT_CONCURRENCY;
}

/**
 * Removes the markdown code fences some models wrap around their HTML output.
 * The cloud backend strips these server-side; local generation needs the same
 * guard because the prompt discourages fences but cannot prevent them.
 */
function stripCodeFences(html: string): string {
  return html
    .trim()
    .replace(/^```(?:html)?\s*\n?/, "")
    .trim()
    .replace(/\n?```\s*$/, "")
    .trim();
}

export class LLMService {
  /** One plain request to the selected provider, for small helper prompts (no audit, no chunking). */
  static async complete(systemPrompt: string, userMessage: string, step?: ModelStep): Promise<string> {
    const config = getConfig();
    const provider = config.provider === "cloud" ? "ollama" : config.provider;
    if (provider === "openai" || provider === "anthropic") {
      const key = await loadCredential(`${provider}_api_key`);
      if (!key) throw new Error(`Vul je ${provider === "openai" ? "OpenAI" : "Anthropic"} API-sleutel in bij Instellingen.`);
      return generateWithHostedAPI(provider, provider === "openai" ? config.openAIModel : config.anthropicModel, systemPrompt, userMessage, key, undefined, step);
    }
    const baseURL = provider === "ollama" ? config.ollamaUrl : config.lmStudioUrl;
    const key = provider === "ollama" && baseURL.startsWith("https://") ? await loadCredential("ollama_api_key") : null;
    return generateWithOpenAICompatible(baseURL, provider === "ollama" ? config.ollamaModel : config.lmStudioModel, systemPrompt, userMessage, key ?? "", undefined, step);
  }

  static async generateNotulen(
    transcription: string,
    profile: Profile,
    onProgress?: ProgressCallback,
    participants: string[] = [],
    quickNote: string = "",
    /** The running step for the task label (stepLabel). */
    onStep?: (step: ModelStep) => void,
  ): Promise<string> {
    const corrections = await loadCorrectionsOrEmpty();
    const context = minutesContext(corrections, transcription, profile.id);
    const finish = (html: string) => correctHTML(ensureNotesSection(stripCodeFences(html), quickNote), corrections, profile.id);
    const config = getConfig();
    const enriched = enrichProfile(profile);
    const systemPrompt = `${enriched.system_prompt ?? ""}\n\nBrongetrouwheid gaat vóór beknoptheid en de template. ${FACTUALITY_RULES} Vermeld ieder expliciet vervallen tijdstip en iedere expliciete afwezigheid, ook als dat geen actie is. Als ergens geen besluit over uitvoering is genomen, behoud dat letterlijk als onbeslist; vraag niet hoe het uitgevoerd moet worden.`;
    let processed = correctText(transcription, corrections, profile.id);
    const compatible = config.provider === "ollama" || config.provider === "lm-studio";
    const baseURL = config.provider === "ollama" ? config.ollamaUrl : config.lmStudioUrl;
    const model = config.provider === "ollama" ? config.ollamaModel : config.lmStudioModel;
    const compatibleKey = compatible && config.provider === "ollama" && baseURL.startsWith("https://")
      ? await loadCredential("ollama_api_key") : null;
    if (compatible) {
      // Match macOS: small local contexts need summaries before the final profile.
      const limit = isHostedURL(baseURL) ? 64_000 : 8_000;
      while (Array.from(processed).length > limit) {
        const characters = Array.from(processed);
        const summaries: string[] = [];
        const total = Math.ceil(characters.length / limit);
        for (let offset = 0; offset < characters.length; offset += limit) {
          summaries.push(await generateWithOpenAICompatible(baseURL, model,
            `Je vat transcripties samen. Bewaar namen, feiten, besluiten, actiepunten, eigenaren en termijnen. Verzin niets. ${FACTUALITY_RULES}`,
            (context ? context.trim() + "\n\n" : "") + "Vat dit deel compact samen:\n\n" + characters.slice(offset, offset + limit).join(""),
            compatibleKey ?? "", undefined, { kind: "chunk-summary", index: offset / limit + 1, total }));
        }
        const summarized = summaries.join("\n\n");
        if (Array.from(summarized).length >= characters.length) {
          throw new Error("De notule-generator verkort de lange transcriptie onvoldoende. De transcriptie is bewaard; kies een ander model en probeer opnieuw.");
        }
        processed = summarized;
      }
    }
    // Same place as macOS: the context block follows the profile's notule prompt.
    const userPrompt = quickNotePrompt(quickNote) + buildUserContent(
      (enriched.notule_prompt ?? "") + context,
      processed,
      enriched.output_template ?? enriched.notule_template,
      participants
    );

    const generate = async (system: string, user: string, step?: ModelStep): Promise<string> => {
      if (config.provider === "ollama" || config.provider === "lm-studio") {
        return generateWithOpenAICompatible(baseURL, model, system, user, compatibleKey ?? "", undefined, step);
      }
      if (config.provider === "openai" || config.provider === "anthropic") {
        const provider = config.provider;
        const key = await loadCredential(`${provider}_api_key`);
        if (!key) throw new Error(`Vul je ${provider === "openai" ? "OpenAI" : "Anthropic"} API-sleutel in bij Instellingen.`);
        return generateWithHostedAPI(provider, provider === "openai" ? config.openAIModel : config.anthropicModel,
          system, user, key, undefined, step);
      }
      throw new Error("Cloud provider moet via de server worden verwerkt");
    };
    // Explicit constraints remain mandatory audit obligations (rules in constraintSentences).
    const constraints = constraintSentences(correctText(transcription, corrections, profile.id));
    const constraintPrompt = constraints.length
      ? `\n\nVerplicht te behouden bronzinnen (behoud de volledige betekenis, bedragen en voorwaarden bij het passende onderwerp, besluit of open punt; correcte parafrases mogen, tegenspraken nergens):\n${constraints.map((sentence, index) => `${index + 1}. ${sentence}`).join("\n")}` : "";
    // Keep the unverified draft out of progress updates and saved notes.
    onStep?.({ kind: "draft" });
    const draftRequest = generate(systemPrompt, userPrompt + constraintPrompt, { kind: "draft" });
    // The source check never sees the notule (DEC-062), so it runs while the draft is written. Settled into a
    // value so it cannot become an unhandled rejection while the draft is still running.
    const sourceCheck = auditSource(correctText(transcription, corrections, profile.id), quickNote, generate)
      .then(warning => ({ warning }), (error: unknown) => ({ error }));
    let candidate: string;
    try {
      const draft = await draftRequest;
      if (!draft.trim()) throw new Error("De notule-generator gaf een leeg concept. De transcriptie is bewaard.");
      candidate = finish(draft);
    } catch (error) {
      // The request takes no abort signal: wait for the source check and drop it, so the draft error still
      // wins and no request outlives this call (as DEC-065 does for step 2).
      await sourceCheck;
      throw error;
    }
    let warning: string | null = null;
    try {
      onStep?.({ kind: "source-check" });
      const source = await sourceCheck;
      if ("error" in source) throw source.error;
      warning = source.warning;
      await auditNotule(correctText(transcription, corrections, profile.id), candidate, quickNote, generate, constraints, warning !== null,
        auditNoteConcurrency(config.provider, baseURL), onStep);
      const approved = appendWarnings(warning ? [warning] : [], candidate);
      onProgress?.(approved);
      return approved;
    } catch (error) {
      // DEC-063: an audit problem never blocks the notule; it becomes a line in the warning section.
      const finding = error instanceof AuditFinding ? error.finding : UNCHECKED_CONTENT_WARNING;
      const result = appendWarnings(warning ? [warning, finding] : [finding], candidate);
      onProgress?.(result);
      return result;
    }
  }
}
