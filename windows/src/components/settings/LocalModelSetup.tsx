import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-shell";
import { isLocalEndpoint, useSettingsStore } from "../../stores/settingsStore";
import { aiEndpoint, getAIConfig, validateAIEndpoint, testAIConnection } from "../../services/llm";
import { CloudAISettings } from "./CloudAISettings";
import { WHISPER_MODELS } from "../../types";

export async function checkNotuleModel(baseUrl: string, model: string, apiKey = ""): Promise<void> {
  validateAIEndpoint(baseUrl);
  let response: { status: number; body: string };
  try {
    response = await invoke<{ status: number; body: string }>("proxy_request", {
      request: { url: aiEndpoint(baseUrl, "/v1/models"), method: "GET", headers: apiKey && new URL(baseUrl).protocol === "https:" ? { Authorization: `Bearer ${apiKey}` } : {} },
    });
  } catch {
    throw new Error(`AI-server niet bereikbaar op ${baseUrl}. Start Ollama of de lokale server van LM Studio en probeer opnieuw.`);
  }
  if (response.status !== 200) throw new Error(response.status === 401 || response.status === 403 ? "API-sleutel ontbreekt of is ongeldig." : `AI-serverfout (HTTP ${response.status}). Controleer het adres en model.`);
  let models: { id: string }[];
  try {
    const data = JSON.parse(response.body).data;
    if (!Array.isArray(data)) throw new Error();
    models = data;
  } catch { throw new Error("De AI-server gaf geen geldige modellenlijst. Controleer de lokale server-URL."); }
  if (!models.some((item) => item?.id === model || item?.id === `${model}:latest`)) {
    throw new Error(`Model "${model}" ontbreekt. Kies een beschikbaar cloudmodel, download het model in Ollama of laad het in LM Studio.`);
  }
  if (!isLocalEndpoint(baseUrl)) await testAIConnection(baseUrl, model, apiKey);
}

export function LocalModelSetup() {
  const settings = useSettingsStore();
  const [whisperReady, setWhisperReady] = useState(false);
  const [checking, setChecking] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [whisperError, setWhisperError] = useState("");
  const [notuleStatus, setNotuleStatus] = useState("");
  const [notuleReady, setNotuleReady] = useState(false);
  const provider = settings.notulen_provider;
  const baseUrl = provider === "lm-studio" ? settings.lm_studio_url : settings.ollama_url;
  const model = provider === "lm-studio" ? settings.lm_studio_model : settings.ollama_model;

  const checkWhisper = useCallback(async () => {
    const status = await invoke<{ exists: boolean }>("whisper_model_status", { modelId: settings.whisper_model });
    setWhisperReady(status.exists);
    return status.exists;
  }, [settings.whisper_model]);

  useEffect(() => {
    setWhisperReady(false);
    setWhisperError("");
    void checkWhisper().catch(() => setWhisperError("Transcriptiemodel controleren mislukt. Probeer opnieuw in de desktopapp."));
  }, [checkWhisper]);
  useEffect(() => { setNotuleReady(false); setNotuleStatus(""); }, [baseUrl, model, provider]);

  async function checkModels() {
    setChecking(true);
    setWhisperError("");
    setNotuleReady(false);
    try { await checkWhisper(); }
    catch { setWhisperError("Transcriptiemodel controleren mislukt. Probeer opnieuw."); }
    try {
      const config = await getAIConfig();
      await checkNotuleModel(config.baseUrl, config.model, config.apiKey);
      setNotuleReady(true);
      setNotuleStatus("Notulemodel klaar voor gebruik.");
    } catch (error) {
      setNotuleStatus(error instanceof Error ? error.message : "AI-server niet bereikbaar. Start Ollama of LM Studio en controleer de URL.");
    } finally { setChecking(false); }
  }

  async function downloadWhisper() {
    setDownloading(true);
    setWhisperError("");
    setProgress(0);
    let unlisten: (() => void) | undefined;
    try {
      unlisten = await listen<{ model: string; pct: number }>("whisper-download-progress", (event) => {
        if (event.payload.model === settings.whisper_model) setProgress(event.payload.pct ?? 0);
      });
      await invoke("download_whisper_model", { modelId: settings.whisper_model });
      await checkWhisper();
    } catch (error) {
      setWhisperError(`Download mislukt: ${String(error)}. Controleer internet en vrije schijfruimte en probeer opnieuw.`);
    } finally { unlisten?.(); setDownloading(false); }
  }

  return (
    <div className="flex-col gap-10">
      <p className="settings-desc">Opslag en transcriptie blijven lokaal. Cloud-AI ontvangt de transcriptie voor notulen; audio blijft op deze pc.</p>
      <label className="form-label-sm">Transcriptiemodel (Whisper)
        <select className="select" style={{ width: "100%" }} value={settings.whisper_model}
          disabled={downloading || checking}
          onChange={(event) => settings.updateSettings({ whisper_model: event.target.value })}>
          {WHISPER_MODELS.map((item) => <option key={item.id} value={item.id}>{item.label} ({item.size})</option>)}
        </select>
      </label>
      <p role="status" className="settings-desc">{whisperReady ? "Transcriptiemodel klaar voor gebruik." : downloading ? `Downloaden… ${progress}%` : "Download het transcriptiemodel voordat je de eerste opname verwerkt."}</p>
      {!whisperReady && <button className="btn btn-secondary btn-sm" onClick={downloadWhisper} disabled={downloading || checking}>
        {downloading ? "Downloaden…" : "Transcriptiemodel downloaden"}
      </button>}
      {whisperError && <p role="alert" className="settings-desc" style={{ color: "var(--fill-system-critical)" }}>{whisperError}</p>}
      <CloudAISettings />
      <label className="form-label-sm">Notule-generator
        <select className="select" style={{ width: "100%" }} value={provider} disabled={checking}
          onChange={(event) => settings.updateSettings({ notulen_provider: event.target.value as typeof provider })}>
          <option value="ollama-cloud">Ollama Cloud</option><option value="openai-compatible">Cloudprovider</option><option value="ollama">Ollama (lokaal)</option><option value="lm-studio">LM Studio (lokaal)</option>
        </select>
      </label>
      {(provider === "ollama" || provider === "lm-studio") && <>
      <label className="form-label-sm">Lokale server-URL
        <input className="input" type="url" value={baseUrl} disabled={checking}
          onChange={(event) => settings.updateSettings(provider === "lm-studio" ? { lm_studio_url: event.target.value } : { ollama_url: event.target.value })} />
      </label>
      {!isLocalEndpoint(baseUrl) && !baseUrl.startsWith("https://") && <p role="alert" className="settings-desc">Gebruik HTTPS voor een externe AI-server; voor lokale AI mag localhost via HTTP.</p>}
      <label className="form-label-sm">Notulemodel
        <input className="input" value={model} disabled={checking}
          onChange={(event) => settings.updateSettings(provider === "lm-studio" ? { lm_studio_model: event.target.value } : { ollama_model: event.target.value })} />
      </label>
      {provider === "ollama" ? <>
        <p className="settings-desc">Installeer en start Ollama. Open daarna PowerShell en voer dit uit:</p>
        <code style={{ overflowWrap: "anywhere" }}>ollama pull {model || "llama3.2"}</code>
        <button className="btn btn-secondary btn-sm" onClick={() => { void open("https://ollama.com/download/windows").catch(() => setNotuleStatus("Open https://ollama.com/download/windows in je browser.")); }}>Ollama downloaden</button>
      </> : <p className="settings-desc">Laad het gekozen model in LM Studio en start de lokale server (standaard poort 1234).</p>}
      </>}
      <button className="btn btn-accent btn-sm" onClick={checkModels} disabled={checking || downloading}>
        {checking ? "Controleren…" : "Opnieuw controleren"}
      </button>
      {notuleStatus && <p role="status" className="settings-desc" style={{ color: notuleReady ? "var(--fill-system-success)" : "var(--fill-system-critical)" }}>{notuleStatus}</p>}
      <p className="settings-desc">Je kunt de inrichting later afronden via Instellingen. Opnemen en bestaande notulen bekijken blijven beschikbaar.</p>
    </div>
  );
}
