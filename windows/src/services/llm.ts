import { useSettingsStore } from "../stores/settingsStore";
import { enrichProfile } from "./profileTemplates";
import type { Profile, NotulenProvider } from "../types";

interface LLMConfig {
  provider: NotulenProvider;
  ollamaUrl: string;
  ollamaModel: string;
  ollamaApiKey: string;
  lmStudioUrl: string;
  lmStudioModel: string;
}

type ProgressCallback = (chunk: string) => void;

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
    ollamaApiKey: settings.ollama_api_key || "",
    lmStudioUrl: settings.lm_studio_url || "http://localhost:1234",
    lmStudioModel: settings.lm_studio_model || "local-model",
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
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  // Bearer only over HTTPS (e.g. Ollama Cloud). Never leak a token to a plain
  // http://localhost endpoint.
  if (apiKey && baseUrl.startsWith("https://")) {
    headers["Authorization"] = `Bearer ${apiKey}`;
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
    const config = getConfig();
    const enriched = enrichProfile(profile);
    const userPrompt = buildUserContent(
      enriched.notule_prompt ?? "",
      transcription,
      enriched.output_template ?? enriched.notule_template,
      participants
    );

    if (config.provider === "ollama") {
      const html = await generateWithOpenAICompatible(
        config.ollamaUrl,
        config.ollamaModel,
        enriched.system_prompt ?? "",
        userPrompt,
        config.ollamaApiKey,
        onProgress
      );
      return stripCodeFences(html);
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
      return stripCodeFences(html);
    }

    throw new Error("Cloud provider moet via de server worden verwerkt");
  }
}
