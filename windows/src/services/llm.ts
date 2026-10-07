import { isLocalEndpoint, useSettingsStore } from "../stores/settingsStore";
import { loadCredential, storeCredential } from "./tauriCommands";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { enrichProfile } from "./profileTemplates";
import type { Profile } from "../types";

type ProgressCallback = (chunk: string) => void;
export function aiEndpoint(baseUrl: string, path: string): string {
  const base = baseUrl.replace(/\/+$/, "");
  return base + (base.endsWith("/v1") && path.startsWith("/v1/") ? path.slice(3) : path);
}
export function validateAIEndpoint(baseUrl: string): void {
  const url = new URL(baseUrl);
  if (url.username || url.password || (url.protocol !== "https:" && !isLocalEndpoint(baseUrl))) throw new Error("Gebruik HTTPS voor cloud-AI of localhost voor lokale AI.");
}
export async function getAIConfig() {
  const settings = useSettingsStore.getState();
  const provider = settings.notulen_provider;
  if (provider === "openai-compatible") {
    const config = settings.cloud_providers.find((item) => item.id === settings.selected_cloud_provider);
    if (!config) throw new Error("Selecteer een opgeslagen cloudprovider in Instellingen.");
    if (new URL(config.base_url).protocol !== "https:") throw new Error("Cloudproviders vereisen een HTTPS-adres.");
    return { baseUrl: config.base_url, model: config.model, apiKey: await loadCredential(`cloudAI-${config.id}`) ?? "" };
  }
  if (provider === "lm-studio") return { baseUrl: settings.lm_studio_url, model: settings.lm_studio_model, apiKey: "" };
  // Move legacy persisted keys to the existing OS credential store before using them.
  if (settings.ollama_api_key) {
    await storeCredential("ollamaApiKey", settings.ollama_api_key);
    useSettingsStore.getState().updateSettings({ ollama_api_key: "" });
  }
  return { baseUrl: provider === "ollama-cloud" ? "https://ollama.com" : settings.ollama_url,
    model: provider === "ollama-cloud" ? settings.ollama_cloud_model : settings.ollama_model,
    apiKey: await loadCredential("ollamaApiKey") ?? "" };
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
  return content + `\n\nLaatste inhoudsregels: volg de gekozen template en laat lege secties weg. Verzin geen feiten, besluiten, eigenaren of termijnen. Schrijf eenvoudige HTML zonder CSS, style-blok of code fences.`;
}

async function generateWithOpenAICompatible(
  baseUrl: string,
  model: string,
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  onProgress?: ProgressCallback
): Promise<string> {
  validateAIEndpoint(baseUrl);
  if (!model.trim()) throw new Error("Kies een notulemodel in Instellingen.");
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (apiKey && new URL(baseUrl).protocol === "https:") headers.Authorization = `Bearer ${apiKey}`;
  const eventName = `ai-stream-${crypto.randomUUID()}`;
  let fullText = "";
  let interrupted = false;
  const unlisten = await listen<string>(eventName, ({ payload }) => {
    try {
      const parsed = JSON.parse(payload);
      const delta = parsed.choices?.[0]?.delta?.content ?? "";
      fullText += delta;
      if (delta) onProgress?.(delta);
    } catch { /* Ignore non-JSON SSE frames. */ }
  });
  const stop = await listen(`${eventName}-interrupted`, () => { interrupted = true; });
  try {
    await invoke("http_sse_stream", { url: aiEndpoint(baseUrl, "/v1/chat/completions"), headers, eventName,
      body: JSON.stringify({ model, stream: true, messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }] }) });
    if (interrupted) throw new Error("AI-verbinding onderbroken. Transcriptie blijft bewaard; probeer opnieuw.");
    if (!fullText.trim()) throw new Error("De AI-provider gaf een leeg antwoord.");
    return fullText;
  } finally { unlisten(); stop(); }
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
  static async generateNotulen(
    transcription: string,
    profile: Profile,
    onProgress?: ProgressCallback,
    participants: string[] = []
  ): Promise<string> {
    const config = await getAIConfig();
    const enriched = enrichProfile(profile);
    const userPrompt = buildUserContent(
      enriched.notule_prompt ?? "",
      transcription,
      enriched.output_template ?? enriched.notule_template,
      participants
    );

    const html = await generateWithOpenAICompatible(config.baseUrl, config.model, enriched.system_prompt ?? "", userPrompt, config.apiKey, onProgress);
    return stripCodeFences(html);
  }
}

export async function testAIConnection(baseUrl: string, model: string, apiKey: string): Promise<void> {
  await generateWithOpenAICompatible(baseUrl, model, "Antwoord alleen OK.", "Dit is een verbindingstest. Antwoord alleen OK.", apiKey);
}
