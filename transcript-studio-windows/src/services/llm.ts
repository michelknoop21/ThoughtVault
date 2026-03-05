import type { Profile, NotulenProvider } from "../types";

interface LLMConfig {
  provider: NotulenProvider;
  ollamaUrl: string;
  ollamaModel: string;
  lmStudioUrl: string;
  lmStudioModel: string;
}

type ProgressCallback = (chunk: string) => void;

function getConfig(): LLMConfig {
  const stored = localStorage.getItem("settings-store");
  if (stored) {
    try {
      const settings = JSON.parse(stored).state;
      return {
        provider: settings.notulen_provider || "cloud",
        ollamaUrl: settings.ollama_url || "http://localhost:11434",
        ollamaModel: settings.ollama_model || "llama3.2",
        lmStudioUrl: settings.lm_studio_url || "http://localhost:1234",
        lmStudioModel: settings.lm_studio_model || "local-model",
      };
    } catch {
      // fall through
    }
  }
  return {
    provider: "cloud",
    ollamaUrl: "http://localhost:11434",
    ollamaModel: "llama3.2",
    lmStudioUrl: "http://localhost:1234",
    lmStudioModel: "local-model",
  };
}

async function generateWithOpenAICompatible(
  baseUrl: string,
  model: string,
  systemPrompt: string,
  userPrompt: string,
  onProgress?: ProgressCallback
): Promise<string> {
  const response = await fetch(`${baseUrl}/v1/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      stream: true,
    }),
  });

  if (!response.ok) {
    throw new Error(`LLM request failed: ${response.status}`);
  }

  const reader = response.body?.getReader();
  if (!reader) throw new Error("No response body");

  const decoder = new TextDecoder();
  let fullText = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = decoder.decode(value);
    const lines = chunk.split("\n").filter((l) => l.startsWith("data: "));

    for (const line of lines) {
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
        // ignore parse errors
      }
    }
  }

  return fullText;
}

export class LLMService {
  static async generateNotulen(
    transcription: string,
    profile: Profile,
    onProgress?: ProgressCallback
  ): Promise<string> {
    const config = getConfig();

    const userPrompt = `${profile.notule_prompt}\n\n---\n\n${transcription}`;

    if (config.provider === "ollama") {
      return generateWithOpenAICompatible(
        config.ollamaUrl,
        config.ollamaModel,
        profile.system_prompt ?? "",
        userPrompt,
        onProgress
      );
    }

    if (config.provider === "lm-studio") {
      return generateWithOpenAICompatible(
        config.lmStudioUrl,
        config.lmStudioModel,
        profile.system_prompt ?? "",
        userPrompt,
        onProgress
      );
    }

    throw new Error("Cloud provider moet via de server worden verwerkt");
  }
}
