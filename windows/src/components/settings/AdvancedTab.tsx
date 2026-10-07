import { useState } from "react";
import { Globe24Regular, CheckmarkCircle24Regular, ErrorCircle24Regular } from "@fluentui/react-icons";
import { useSettingsStore } from "../../stores/settingsStore";
import { api } from "../../services/api";
import { CardHead } from "./SettingsFields";

export function AdvancedTab() {
  const settings = useSettingsStore();
  const [serverUrl, setServerUrl] = useState(settings.server_url);
  const [serverSaved, setServerSaved] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<"idle" | "testing" | "success" | "error">("idle");

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
  return <div className="settings-other"><header className="settings-section-header"><div><h2>Geavanceerd</h2><p>Serververbinding voor ThoughtVault Cloud.</p></div></header>          {/* Verbinding */}
          <div className="settings-group">
            <CardHead icon={<Globe24Regular />} title="Verbinding" subtitle="Server van ThoughtVault Cloud" />
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
                <input
                  type="url"
                  value={serverUrl}
                  onChange={(e) => { setServerUrl(e.target.value); setServerError(null); }}
                  placeholder="https://n8n.prezent.nl/tstudio/api"
                  className="input"
                />
                {serverError && (
                  <p style={{ color: "var(--fill-system-critical)", fontSize: "var(--font-caption)", margin: 0 }}>
                    {serverError}
                  </p>
                )}
                <div className="action-row">
                  <button
                    onClick={handleSaveServer}
                    className="btn btn-accent btn-sm flex-shrink-0"
                  >
                    {serverSaved ? "Opgeslagen" : "Opslaan"}
                  </button>
                  <button
                    onClick={handleTestConnection}
                    className="btn btn-secondary btn-sm"
                    disabled={connectionStatus === "testing"}
                  >
                    {connectionStatus === "testing" ? "Testen..." :
                     connectionStatus === "success" ? <><CheckmarkCircle24Regular style={{ fontSize: 14 }} /> Verbonden</> :
                     connectionStatus === "error" ? <><ErrorCircle24Regular style={{ fontSize: 14 }} /> Niet bereikbaar</> :
                     "Test verbinding"}
                  </button>
                </div>
              </div>
            </div>
          </div>

</div>;
}
