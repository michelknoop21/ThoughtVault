import { useState } from "react";
import {
  Globe24Regular,
  DocumentText24Regular,
  Brain24Regular,
  Calendar24Regular,
  ChatBubblesQuestion24Regular,
  Info24Regular,
  ChevronRight24Regular,
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
    <div style={{ height: "100%", display: "flex", flexDirection: "column" }}>
      {/* Page header */}
      <div
        style={{
          padding: "12px 16px",
          borderBottom: "1px solid var(--stroke-divider)",
          background: "var(--surface-card)",
          flexShrink: 0,
        }}
      >
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--text-primary)", margin: 0 }}>
          Instellingen
        </h1>
      </div>

      {/* Scrollable settings groups */}
      <div style={{ flex: 1, overflowY: "auto", padding: 24 }}>
        <div style={{ maxWidth: 520, display: "flex", flexDirection: "column", gap: 28 }}>

          {/* Verbinding */}
          <div className="settings-group">
            <p className="settings-group-label">Verbinding</p>
            <div className="settings-row">
              <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                <Globe24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)", flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Server URL</p>
                  <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>Backend verbinding</p>
                </div>
              </div>
            </div>
            <div style={{ padding: "0 14px 12px" }}>
              <div style={{ display: "flex", gap: 8 }}>
                <input
                  type="url"
                  value={serverUrl}
                  onChange={(e) => setServerUrl(e.target.value)}
                  placeholder="https://n8n.prezent.nl"
                  style={inputStyle}
                />
                <button
                  onClick={handleSaveServer}
                  className="btn btn-accent"
                  style={{ padding: "7px 14px", fontSize: 12, flexShrink: 0 }}
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
              <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                <DocumentText24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)", flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Profiel</p>
                  <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>Schrijfstijl voor notulen</p>
                </div>
                <span style={{ fontSize: 12, color: "var(--text-tertiary)", flexShrink: 0 }}>
                  {profiles.length} {profiles.length === 1 ? "profiel" : "profielen"}
                </span>
              </div>
            </div>
          </div>

          {/* Notulen generatie */}
          <div className="settings-group">
            <p className="settings-group-label">Notulen generatie</p>
            <div className="settings-row">
              <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                <Brain24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)", flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Provider</p>
                  <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>
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
                  style={selectStyle}
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
                      style={inputStyle}
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
                      style={inputStyle}
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
                      style={inputStyle}
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
                      style={inputStyle}
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
                  <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                    <Calendar24Regular style={{ fontSize: 18, color: "var(--fill-system-success)", flexShrink: 0 }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Microsoft 365</p>
                      <p style={{ fontSize: 12, color: "var(--fill-system-success)", marginTop: 1 }}>
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
                  <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                    <Calendar24Regular style={{ fontSize: 18, color: "var(--text-tertiary)", flexShrink: 0 }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Microsoft 365</p>
                      <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>Niet verbonden</p>
                    </div>
                  </div>
                </div>
                <div style={{ padding: "0 14px 12px" }}>
                  <button
                    onClick={handleConnect365}
                    disabled={isConnecting}
                    className="btn btn-accent"
                    style={{ alignSelf: "flex-start", padding: "7px 14px", fontSize: 12 }}
                  >
                    {isConnecting ? "Verbinden..." : "Verbinden met Microsoft 365"}
                  </button>
                </div>
              </>
            ) : (
              <div className="settings-row">
                <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                  <Calendar24Regular style={{ fontSize: 18, color: "var(--text-tertiary)", flexShrink: 0 }} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Microsoft 365</p>
                    <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>
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
              <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                <div
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: "50%",
                    background: "var(--fill-accent-default)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: "#fff",
                    fontWeight: 600,
                    fontSize: 13,
                    flexShrink: 0,
                  }}
                >
                  {user?.name?.charAt(0).toUpperCase() || "?"}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>{user?.name}</p>
                  <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>{user?.email}</p>
                </div>
                {user?.role === "admin" && (
                  <span className="status-badge-accent" style={{ fontSize: 11 }}>Admin</span>
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
            <div className="settings-row" style={{ cursor: "pointer" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                <ChatBubblesQuestion24Regular style={{ fontSize: 18, color: "var(--fill-accent-default)", flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Bug melden</p>
                  <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>Meld een probleem of suggestie</p>
                </div>
                <ChevronRight24Regular style={{ fontSize: 14, color: "var(--text-tertiary)" }} />
              </div>
            </div>
          </div>

          {/* Over */}
          <div className="settings-group">
            <p className="settings-group-label">Over</p>
            <div className="settings-row">
              <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                <Info24Regular style={{ fontSize: 18, color: "var(--text-tertiary)", flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>TranscriptStudio</p>
                  <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>Versie 0.1.0 — Windows (Tauri 2)</p>
                </div>
              </div>
            </div>
            <div style={{ padding: "4px 14px 12px" }}>
              <p style={{ fontSize: 12, color: "var(--text-tertiary)" }}>
                Ontwikkeld door Prezent Internet B.V.
              </p>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
}

function SettingsField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
      <label style={{ fontSize: 12, fontWeight: 500, color: "var(--text-secondary)" }}>{label}</label>
      {children}
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "7px 10px",
  background: "var(--fill-control-default)",
  border: "1px solid var(--stroke-control-secondary)",
  borderBottom: "1px solid var(--stroke-control-default)",
  borderRadius: "var(--radius-sm)",
  color: "var(--text-primary)",
  fontSize: 13,
  outline: "none",
  fontFamily: "inherit",
};

const selectStyle: React.CSSProperties = {
  padding: "6px 10px",
  background: "var(--fill-control-default)",
  border: "1px solid var(--stroke-control-secondary)",
  borderBottom: "1px solid var(--stroke-control-default)",
  borderRadius: "var(--radius-sm)",
  color: "var(--text-primary)",
  fontSize: 12,
  outline: "none",
  fontFamily: "inherit",
  cursor: "pointer",
  flexShrink: 0,
};
