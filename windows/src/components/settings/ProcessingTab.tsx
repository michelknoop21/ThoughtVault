import { ask } from "@tauri-apps/plugin-dialog";
import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  DocumentText24Regular,
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  Laptop24Regular,
} from "../ui/StudioIcons";
import { transcriptionAdvice } from "../../services/processingAdvice";
import type { SystemSpecs } from "../../services/tauriCommands";
import { loadCredential } from "../../services/tauriCommands";
import { WHISPER_MODELS } from "../../types";
import { useRecordingStore } from "../../stores/recordingStore";
import { useSettingsStore } from "../../stores/settingsStore";
import { SettingsField, CredentialField } from "./SettingsFields";

export function ProcessingTab() {
  const [specs, setSpecs] = useState<SystemSpecs | null>(null);
  const [specError, setSpecError] = useState("");
  const [setupDetails, setSetupDetails] = useState(false);
  const [modelError, setModelError] = useState("");
  const advice = transcriptionAdvice(specs);
  useEffect(() => { invoke<SystemSpecs>("get_system_specs").then(setSpecs).catch(() => setSpecError("Systeemgegevens niet beschikbaar")); }, []);
  const settings = useSettingsStore();
  const isTranscribing = useRecordingStore(s => s.backgroundTasks.some(task => task.status === "transcribing" || task.status === "downloading"));
  const [ollamaTestStatus, setOllamaTestStatus] = useState<"idle" | "testing" | "success" | "error">("idle");


  // Local Whisper model state
  const [modelExists, setModelExists] = useState<boolean | null>(null);
  const [modelLibrary, setModelLibrary] = useState<{ id: string; exists: boolean }[]>([]);
  const [downloading, setDownloading] = useState(false);
  const [dlPct, setDlPct] = useState(0);

  const checkModel = useCallback(async () => {
    try {
      const models = await Promise.all(WHISPER_MODELS.map(async model => ({
        id: model.id, ...await invoke<{ exists: boolean }>("whisper_model_status", { modelId: model.id }),
      })));
      setModelLibrary(models);
      setModelExists(models.find(model => model.id === useSettingsStore.getState().whisper_model)?.exists ?? false);
    } catch {
      setModelExists(null);
    }
  }, [settings.whisper_model]);

  useEffect(() => {
    if (settings.processing_mode === "local") checkModel();
  }, [settings.processing_mode, checkModel]);

  useEffect(() => {
    let disposed = false;
    const subscriptions = [
      listen<{ pct: number }>("whisper-download-progress", event => {
        if (!disposed) { setDownloading(true); setDlPct(event.payload.pct); }
      }),
      listen<{ error: string | null }>("whisper-download-finished", event => {
        if (!disposed) { setDownloading(false); setModelError(event.payload.error ?? ""); void checkModel(); }
      }),
    ];
    void invoke<string | null>("whisper_download_status").then(model => { if (!disposed) setDownloading(Boolean(model)); }).catch(() => {});
    return () => { disposed = true; subscriptions.forEach(subscription => void subscription.then(unlisten => unlisten()).catch(() => {})); };
  }, [checkModel]);

  async function handleDownloadModel(modelId = settings.whisper_model) {
    setDownloading(true);
    setModelError("");
    setDlPct(0);
    let unlisten: (() => void) | undefined;
    try {
      unlisten = await listen<{ pct: number; model: string }>(
      "whisper-download-progress",
      (e) => { if (e.payload.model === modelId) setDlPct(e.payload.pct ?? 0); },
    );
      await invoke("download_whisper_model", { modelId });
      await checkModel();
    } catch (err) {
      setModelError(err instanceof Error ? err.message : String(err));
    } finally {
      unlisten?.();
      setDownloading(false);
    }
  }

  async function handleTestOllama() {
    setOllamaTestStatus("testing");
    try {
      const res = await invoke<{ status: number }>("ollama_test", {
        baseUrl: settings.ollama_url,
        apiKey: await loadCredential("ollama_api_key"),
      });
      setOllamaTestStatus(res.status === 200 ? "success" : "error");
    } catch {
      setOllamaTestStatus("error");
    }
    setTimeout(() => setOllamaTestStatus("idle"), 3000);
  }
  return <div className="processing-columns"><div>
      <header className="settings-section-header"><div><h2>Verwerking</h2><p>Stel in hoe ThoughtVault gesprekken transcribeert en notulen genereert.</p></div></header>
      <section className="northstar-card setup-card"><header><div><small>Snelle setup</small><h3>Aanbevolen instellingen voor jouw pc</h3><p>Op basis van je systeem. Je kunt alles daarna nog aanpassen.</p></div>
        <button className="btn btn-accent" disabled={downloading} onClick={() => {
          settings.updateSettings({ processing_mode: "local", whisper_model: advice.model, notulen_provider: settings.notulen_provider === "cloud" ? "ollama" : settings.notulen_provider });
        }}>Toepassen</button></header>
        <div className="setup-choices"><div><Laptop24Regular /><span><small>Transcriptie</small><strong>Lokaal op deze pc</strong><span>{advice.name}</span></span></div><div><DocumentText24Regular /><span><small>Notulen</small><strong>{settings.notulen_provider === "openai" ? "OpenAI" : settings.notulen_provider === "anthropic" ? "Claude" : settings.notulen_provider === "lm-studio" ? "LM Studio" : "Ollama"}</strong><span>{settings.notulen_provider === "openai" || settings.notulen_provider === "anthropic" ? "Eigen API-sleutel · aparte kosten" : "Controleer je eigen server"}</span></span></div></div>
        <button className="studio-link" onClick={() => setSetupDetails(!setupDetails)}>Bekijk details {setupDetails ? "↑" : "→"}</button>{setupDetails && <p>{advice.reason} Toepassen wijzigt de instellingen; download daarna het gekozen transcriptiemodel. Een bestaande API-provider blijft geselecteerd.</p>}
      </section>
          {/* Verwerking — local vs cloud, mirrors macOS processingMode */}
          <div className="settings-group">
            <header className="card-head"><span className="card-icon"><Laptop24Regular /></span><div><h3>Transcriptie</h3><p>Zet audio om naar tekst.</p></div></header>
            <div className="choice-cards" role="radiogroup" aria-label="Verwerkingsmodus">
              {([
                ["local", "Lokaal", "Audio blijft op deze pc; kies apart de aanbieder voor notulen"],
                ["cloud", "Cloud", "Transcriptie en notulen via de bestaande server"],
              ] as const).map(([mode, name, desc]) => <button key={mode} role="radio" aria-checked={settings.processing_mode === mode}
                className={settings.processing_mode === mode ? "selected" : ""}
                onClick={() => {
                  // Switching to local with the cloud provider still selected
                  // would fail at notule generation, so move it to Ollama.
                  const patch: Partial<typeof settings> = { processing_mode: mode };
                  if (mode === "local" && settings.notulen_provider === "cloud") {
                    patch.notulen_provider = "ollama";
                  }
                  settings.updateSettings(patch);
                }}><strong>{name}</strong><span>{desc}</span></button>)}
            </div>

            {settings.processing_mode === "local" && (
              <>
                <div style={{ padding: "0 20px 4px" }}>
                  <SettingsField label="Transcriptiemodel (Whisper)">
                    <select
                      aria-label="Transcriptiemodel" disabled={downloading} value={settings.whisper_model}
                      onChange={(e) => settings.updateSettings({ whisper_model: e.target.value })}
                      className="select"
                      style={{ width: "100%" }}
                    >
                      {WHISPER_MODELS.map((m) => (
                        <option key={m.id} value={m.id}>
                          {m.label} ({m.size})
                        </option>
                      ))}
                    </select>
                  </SettingsField>
                </div>
                <div style={{ padding: "0 20px 12px", display: "flex", flexDirection: "column", gap: 6 }}>
                  {downloading ? (
                    <><p className="settings-desc" style={{ margin: 0 }}>Downloaden… {dlPct}%</p>
                      <progress value={dlPct} max={100} aria-label="Modeldownload" />
                      <button className="btn btn-secondary btn-sm" style={{ alignSelf: "flex-start" }} onClick={() => invoke("cancel_whisper_download").catch(err => setModelError(String(err)))}>Annuleren</button></>
                  ) : modelExists ? (
                    <p className="settings-desc-success" style={{ margin: 0 }}>
                      <CheckmarkCircle24Regular style={{ fontSize: 14, verticalAlign: "middle" }} /> Model gedownload en klaar voor gebruik
                    </p>
                  ) : (
                    <>
                      <button
                        onClick={() => void handleDownloadModel()}
                        className="btn btn-accent btn-sm"
                        style={{ alignSelf: "flex-start" }}
                      >
                        Model downloaden
                      </button>
                      <p className="settings-desc" style={{ margin: 0 }}>
                        Het model wordt eenmalig gedownload. Anders gebeurt dit automatisch bij de eerste opname.
                      </p>
                    </>
                  )}
                </div>
                <details className="model-library"><summary>Modellen beheren</summary>
                  {WHISPER_MODELS.map(model => <div key={model.id}><span>{model.label} · {model.size}</span>
                    {modelLibrary.find(item => item.id === model.id)?.exists ? <>
                      <button className="btn btn-secondary btn-sm" onClick={() => invoke("show_whisper_model", { modelId: model.id }).catch(err => setModelError(String(err)))}>Toon bestand</button>
                      <button className="btn btn-secondary btn-sm" disabled={downloading || isTranscribing || model.id === settings.whisper_model} onClick={async () => {
                        if (!await ask(`Gedownload model ${model.label} verwijderen? Je kunt het later opnieuw downloaden.`, { title: "Model verwijderen", kind: "warning", okLabel: "Verwijderen", cancelLabel: "Annuleren" })) return;
                        try { await invoke("remove_whisper_model", { modelId: model.id }); await checkModel(); }
                        catch (err) { setModelError(String(err)); }
                      }}>Verwijderen</button>
                    </> : <button className="btn btn-secondary btn-sm" disabled={downloading} onClick={() => void handleDownloadModel(model.id)}>Downloaden</button>}
                  </div>)}
                  <p>Het geselecteerde model blijft bewaard.</p>
                </details>
              </>
            )}
            {modelError && <p role="alert" className="text-error" style={{ padding: "12px 20px" }}>{modelError}</p>}
          </div>

          {/* Notulen generatie */}
          <div className="settings-group">
            <header className="card-head"><span className="card-icon"><DocumentText24Regular /></span><div><h3>Notulen generatie</h3><p>Maak gestructureerde notulen van het transcript.</p></div></header>
            <div className="provider-tiles">{([
              ["openai", "OpenAI", "Eigen API-sleutel"], ["anthropic", "Claude", "Eigen Anthropic API-sleutel"],
              ["ollama", "Ollama", "Lokale of eigen server"], ["lm-studio", "LM Studio", "Lokale of eigen server"],
            ] as const).map(([id, name, subtitle]) => <button key={id} className={settings.notulen_provider === id ? "selected" : ""}
              aria-pressed={settings.notulen_provider === id} disabled={settings.processing_mode === "cloud"}
              onClick={() => settings.updateSettings({ notulen_provider: id })}><strong>{name}</strong><span>{subtitle}</span></button>)}
              <button disabled title="Apple Intelligence is alleen beschikbaar op ondersteunde Apple-apparaten"><strong>Apple Intelligence</strong><span>Niet beschikbaar op Windows</span></button>
            </div>
            {settings.processing_mode === "cloud" && <p className="settings-desc" style={{ padding: "12px 20px" }}>ThoughtVault Cloud maakt transcriptie en notulen op de server. Kies lokale transcriptie om een eigen notulenaanbieder te gebruiken.</p>}

            {settings.processing_mode === "local" && settings.notulen_provider === "ollama" && (
              <>
                <div style={{ padding: "0 20px 4px" }}>
                  <SettingsField label="Ollama URL">
                    <input
                      type="url"
                      value={settings.ollama_url}
                      onChange={(e) => settings.updateSettings({ ollama_url: e.target.value })}
                      className="input"
                    />
                  </SettingsField>
                </div>
                <div style={{ padding: "0 20px 4px" }}>
                  <SettingsField label="Model">
                    <input
                      type="text"
                      value={settings.ollama_model}
                      onChange={(e) => settings.updateSettings({ ollama_model: e.target.value })}
                      placeholder="llama3.2"
                      className="input"
                    />
                  </SettingsField>
                </div>
                <div style={{ padding: "0 20px 14px" }}>
                  <CredentialField credentialKey="ollama_api_key" label="API-sleutel (alleen Ollama Cloud)">
                  <button
                    onClick={handleTestOllama}
                    className="btn btn-secondary btn-sm"
                    disabled={ollamaTestStatus === "testing"}
                    style={{ alignSelf: "flex-start" }}
                  >
                    {ollamaTestStatus === "testing" ? "Testen..." :
                     ollamaTestStatus === "success" ? <><CheckmarkCircle24Regular style={{ fontSize: 14 }} /> Verbonden</> :
                     ollamaTestStatus === "error" ? <><ErrorCircle24Regular style={{ fontSize: 14 }} /> Niet bereikbaar</> :
                     "Test verbinding"}
                  </button>
                  </CredentialField>
                </div>
              </>
            )}

            {settings.processing_mode === "local" && settings.notulen_provider === "lm-studio" && (
              <>
                <div style={{ padding: "0 20px 4px" }}>
                  <SettingsField label="LM Studio URL">
                    <input
                      type="url"
                      value={settings.lm_studio_url}
                      onChange={(e) => settings.updateSettings({ lm_studio_url: e.target.value })}
                      className="input"
                    />
                  </SettingsField>
                </div>
                <div style={{ padding: "0 20px 12px" }}>
                  <SettingsField label="Model">
                    <input
                      type="text"
                      value={settings.lm_studio_model}
                      onChange={(e) => settings.updateSettings({ lm_studio_model: e.target.value })}
                      placeholder="local-model"
                      className="input"
                    />
                  </SettingsField>
                </div>
              </>
            )}

            {settings.processing_mode === "local" &&
              (settings.notulen_provider === "openai" || settings.notulen_provider === "anthropic") && (
              <div style={{ padding: "0 20px 12px" }}>
                <p className="settings-desc">Dit gebruikt je eigen API-sleutel met aparte API-kosten. Je ChatGPT- of Claude-abonnement wordt hiervoor niet gebruikt.</p>
                <SettingsField label="Model">
                  <input className="input" type="text"
                    value={settings.notulen_provider === "openai" ? settings.openai_model : settings.anthropic_model}
                    onChange={(e) => settings.updateSettings(settings.notulen_provider === "openai"
                      ? { openai_model: e.target.value } : { anthropic_model: e.target.value })} />
                </SettingsField>
                <CredentialField key={settings.notulen_provider} credentialKey={`${settings.notulen_provider}_api_key`}
                  label={`${settings.notulen_provider === "openai" ? "OpenAI" : "Anthropic"} API-sleutel`} />
              </div>
            )}
          </div>


    </div><aside className="processing-side">
      <section className="northstar-card"><h3>Jouw pc</h3>{specs ? <dl className="system-specs"><div><dt>Processor</dt><dd>{specs.cpu || "Onbekend"}</dd></div><div><dt>Architectuur</dt><dd>{specs.architecture}</dd></div><div><dt>Geheugen</dt><dd>{specs.memory_gb} GB</dd></div><div><dt>Processorkernen</dt><dd>{specs.threads} threads</dd></div>{specs.free_storage_gb !== null && <div><dt>Opslag vrij</dt><dd>{specs.free_storage_gb} GB</dd></div>}<div><dt>Systeem</dt><dd>{specs.os_version}</dd></div></dl> : <p>{specError || "Systeemgegevens ophalen…"}</p>}</section>
      <section className="northstar-card"><h3>Aanbevolen model</h3><h4>{advice.name}</h4><p>{advice.reason}</p><p>✓ Lokale transcriptie · Nederlands</p><p>{WHISPER_MODELS.find(m => m.id === advice.model)?.size} · CPU-verwerking</p>
        <button className="btn btn-secondary" disabled={downloading} onClick={() => settings.updateSettings({ processing_mode: "local", whisper_model: advice.model })}>Gebruik dit model</button><p>Downloadstatus en modelkeuze staan bij Transcriptie.</p>
      </section>
      <section className="northstar-card"><h3>Privacy & gegevens</h3><h4>Transcriptie</h4><p>{settings.processing_mode === "local" ? "Audio wordt op deze pc omgezet naar tekst." : "Audio wordt naar de ThoughtVault-server geüpload."}</p><h4>Notulen</h4><p>{settings.processing_mode === "cloud" ? "Transcript en notulen worden op de ThoughtVault-server verwerkt." : settings.notulen_provider === "openai" ? "Het transcript wordt naar OpenAI gestuurd. Dit kost apart API-tegoed." : settings.notulen_provider === "anthropic" ? "Het transcript wordt naar Anthropic gestuurd. Dit kost apart API-tegoed." : "Het transcript wordt naar je ingestelde Ollama- of LM Studio-server gestuurd. Bij een externe server verlaat het deze pc."}</p><p>API-sleutels worden uitsluitend in Windows Credential Manager bewaard.</p></section>
    </aside></div>;
}
