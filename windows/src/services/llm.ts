import { useSettingsStore } from "../stores/settingsStore";
import { enrichProfile } from "./profileTemplates";
import { loadCredential } from "./tauriCommands";
import { quickNotePrompt, ensureNotesSection } from "./quickNotes";
import { invoke } from "@tauri-apps/api/core";
import { DEFAULT_SETTINGS } from "../types";
import type { Profile, NotulenProvider } from "../types";
import { isOllamaCloudURL } from "./ollamaModels";

import { usePersonalCorrectionsStore } from "../stores/personalCorrectionsStore";
import { correctText, correctHTML, correctionPrompt } from "./personalCorrections";

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

// These constraints must survive both chunk summaries and the final profile.
const FACTUALITY_RULES = "Behoud expliciete ontkenningen, verboden, voorwaarden en vervallen afspraken bij het bijbehorende besluit of de actie, ook in een compacte notule. Een uitnodiging is geen aanwezigheid; vermeld expliciete afwezigheid. Een open vraag is geen besluit: presenteer onbesliste onderwerpen niet als opdracht of afgesproken vervolg. Voeg geen vervolgafspraken toe die niet zijn genoemd. Controleer vóór het antwoorden alle besluiten en acties tegen de transcriptie op deze beperkingen en herstel weglatingen.";

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
  return content + `\n\nLaatste inhoudsregels: volg de gekozen template en laat lege secties weg. Verzin geen feiten, besluiten, eigenaren of termijnen. ${FACTUALITY_RULES} Schrijf eenvoudige HTML zonder CSS, style-blok of code fences.`;
}

async function generateWithOpenAICompatible(
  baseUrl: string,
  model: string,
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  onProgress?: ProgressCallback
): Promise<string> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  // Bearer only over HTTPS (e.g. Ollama Cloud). Never leak a token to a plain
  // http://localhost endpoint.
  if (apiKey && baseUrl.startsWith("https://")) {
    headers["Authorization"] = `Bearer ${apiKey}`;
  }

  // Ollama Cloud rejects WebView CORS; use the same native proxy as its model list.
  if (isOllamaCloudURL(baseUrl)) {
    if (!apiKey) throw new Error("Vul je Ollama Cloud API-sleutel in bij Instellingen.");
    const base = baseUrl.replace(/\/+$/, "").replace(/\/v1$/, "");
    const response = await invoke<{ status: number; body: string }>("proxy_request", {
      request: { url: `${base}/v1/chat/completions`, method: "POST", headers, timeout_seconds: 300,
        body: JSON.stringify({ model, messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }], stream: false }) },
    });
    if (response.status === 401) throw new Error("Ollama Cloud API-sleutel geweigerd.");
    if (response.status === 429) throw new Error("Ollama Cloud API-limiet bereikt. Probeer later opnieuw.");
    if (response.status >= 400) throw new Error(`Ollama Cloud gaf HTTP ${response.status} voor model "${model}".`);
    const text = JSON.parse(response.body).choices?.[0]?.message?.content;
    if (typeof text !== "string" || !text.trim()) throw new Error("Ollama Cloud gaf een leeg antwoord.");
    onProgress?.(text);
    return text;
  }

  let response: Response;
  try {
    response = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        stream: true,
      }),
    });
  } catch {
    // A bare "Failed to fetch" hides which server is down — name it.
    throw new Error(
      `Kan de notule-generator niet bereiken op ${baseUrl} (model "${model}"). Draait Ollama/LM Studio en klopt de URL in Instellingen?`,
    );
  }

  if (!response.ok) {
    throw new Error(`Notule-generator op ${baseUrl} gaf een fout (HTTP ${response.status}, model "${model}").`);
  }

  const reader = response.body?.getReader();
  if (!reader) throw new Error("No response body");

  const decoder = new TextDecoder();
  let fullText = "";
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? ""; // keep incomplete trailing line for next chunk

    for (const line of lines) {
      if (!line.startsWith("data: ")) continue;
      const data = line.slice(6).trim();
      if (data === "[DONE]") continue;
      try {
        const parsed = JSON.parse(data);
        const delta = parsed.choices?.[0]?.delta?.content || "";
        if (delta) {
          fullText += delta;
          onProgress?.(delta);
        }
      } catch {
        // ignore parse errors on partial frames
      }
    }
  }

  return fullText;
}

async function generateWithHostedAPI(
  provider: "openai" | "anthropic",
  model: string,
  systemPrompt: string,
  userPrompt: string,
  apiKey: string,
  onProgress?: ProgressCallback,
): Promise<string> {
  const openAI = provider === "openai";
  const url = openAI ? "https://api.openai.com/v1/chat/completions" : "https://api.anthropic.com/v1/messages";
  const body = openAI
    ? { model, messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }] }
    : { model, max_tokens: 16000, system: systemPrompt, messages: [{ role: "user", content: userPrompt }] };
  const response = await invoke<{ status: number; body: string }>("proxy_request", {
    request: {
      url, method: "POST", timeout_seconds: 300,
      headers: openAI
        ? { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` }
        : { "Content-Type": "application/json", "anthropic-version": "2023-06-01", "x-api-key": apiKey },
      body: JSON.stringify(body),
    },
  });
  if (response.status === 401) throw new Error(`${openAI ? "OpenAI" : "Anthropic"} API-sleutel geweigerd.`);
  if (response.status === 429) throw new Error(`${openAI ? "OpenAI" : "Anthropic"} API-limiet bereikt. Probeer later opnieuw.`);
  if (response.status >= 400) throw new Error(`${openAI ? "OpenAI" : "Anthropic"} gaf HTTP ${response.status}.`);
  const result = JSON.parse(response.body);
  const text = openAI ? result.choices?.[0]?.message?.content : result.content?.filter((part: { type: string }) => part.type === "text").map((part: { text: string }) => part.text).join("");
  if (typeof text !== "string" || !text.trim()) throw new Error("De aanbieder gaf een leeg antwoord.");
  onProgress?.(text);
  return text;
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
    participants: string[] = [],
    quickNote: string = "",
  ): Promise<string> {
    await usePersonalCorrectionsStore.getState().hydrate();
    const corrections = usePersonalCorrectionsStore.getState().entries;
    const finish = (html: string) => correctHTML(ensureNotesSection(stripCodeFences(html), quickNote), corrections, profile.id);
    const config = getConfig();
    const enriched = enrichProfile(profile);
    let processed = correctText(transcription, corrections, profile.id);
    const compatible = config.provider === "ollama" || config.provider === "lm-studio";
    const baseURL = config.provider === "ollama" ? config.ollamaUrl : config.lmStudioUrl;
    const model = config.provider === "ollama" ? config.ollamaModel : config.lmStudioModel;
    const compatibleKey = compatible && config.provider === "ollama" && baseURL.startsWith("https://")
      ? await loadCredential("ollama_api_key") : null;
    if (compatible) {
      // Match macOS: small local contexts need summaries before the final profile.
      const hostedGPTOSS = isOllamaCloudURL(baseURL)
        && ["gpt-oss:120b", "gpt-oss:120b-cloud", "gpt-oss:20b", "gpt-oss:20b-cloud"].includes(model);
      const limit = hostedGPTOSS ? 64_000 : 8_000;
      while (Array.from(processed).length > limit) {
        const characters = Array.from(processed);
        const summaries: string[] = [];
        for (let offset = 0; offset < characters.length; offset += limit) {
          summaries.push(await generateWithOpenAICompatible(baseURL, model,
            `Je vat transcripties samen. Bewaar namen, feiten, besluiten, actiepunten, eigenaren en termijnen. Verzin niets. ${FACTUALITY_RULES}`,
            correctionPrompt(corrections, profile.id) + "Vat dit deel compact samen:\n\n" + characters.slice(offset, offset + limit).join(""),
            compatibleKey ?? ""));
        }
        const summarized = summaries.join("\n\n");
        if (Array.from(summarized).length >= characters.length) {
          throw new Error("De notule-generator verkort de lange transcriptie onvoldoende. De transcriptie is bewaard; kies een ander model en probeer opnieuw.");
        }
        processed = summarized;
      }
    }
    const userPrompt = correctionPrompt(corrections, profile.id) + quickNotePrompt(quickNote) + buildUserContent(
      enriched.notule_prompt ?? "",
      processed,
      enriched.output_template ?? enriched.notule_template,
      participants
    );

    if (config.provider === "ollama") {
      const html = await generateWithOpenAICompatible(
        config.ollamaUrl,
        config.ollamaModel,
        enriched.system_prompt ?? "",
        userPrompt,
        compatibleKey ?? "",
        onProgress
      );
      return finish(html);
    }

    if (config.provider === "lm-studio") {
      const html = await generateWithOpenAICompatible(
        config.lmStudioUrl,
        config.lmStudioModel,
        enriched.system_prompt ?? "",
        userPrompt,
        "",
        onProgress
      );
      return finish(html);
    }

    if (config.provider === "openai" || config.provider === "anthropic") {
      const provider = config.provider;
      const key = await loadCredential(`${provider}_api_key`);
      if (!key) throw new Error(`Vul je ${provider === "openai" ? "OpenAI" : "Anthropic"} API-sleutel in bij Instellingen.`);
      return finish(await generateWithHostedAPI(
        provider, provider === "openai" ? config.openAIModel : config.anthropicModel,
        enriched.system_prompt ?? "", userPrompt, key, onProgress,
      ));
    }

    throw new Error("Cloud provider moet via de server worden verwerkt");
  }
}
