import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  Globe24Regular,
  DocumentText24Regular,
  Calendar24Regular,
  Info24Regular,
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  ArrowSync24Regular,
  Laptop24Regular,
  Notebook24Regular,
} from "@fluentui/react-icons";
import { useNavigate } from "react-router-dom";
import { transcriptionAdvice } from "../services/processingAdvice";
import type { SystemSpecs } from "../services/tauriCommands";
import { WHISPER_MODELS } from "../types";
import { api } from "../services/api";
import { testObsidian } from "../services/obsidian";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useCalendarStore } from "../stores/calendarStore";
import { useProfilesStore } from "../stores/profilesStore";
import { MicrosoftGraphService } from "../services/microsoftGraph";
import { getVersion } from "@tauri-apps/api/app";
import { ProfileSettings } from "../components/settings/ProfileSettings";
import { loadCredential, storeCredential, deleteCredential } from "../services/tauriCommands";

export function SettingsPage() {
  const navigate = useNavigate();
  const [tab, setTab] = useState("Verwerking");
  const [specs, setSpecs] = useState<SystemSpecs | null>(null);
  const [specError, setSpecError] = useState("");
  const [setupDetails, setSetupDetails] = useState(false);
  const [modelError, setModelError] = useState("");
  const advice = transcriptionAdvice(specs);
  useEffect(() => { invoke<SystemSpecs>("get_system_specs").then(setSpecs).catch(() => setSpecError("Systeemgegevens niet beschikbaar")); }, []);
  const [appVersion, setAppVersion] = useState("");

  useEffect(() => {
    getVersion().then(setAppVersion).catch(() => setAppVersion("onbekend"));
  }, []);
  const settings = useSettingsStore();
  const isTranscribing = useRecordingStore(s => s.backgroundTasks.some(task => task.status === "transcribing" || task.status === "downloading"));
  const calendar = useCalendarStore();
  const profiles = useProfilesStore((s) => s.profiles);

  const [serverUrl, setServerUrl] = useState(settings.server_url);
  const [serverSaved, setServerSaved] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<"idle" | "testing" | "success" | "error">("idle");
  const [isConnecting, setIsConnecting] = useState(false);
  const [obsidianTestStatus, setObsidianTestStatus] = useState<"idle" | "testing" | "success" | "error">("idle");
  const [ollamaTestStatus, setOllamaTestStatus] = useState<"idle" | "testing" | "success" | "error">("idle");

  const hasOAuthConfig = Boolean(settings.ms365_client_id && settings.ms365_tenant_id);

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

  function validateUrl(url: string): string | null {
    if (!url.trim()) return "URL mag niet leeg zijn";
    try {
      const parsed = new URL(url);
      if (parsed.protocol !== "https:") return "URL moet HTTPS gebruiken";
      return null;
    } catch {
      return "Ongeldig URL-formaat";
    }
  }

  function handleSaveServer() {
    const error = validateUrl(serverUrl);
    if (error) {
      setServerError(error);
      return;
    }
    setServerError(null);
    settings.updateSettings({ server_url: serverUrl });
    setServerSaved(true);
    setTimeout(() => setServerSaved(false), 2000);
  }

  async function handleTestConnection() {
    const error = validateUrl(serverUrl);
    if (error) {
      setServerError(error);
      return;
    }
    setServerError(null);
    setConnectionStatus("testing");
    try {
      const health = await api.getSystemHealth();
      setConnectionStatus(health.api_status !== "down" ? "success" : "error");
    } catch {
      setConnectionStatus("error");
    }
    setTimeout(() => setConnectionStatus("idle"), 3000);
  }

  async function handleTestObsidian() {
    setObsidianTestStatus("testing");
    try {
      await testObsidian(settings);
      setObsidianTestStatus("success");
    } catch {
      setObsidianTestStatus("error");
    }
    setTimeout(() => setObsidianTestStatus("idle"), 3000);
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

  async function handleConnect365() {
    setIsConnecting(true);
    try {
      await MicrosoftGraphService.initiateAuth();
    } catch (err) {
      console.error("Auth failed:", err);
    } finally {
      setIsConnecting(false);
    }
  }

  return <div className="page-scroll northstar-settings">
    <h1>Instellingen</h1>
    <nav className="settings-tabs" aria-label="Instellingen">{["Algemeen", "Verwerking", "Notulen", "Agenda", "Obsidian", "Account", "Geavanceerd"].map(value => <button key={value} aria-current={tab === value ? "page" : undefined} className={tab === value ? "active" : ""} onClick={() => setTab(value)}>{value}</button>)}</nav>
    {tab === "Verwerking" && <div className="processing-columns"><div>
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
            <p className="settings-group-label">Verwerking</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Laptop24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Verwerkingsmodus</p>
                  <p className="settings-desc">
                    {settings.processing_mode === "local"
                      ? "Audio blijft op deze pc; kies apart de aanbieder voor notulen"
                      : "Cloud: transcriptie en notulen via de bestaande server"}
                  </p>
                </div>
                <select
                  value={settings.processing_mode}
                  onChange={(e) => {
                    const mode = e.target.value as "cloud" | "local";
                    // Switching to local with the cloud provider still selected
                    // would fail at notule generation — move it to Ollama.
                    const patch: Partial<typeof settings> = { processing_mode: mode };
                    if (mode === "local" && settings.notulen_provider === "cloud") {
                      patch.notulen_provider = "ollama";
                    }
                    settings.updateSettings(patch);
                  }}
                  className="select"
                >
                  <option value="cloud">Cloud</option>
                  <option value="local">Lokaal</option>
                </select>
              </div>
            </div>

            {settings.processing_mode === "local" && (
              <>
                <div style={{ padding: "0 14px 4px" }}>
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
                <div style={{ padding: "0 14px 12px", display: "flex", flexDirection: "column", gap: 6 }}>
                  {downloading ? (
                    <><p className="settings-desc" style={{ margin: 0 }}>Downloaden… {dlPct}%</p>
                      <progress value={dlPct} max={100} aria-label="Modeldownload" />
                      <button className="btn btn-secondary btn-sm" onClick={() => invoke("cancel_whisper_download").catch(err => setModelError(String(err)))}>Annuleren</button></>
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
                        if (!confirm(`Gedownload model ${model.label} verwijderen? Je kunt het later opnieuw downloaden.`)) return;
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
            <p className="settings-group-label">Notulen generatie</p>
            <p className="settings-desc" style={{ padding: "0 20px 12px" }}>Maak gestructureerde notulen van het transcript.</p>
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
                <div style={{ padding: "0 14px 4px" }}>
                  <SettingsField label="Ollama URL">
                    <input
                      type="url"
                      value={settings.ollama_url}
                      onChange={(e) => settings.updateSettings({ ollama_url: e.target.value })}
                      className="input"
                    />
                  </SettingsField>
                </div>
                <div style={{ padding: "0 14px 4px" }}>
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
                <div style={{ padding: "0 14px 4px" }}>
                  <CredentialField credentialKey="ollama_api_key" label="API-sleutel (alleen Ollama Cloud)" />
                </div>
                <div style={{ padding: "0 14px 12px" }}>
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
                </div>
              </>
            )}

            {settings.processing_mode === "local" && settings.notulen_provider === "lm-studio" && (
              <>
                <div style={{ padding: "0 14px 4px" }}>
                  <SettingsField label="LM Studio URL">
                    <input
                      type="url"
                      value={settings.lm_studio_url}
                      onChange={(e) => settings.updateSettings({ lm_studio_url: e.target.value })}
                      className="input"
                    />
                  </SettingsField>
                </div>
                <div style={{ padding: "0 14px 12px" }}>
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
              <div style={{ padding: "0 14px 12px" }}>
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
    </aside></div>}
    {tab === "Algemeen" && <div className="settings-other"><h2>Algemeen</h2>          {/* Updates */}
          <div className="settings-group">
            <p className="settings-group-label">Updates</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <ArrowSync24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Controleer op updates</p>
                  <p className="settings-desc">Toon een melding op de homepage als er een nieuwe versie beschikbaar is</p>
                </div>
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    role="switch"
                    aria-checked={settings.check_for_updates}
                    checked={settings.check_for_updates}
                    onChange={(e) => settings.updateSettings({ check_for_updates: e.target.checked })}
                  />
                  <span className="toggle-slider" />
                </label>
              </div>
            </div>
          </div>

          {/* Over */}
          <div className="settings-group">
            <p className="settings-group-label">Over</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Info24Regular className="settings-icon-muted" />
                <div className="flex-1">
                  <p className="settings-label">ThoughtVault</p>
                  <p className="settings-desc">Versie {appVersion || "..."} · Windows (Tauri 2)</p>
                </div>
              </div>
            </div>
          </div>
</div>}
    {tab === "Notulen" && <div className="settings-other"><h2>Notulen</h2>          {/* Notulen */}
          <div className="settings-group">
            <p className="settings-group-label">Notulen</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <DocumentText24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Profiel</p>
                  <p className="settings-desc">Schrijfstijl voor notulen</p>
                </div>
                <span className="text-caption flex-shrink-0">
                  {profiles.length} {profiles.length === 1 ? "profiel" : "profielen"}
                </span>
              </div>
            </div>
          </div>

<section className="northstar-card"><label>Standaard notulentemplate<select className="select" value={settings.default_profile_id} onChange={e => settings.updateSettings({ default_profile_id: e.target.value })}>{profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label><button className="studio-link" onClick={() => navigate("/profiles")}>Profielen beheren →</button></section></div>}
    {tab === "Agenda" && <div className="settings-other"><h2>Agenda</h2>          {/* Agenda */}
          <div className="settings-group">
            <p className="settings-group-label">Agenda</p>
            {calendar.isConnected ? (
              <>
                <div className="settings-row">
                  <div className="flex-row gap-10 flex-1">
                    <Calendar24Regular className="settings-icon" style={{ color: "var(--fill-system-success)" }} />
                    <div className="flex-1">
                      <p className="settings-label">Microsoft 365</p>
                      <p className="settings-desc-success">
                        Verbonden: {calendar.accountEmail}
                      </p>
                    </div>
                  </div>
                </div>
                <div style={{ padding: "0 14px 12px" }}>
                  <button
                    onClick={() => calendar.disconnect()}
                    className="btn btn-secondary btn-sm"
                  >
                    Verbinding verbreken
                  </button>
                </div>
              </>
            ) : hasOAuthConfig ? (
              <>
                <div className="settings-row">
                  <div className="flex-row gap-10 flex-1">
                    <Calendar24Regular className="settings-icon-muted" />
                    <div className="flex-1">
                      <p className="settings-label">Microsoft 365</p>
                      <p className="settings-desc">Niet verbonden</p>
                    </div>
                  </div>
                </div>
                <div style={{ padding: "0 14px 12px" }}>
                  <button
                    onClick={handleConnect365}
                    disabled={isConnecting}
                    className="btn btn-accent btn-sm"
                  >
                    {isConnecting ? "Verbinden..." : "Verbinden met Microsoft 365"}
                  </button>
                </div>
              </>
            ) : (
              <div className="settings-row">
                <div className="flex-row gap-10 flex-1">
                  <Calendar24Regular className="settings-icon-muted" />
                  <div className="flex-1">
                    <p className="settings-label">Microsoft 365</p>
                    <p className="settings-desc">
                      Agenda-koppeling niet geconfigureerd. Neem contact op met de beheerder.
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>

</div>}
    {tab === "Obsidian" && <div className="settings-other"><h2>Obsidian</h2>          {/* Obsidian */}
          <div className="settings-group">
            <p className="settings-group-label">Obsidian-koppeling</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Notebook24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Automatisch exporteren naar Obsidian</p>
                  <p className="settings-desc">Schrijf elke nieuwe notule naar je Obsidian-vault</p>
                </div>
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    role="switch"
                    aria-checked={settings.obsidian_enabled}
                    checked={settings.obsidian_enabled}
                    onChange={(e) => settings.updateSettings({ obsidian_enabled: e.target.checked })}
                  />
                  <span className="toggle-slider" />
                </label>
              </div>
            </div>
            <div style={{ padding: "0 14px 4px" }}>
              <SettingsField label="Base-URL">
                <input
                  type="url"
                  value={settings.obsidian_base_url}
                  onChange={(e) => settings.updateSettings({ obsidian_base_url: e.target.value })}
                  placeholder="https://127.0.0.1:27124"
                  className="input"
                />
              </SettingsField>
            </div>
            <div style={{ padding: "0 14px 4px" }}>
              <SettingsField label="Vault-pad">
                <input
                  type="text"
                  value={settings.obsidian_vault_path}
                  onChange={(e) => settings.updateSettings({ obsidian_vault_path: e.target.value })}
                  placeholder="Notulen"
                  className="input"
                />
              </SettingsField>
            </div>
            <div style={{ padding: "0 14px 4px" }}>
              <CredentialField credentialKey="obsidian_api_key" label="API-sleutel" />
            </div>
            <div style={{ padding: "0 14px 12px" }}>
              <button
                onClick={handleTestObsidian}
                className="btn btn-secondary btn-sm"
                disabled={obsidianTestStatus === "testing"}
                style={{ alignSelf: "flex-start" }}
              >
                {obsidianTestStatus === "testing" ? "Testen..." :
                 obsidianTestStatus === "success" ? <><CheckmarkCircle24Regular style={{ fontSize: 14 }} /> Verbonden</> :
                 obsidianTestStatus === "error" ? <><ErrorCircle24Regular style={{ fontSize: 14 }} /> Niet bereikbaar</> :
                 "Test verbinding"}
              </button>
            </div>
          </div>

</div>}
    {tab === "Account" && <div className="settings-other"><h2>Account</h2>          {/* Profiel — self-profile, separate from notule-Profielen (D-08) */}
          <div className="settings-group">
            <p className="settings-group-label">Profiel</p>
            <div style={{ padding: "12px 14px" }}>
              <ProfileSettings />
            </div>
            {/* Onboarding re-entry — in local-only mode there is no login window,
                so the onboarding flow must be reachable from Settings. */}
            <div style={{ padding: "0 14px 12px", display: "flex", flexDirection: "column", gap: 6 }}>
              <button
                onClick={() => settings.setHasCompletedOnboarding(false)}
                className="btn btn-secondary btn-sm"
                style={{ alignSelf: "flex-start" }}
              >
                <ArrowSync24Regular style={{ fontSize: 14 }} /> Onboarding opnieuw doorlopen
              </button>
              <p className="settings-desc" style={{ margin: 0 }}>
                Doorloop de welkomststappen opnieuw, bijvoorbeeld om je profiel opnieuw in te stellen.
              </p>
            </div>
          </div>

</div>}
    {tab === "Geavanceerd" && <div className="settings-other"><h2>Geavanceerd</h2>          {/* Verbinding */}
          <div className="settings-group">
            <p className="settings-group-label">Verbinding</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Globe24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Server URL</p>
                  <p className="settings-desc">Backend verbinding</p>
                </div>
              </div>
            </div>
            <div style={{ padding: "0 14px 12px" }}>
              <div className="flex-col gap-6">
                <div className="flex-row gap-8">
                  <input
                    type="url"
                    value={serverUrl}
                    onChange={(e) => { setServerUrl(e.target.value); setServerError(null); }}
                    placeholder="https://n8n.prezent.nl/tstudio/api"
                    className="input"
                  />
                  <button
                    onClick={handleSaveServer}
                    className="btn btn-accent btn-sm flex-shrink-0"
                  >
                    {serverSaved ? "Opgeslagen" : "Opslaan"}
                  </button>
                </div>
                {serverError && (
                  <p style={{ color: "var(--fill-system-critical)", fontSize: "var(--font-caption)", margin: 0 }}>
                    {serverError}
                  </p>
                )}
                <button
                  onClick={handleTestConnection}
                  className="btn btn-secondary btn-sm"
                  disabled={connectionStatus === "testing"}
                  style={{ alignSelf: "flex-start" }}
                >
                  {connectionStatus === "testing" ? "Testen..." :
                   connectionStatus === "success" ? <><CheckmarkCircle24Regular style={{ fontSize: 14 }} /> Verbonden</> :
                   connectionStatus === "error" ? <><ErrorCircle24Regular style={{ fontSize: 14 }} /> Niet bereikbaar</> :
                   "Test verbinding"}
                </button>
              </div>
            </div>
          </div>

</div>}
  </div>;
}

function SettingsField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="form-field">
      <label className="form-label-sm">{label}</label>
      {children}
    </div>
  );
}

function CredentialField({ credentialKey, label }: { credentialKey: string; label: string }) {
  const [draft, setDraft] = useState("");
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    loadCredential(credentialKey).then((key) => { if (active) setSaved(Boolean(key)); })
      .catch(() => { if (active) setError("Sleutelopslag niet beschikbaar"); });
    return () => { active = false; };
  }, [credentialKey]);

  async function save() {
    try {
      await storeCredential(credentialKey, draft.trim());
      setDraft("");
      setSaved(true);
      setError("");
    } catch {
      setError("Opslaan in Windows Credential Manager mislukt");
    }
  }

  async function remove() {
    try {
      await deleteCredential(credentialKey);
      setDraft("");
      setSaved(false);
      setError("");
    } catch {
      setError("Verwijderen uit Windows Credential Manager mislukt");
    }
  }

  return <SettingsField label={label}>
    <input className="input" type="password" value={draft} onChange={(e) => setDraft(e.target.value)}
      placeholder={saved ? "Sleutel opgeslagen · vul in om te vervangen" : "API-sleutel invoeren"} />
    <div style={{ display: "flex", gap: 8, marginTop: 6 }}>
      <button className="btn btn-secondary btn-sm" disabled={!draft.trim()} onClick={save}>Opslaan</button>
      {saved && <button className="btn btn-secondary btn-sm" onClick={remove}>Verwijderen</button>}
    </div>
    {error && <p className="settings-desc" role="alert">{error}</p>}
  </SettingsField>;
}
