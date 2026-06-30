import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import {
  Globe24Regular,
  DocumentText24Regular,
  Brain24Regular,
  Calendar24Regular,
  Info24Regular,
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  ArrowSync24Regular,
  Laptop24Regular,
  Notebook24Regular,
} from "@fluentui/react-icons";
import { WHISPER_MODELS } from "../types";
import { api } from "../services/api";
import { testObsidian } from "../services/obsidian";
import { useSettingsStore } from "../stores/settingsStore";
import { useCalendarStore } from "../stores/calendarStore";
import { useProfilesStore } from "../stores/profilesStore";
import { MicrosoftGraphService } from "../services/microsoftGraph";
import { getVersion } from "@tauri-apps/api/app";
import { ProfileSettings } from "../components/settings/ProfileSettings";

export function SettingsPage() {
  const [appVersion, setAppVersion] = useState("");

  useEffect(() => {
    getVersion().then(setAppVersion).catch(() => setAppVersion("onbekend"));
  }, []);
  const settings = useSettingsStore();
  const calendar = useCalendarStore();
  const profiles = useProfilesStore((s) => s.profiles);

  const [serverUrl, setServerUrl] = useState(settings.server_url);
  const [serverSaved, setServerSaved] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<"idle" | "testing" | "success" | "error">("idle");
  const [isConnecting, setIsConnecting] = useState(false);
  const [obsidianTestStatus, setObsidianTestStatus] = useState<"idle" | "testing" | "success" | "error">("idle");

  const hasOAuthConfig = Boolean(settings.ms365_client_id && settings.ms365_tenant_id);

  // Local Whisper model state
  const [modelExists, setModelExists] = useState<boolean | null>(null);
  const [downloading, setDownloading] = useState(false);
  const [dlPct, setDlPct] = useState(0);

  const checkModel = useCallback(async () => {
    try {
      const s = await invoke<{ exists: boolean }>("whisper_model_status", {
        modelId: settings.whisper_model,
      });
      setModelExists(s.exists);
    } catch {
      setModelExists(null);
    }
  }, [settings.whisper_model]);

  useEffect(() => {
    if (settings.processing_mode === "local") checkModel();
  }, [settings.processing_mode, checkModel]);

  async function handleDownloadModel() {
    setDownloading(true);
    setDlPct(0);
    const unlisten = await listen<{ pct: number }>(
      "whisper-download-progress",
      (e) => setDlPct(e.payload.pct ?? 0),
    );
    try {
      await invoke("download_whisper_model", { modelId: settings.whisper_model });
      await checkModel();
    } catch (err) {
      console.error("[Settings] Model download failed:", err);
    } finally {
      unlisten();
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

  return (
    <div className="page-scroll">
      {/* Page header */}
      <div className="page-header">
        <h1 className="page-title-sm">Instellingen</h1>
      </div>

      {/* Scrollable settings groups */}
      <div className="page-content">
        <div className="page-content-narrow">

          {/* Verbinding */}
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

          {/* Profiel — self-profile, separate from notule-Profielen (D-08) */}
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

          {/* Notulen */}
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
                      ? "Lokaal — transcriptie én notulen draaien volledig op dit apparaat"
                      : "Cloud — opname wordt naar de server geüpload"}
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
                      value={settings.whisper_model}
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
                  {modelExists ? (
                    <p className="settings-desc-success" style={{ margin: 0 }}>
                      <CheckmarkCircle24Regular style={{ fontSize: 14, verticalAlign: "middle" }} /> Model gedownload en klaar voor gebruik
                    </p>
                  ) : downloading ? (
                    <p className="settings-desc" style={{ margin: 0 }}>Downloaden… {dlPct}%</p>
                  ) : (
                    <>
                      <button
                        onClick={handleDownloadModel}
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
              </>
            )}
          </div>

          {/* Notulen generatie */}
          <div className="settings-group">
            <p className="settings-group-label">Notulen generatie</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Brain24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Provider</p>
                  <p className="settings-desc">
                    {settings.notulen_provider === "cloud"
                      ? "Cloud"
                      : settings.notulen_provider === "ollama"
                      ? "Ollama (lokaal)"
                      : "LM Studio (lokaal)"}
                  </p>
                </div>
                <select
                  value={settings.notulen_provider}
                  onChange={(e) =>
                    settings.updateSettings({
                      notulen_provider: e.target.value as "cloud" | "ollama" | "lm-studio",
                    })
                  }
                  className="select"
                >
                  <option value="cloud">Cloud</option>
                  <option value="ollama">Ollama (lokaal)</option>
                  <option value="lm-studio">LM Studio (lokaal)</option>
                </select>
              </div>
            </div>

            {settings.notulen_provider === "ollama" && (
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
                <div style={{ padding: "0 14px 12px" }}>
                  <SettingsField label="API-sleutel (alleen voor Ollama Cloud)">
                    <input
                      type="password"
                      value={settings.ollama_api_key}
                      onChange={(e) => settings.updateSettings({ ollama_api_key: e.target.value })}
                      placeholder="Leeg laten voor lokale Ollama"
                      className="input"
                    />
                  </SettingsField>
                </div>
              </>
            )}

            {settings.notulen_provider === "lm-studio" && (
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
          </div>

          {/* Obsidian */}
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
              <SettingsField label="API-sleutel">
                <input
                  type="password"
                  value={settings.obsidian_api_key}
                  onChange={(e) => settings.updateSettings({ obsidian_api_key: e.target.value })}
                  placeholder="Bearer-sleutel uit de Local REST API plugin"
                  className="input"
                />
              </SettingsField>
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

          {/* Agenda */}
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
                        Verbonden — {calendar.accountEmail}
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

          {/* Updates */}
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
                  <p className="settings-label">TranscriptStudio</p>
                  <p className="settings-desc">Versie {appVersion || "..."} — Windows (Tauri 2)</p>
                </div>
              </div>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}

function SettingsField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="form-field">
      <label className="form-label-sm">{label}</label>
      {children}
    </div>
  );
}
