import { useState } from "react";
import {
  Globe24Regular,
  DocumentText24Regular,
  Brain24Regular,
  Calendar24Regular,
  ChatBubblesQuestion24Regular,
  Info24Regular,
  ChevronRight24Regular,
  ShieldLock24Regular,
  Mail24Regular,
} from "@fluentui/react-icons";
import { useSettingsStore } from "../stores/settingsStore";
import { useAuthStore } from "../stores/authStore";
import { useCalendarStore } from "../stores/calendarStore";
import { useProfilesStore } from "../stores/profilesStore";
import { api } from "../services/api";
import { MicrosoftGraphService } from "../services/microsoftGraph";

export function SettingsPage() {
  const settings = useSettingsStore();
  const { user, logout } = useAuthStore();
  const calendar = useCalendarStore();
  const profiles = useProfilesStore((s) => s.profiles);

  const [serverUrl, setServerUrl] = useState(settings.server_url);
  const [serverSaved, setServerSaved] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);

  const hasOAuthConfig = Boolean(settings.ms365_client_id && settings.ms365_tenant_id);

  function handleSaveServer() {
    settings.updateSettings({ server_url: serverUrl });
    setServerSaved(true);
    setTimeout(() => setServerSaved(false), 2000);
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

  async function handleLogout() {
    await api.logout();
    logout();
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
              <div className="flex-row gap-8">
                <input
                  type="url"
                  value={serverUrl}
                  onChange={(e) => setServerUrl(e.target.value)}
                  placeholder="https://n8n.prezent.nl"
                  className="input"
                />
                <button
                  onClick={handleSaveServer}
                  className="btn btn-accent flex-shrink-0"
                  style={{ padding: "7px 14px", fontSize: 12 }}
                >
                  {serverSaved ? "Opgeslagen" : "Opslaan"}
                </button>
              </div>
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
                      ? "Cloud (N8N + Claude)"
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
                  <option value="cloud">Cloud (N8N + Claude)</option>
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
                    className="btn btn-secondary"
                    style={{ fontSize: 12 }}
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
                    className="btn btn-accent"
                    style={{ padding: "7px 14px", fontSize: 12 }}
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

          {/* Account */}
          <div className="settings-group">
            <p className="settings-group-label">Account</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <div className="avatar avatar-accent">
                  {user?.name?.charAt(0).toUpperCase() || "?"}
                </div>
                <div className="flex-1">
                  <p className="settings-label">{user?.name}</p>
                  <p className="settings-desc">{user?.email}</p>
                </div>
                {user?.role === "admin" && (
                  <span className="status-badge-accent">Admin</span>
                )}
              </div>
            </div>
            <div style={{ padding: "0 14px 12px" }}>
              <button
                onClick={handleLogout}
                className="btn btn-secondary"
                style={{ fontSize: 12, color: "var(--text-error)", borderColor: "rgba(188,0,22,0.3)" }}
              >
                Uitloggen
              </button>
            </div>
          </div>

          {/* Feedback */}
          <div className="settings-group">
            <p className="settings-group-label">Feedback</p>
            <div className="settings-row" style={{ cursor: "default" }}>
              <div className="flex-row gap-10 flex-1">
                <ChatBubblesQuestion24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Bug melden</p>
                  <p className="settings-desc">Meld een probleem of suggestie</p>
                </div>
                <ChevronRight24Regular className="settings-icon-muted" style={{ fontSize: 14 }} />
              </div>
            </div>
          </div>

          {/* Privacy & Gegevens (GDPR) */}
          <div className="settings-group">
            <p className="settings-group-label">Privacy & gegevens</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <ShieldLock24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Gegevens exporteren (AVG)</p>
                  <p className="settings-desc">Download al je opnames en transcripties</p>
                </div>
                <ChevronRight24Regular className="settings-icon-muted" style={{ fontSize: 14 }} />
              </div>
            </div>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Mail24Regular className="settings-icon" style={{ color: "var(--fill-system-critical)" }} />
                <div className="flex-1">
                  <p className="settings-label">Account verwijderen</p>
                  <p className="settings-desc">
                    Neem contact op met{" "}
                    <a
                      href="mailto:support@yinga.nl?subject=Account%20verwijderen%20TranscriptStudio"
                      style={{ color: "var(--text-accent)", textDecoration: "none" }}
                    >
                      support@yinga.nl
                    </a>
                    {" "}om je account te laten verwijderen. Verzoeken worden binnen 30 dagen verwerkt conform de AVG.
                  </p>
                </div>
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
                  <p className="settings-desc">Versie 1.0.10 — Windows (Tauri 2)</p>
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
