import { useState } from "react";
import { Notebook24Regular, CheckmarkCircle24Regular, ErrorCircle24Regular } from "@fluentui/react-icons";
import { useSettingsStore } from "../../stores/settingsStore";
import { testObsidian } from "../../services/obsidian";
import { SettingsField, CredentialField, CardHead } from "./SettingsFields";

export function ObsidianTab() {
  const settings = useSettingsStore();
  const [obsidianTestStatus, setObsidianTestStatus] = useState<"idle" | "testing" | "success" | "error">("idle");

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
  return <div className="settings-other"><header className="settings-section-header"><div><h2>Obsidian</h2><p>Schrijf je notulen naar je Obsidian-vault.</p></div></header>          {/* Obsidian */}
          <div className="settings-group">
            <CardHead icon={<Notebook24Regular />} title="Obsidian-koppeling" subtitle="Local REST API-plugin" />
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
            <div style={{ padding: "0 14px 14px" }}>
              <CredentialField credentialKey="obsidian_api_key" label="API-sleutel">
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
              </CredentialField>
            </div>
          </div>

</div>;
}
