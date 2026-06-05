import { useState, useEffect } from "react";
import {
  Globe24Regular,
  DocumentText24Regular,
  Brain24Regular,
  Calendar24Regular,
  Info24Regular,
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  ArrowSync24Regular,
} from "@fluentui/react-icons";
import { api } from "../services/api";
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

  const hasOAuthConfig = Boolean(settings.ms365_client_id && settings.ms365_tenant_id);

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
                <div style={{ padding: "0 14px 12px" }}>
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
