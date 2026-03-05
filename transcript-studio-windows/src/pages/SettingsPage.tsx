import { useState } from "react";
import {
  Server24Regular,
  Brain24Regular,
  Person24Regular,
  Calendar24Regular,
  Info24Regular,
} from "@fluentui/react-icons";
import { useSettingsStore } from "../stores/settingsStore";
import { useAuthStore } from "../stores/authStore";
import { useCalendarStore } from "../stores/calendarStore";
import { api } from "../services/api";
import { MicrosoftGraphService } from "../services/microsoftGraph";

type Tab = "server" | "llm" | "account" | "agenda" | "over";

const TABS: { id: Tab; label: string; icon: React.ReactNode }[] = [
  { id: "server", label: "Server", icon: <Server24Regular style={{ fontSize: 16 }} /> },
  { id: "llm", label: "LLM", icon: <Brain24Regular style={{ fontSize: 16 }} /> },
  { id: "account", label: "Account", icon: <Person24Regular style={{ fontSize: 16 }} /> },
  { id: "agenda", label: "Agenda", icon: <Calendar24Regular style={{ fontSize: 16 }} /> },
  { id: "over", label: "Over", icon: <Info24Regular style={{ fontSize: 16 }} /> },
];

export function SettingsPage() {
  const [activeTab, setActiveTab] = useState<Tab>("server");

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

      {/* Tab bar */}
      <div
        style={{
          display: "flex",
          gap: 2,
          padding: "8px 12px",
          background: "var(--surface-card)",
          borderBottom: "1px solid var(--stroke-divider)",
          flexShrink: 0,
        }}
      >
        {TABS.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 6,
              padding: "6px 14px",
              fontSize: 13,
              fontWeight: activeTab === tab.id ? 600 : 400,
              borderRadius: "var(--radius-sm)",
              border: "none",
              cursor: "pointer",
              transition: "background 67ms ease, color 67ms ease",
              background: activeTab === tab.id ? "var(--fill-accent-default)" : "transparent",
              color: activeTab === tab.id ? "#fff" : "var(--text-secondary)",
            }}
            onMouseEnter={(e) => {
              if (activeTab !== tab.id)
                (e.currentTarget as HTMLButtonElement).style.background = "var(--fill-control-secondary)";
            }}
            onMouseLeave={(e) => {
              if (activeTab !== tab.id)
                (e.currentTarget as HTMLButtonElement).style.background = "transparent";
            }}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div style={{ flex: 1, overflowY: "auto", padding: 24 }}>
        {activeTab === "server" && <ServerTab />}
        {activeTab === "llm" && <LLMTab />}
        {activeTab === "account" && <AccountTab />}
        {activeTab === "agenda" && <AgendaTab />}
        {activeTab === "over" && <OverTab />}
      </div>
    </div>
  );
}

function ServerTab() {
  const settings = useSettingsStore();
  const [serverUrl, setServerUrl] = useState(settings.server_url);
  const [saved, setSaved] = useState(false);

  function handleSave() {
    settings.updateSettings({ server_url: serverUrl });
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }

  return (
    <div style={{ maxWidth: 480, display: "flex", flexDirection: "column", gap: 20 }}>
      <SettingsSection title="Server configuratie">
        <SettingsField label="Server URL" description="URL van de TranscriptStudio backend">
          <input
            type="url"
            value={serverUrl}
            onChange={(e) => setServerUrl(e.target.value)}
            placeholder="https://n8n.prezent.nl"
            style={inputStyle}
          />
        </SettingsField>
        <button
          onClick={handleSave}
          className="btn btn-accent"
          style={{ alignSelf: "flex-start", padding: "7px 16px" }}
        >
          {saved ? "Opgeslagen ✓" : "Opslaan"}
        </button>
      </SettingsSection>
    </div>
  );
}

function LLMTab() {
  const settings = useSettingsStore();

  return (
    <div style={{ maxWidth: 480, display: "flex", flexDirection: "column", gap: 24 }}>
      <SettingsSection title="Notulen provider">
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {(["cloud", "ollama", "lm-studio"] as const).map((provider) => (
            <label
              key={provider}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                padding: "10px 14px",
                border: `1px solid ${settings.notulen_provider === provider ? "var(--fill-accent-default)" : "var(--stroke-card)"}`,
                borderRadius: "var(--radius-md)",
                cursor: "pointer",
                background: settings.notulen_provider === provider ? "rgba(229,0,116,0.05)" : "var(--surface-card)",
                transition: "border-color 67ms ease, background 67ms ease",
              }}
            >
              <input
                type="radio"
                name="provider"
                value={provider}
                checked={settings.notulen_provider === provider}
                onChange={() => settings.updateSettings({ notulen_provider: provider })}
                style={{ accentColor: "var(--fill-accent-default)" }}
              />
              <div>
                <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>
                  {provider === "cloud" ? "Cloud (N8N + Claude)" : provider === "ollama" ? "Ollama (lokaal)" : "LM Studio (lokaal)"}
                </p>
                <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>
                  {provider === "cloud" ? "Verwerkt via de server" : "Volledig lokaal, geen data naar server"}
                </p>
              </div>
            </label>
          ))}
        </div>
      </SettingsSection>

      {settings.notulen_provider === "ollama" && (
        <SettingsSection title="Ollama configuratie">
          <SettingsField label="Ollama URL">
            <input
              type="url"
              value={settings.ollama_url}
              onChange={(e) => settings.updateSettings({ ollama_url: e.target.value })}
              style={inputStyle}
            />
          </SettingsField>
          <SettingsField label="Model">
            <input
              type="text"
              value={settings.ollama_model}
              onChange={(e) => settings.updateSettings({ ollama_model: e.target.value })}
              placeholder="llama3.2"
              style={inputStyle}
            />
          </SettingsField>
        </SettingsSection>
      )}

      {settings.notulen_provider === "lm-studio" && (
        <SettingsSection title="LM Studio configuratie">
          <SettingsField label="LM Studio URL">
            <input
              type="url"
              value={settings.lm_studio_url}
              onChange={(e) => settings.updateSettings({ lm_studio_url: e.target.value })}
              style={inputStyle}
            />
          </SettingsField>
          <SettingsField label="Model">
            <input
              type="text"
              value={settings.lm_studio_model}
              onChange={(e) => settings.updateSettings({ lm_studio_model: e.target.value })}
              placeholder="local-model"
              style={inputStyle}
            />
          </SettingsField>
        </SettingsSection>
      )}
    </div>
  );
}

function AccountTab() {
  const { user, logout } = useAuthStore();

  async function handleLogout() {
    await api.logout();
    logout();
  }

  return (
    <div style={{ maxWidth: 480, display: "flex", flexDirection: "column", gap: 20 }}>
      <SettingsSection title="Account">
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div
            className="card"
            style={{ display: "flex", alignItems: "center", gap: 12, padding: "12px 14px" }}
          >
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: "50%",
                background: "var(--fill-accent-default)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "#fff",
                fontWeight: 600,
                fontSize: 16,
                flexShrink: 0,
              }}
            >
              {user?.name?.charAt(0).toUpperCase() || "?"}
            </div>
            <div>
              <p style={{ fontSize: 14, fontWeight: 500, color: "var(--text-primary)" }}>{user?.name}</p>
              <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>{user?.email}</p>
              {user?.role === "admin" && (
                <p style={{ fontSize: 12, color: "var(--fill-accent-default)", fontWeight: 500, marginTop: 1 }}>
                  Administrator
                </p>
              )}
            </div>
          </div>
          <button
            onClick={handleLogout}
            className="btn btn-secondary"
            style={{ alignSelf: "flex-start", color: "var(--text-error)", borderColor: "rgba(188,0,22,0.4)" }}
          >
            Uitloggen
          </button>
        </div>
      </SettingsSection>
    </div>
  );
}

function AgendaTab() {
  const calendar = useCalendarStore();
  const settings = useSettingsStore();
  const [tenantId, setTenantId] = useState(settings.ms365_tenant_id || "");
  const [clientId, setClientId] = useState(settings.ms365_client_id || "");
  const [isConnecting, setIsConnecting] = useState(false);

  async function handleConnect() {
    settings.updateSettings({ ms365_tenant_id: tenantId, ms365_client_id: clientId });
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
    <div style={{ maxWidth: 480, display: "flex", flexDirection: "column", gap: 20 }}>
      {calendar.isConnected ? (
        <SettingsSection title="Microsoft 365">
          <div
            className="card"
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              padding: "10px 14px",
              border: "1px solid rgba(15, 123, 15, 0.30)",
              background: "rgba(15, 123, 15, 0.06)",
            }}
          >
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: "var(--fill-system-success)", flexShrink: 0 }} />
            <div>
              <p style={{ fontSize: 13, fontWeight: 500, color: "var(--text-primary)" }}>Verbonden</p>
              <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 1 }}>{calendar.accountEmail}</p>
            </div>
          </div>
          <button
            onClick={() => calendar.disconnect()}
            className="btn btn-secondary"
            style={{ alignSelf: "flex-start" }}
          >
            Verbinding verbreken
          </button>
        </SettingsSection>
      ) : (
        <SettingsSection title="Microsoft 365 koppelen">
          <p style={{ fontSize: 13, color: "var(--text-tertiary)", marginBottom: 4 }}>
            Koppel uw Microsoft 365 account om aankomende vergaderingen te zien.
          </p>
          <SettingsField label="Tenant ID">
            <input
              type="text"
              value={tenantId}
              onChange={(e) => setTenantId(e.target.value)}
              placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
              style={inputStyle}
            />
          </SettingsField>
          <SettingsField label="Client ID">
            <input
              type="text"
              value={clientId}
              onChange={(e) => setClientId(e.target.value)}
              placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
              style={inputStyle}
            />
          </SettingsField>
          <button
            onClick={handleConnect}
            disabled={!tenantId || !clientId || isConnecting}
            className="btn btn-accent"
            style={{ alignSelf: "flex-start", padding: "7px 16px" }}
          >
            {isConnecting ? "Verbinden..." : "Verbinden met Microsoft 365"}
          </button>
        </SettingsSection>
      )}
    </div>
  );
}

function OverTab() {
  return (
    <div style={{ maxWidth: 480 }}>
      <SettingsSection title="Over TranscriptStudio">
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {[
            { label: "Versie", value: "0.1.0" },
            { label: "Platform", value: "Windows (Tauri 2)" },
            { label: "Ontwikkeld door", value: "Prezent Internet B.V." },
          ].map(({ label, value }) => (
            <div key={label} style={{ display: "flex", gap: 8 }}>
              <span style={{ fontSize: 13, color: "var(--text-tertiary)", minWidth: 120 }}>{label}</span>
              <span style={{ fontSize: 13, color: "var(--text-primary)", fontWeight: 500 }}>{value}</span>
            </div>
          ))}
        </div>
      </SettingsSection>
    </div>
  );
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <p style={{ fontSize: 11, fontWeight: 600, color: "var(--text-tertiary)", textTransform: "uppercase", letterSpacing: "0.06em" }}>
        {title}
      </p>
      {children}
    </div>
  );
}

function SettingsField({ label, description, children }: { label: string; description?: string; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
      <label style={{ fontSize: 13, fontWeight: 500, color: "var(--text-secondary)" }}>{label}</label>
      {description && <p style={{ fontSize: 12, color: "var(--text-tertiary)" }}>{description}</p>}
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
