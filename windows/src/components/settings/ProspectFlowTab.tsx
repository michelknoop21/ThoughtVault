import { useState } from "react";
import { DocumentText24Regular, CheckmarkCircle24Regular, ErrorCircle24Regular } from "../ui/StudioIcons";
import { useSettingsStore } from "../../stores/settingsStore";
import { testConnection, PROSPECTFLOW_KEY } from "../../services/prospectFlow";
import { SettingsField, CredentialField, CardHead } from "./SettingsFields";

export function ProspectFlowTab() {
  const settings = useSettingsStore();
  const [status, setStatus] = useState<"idle" | "testing" | "success" | "error">("idle");
  const [error, setError] = useState("");

  async function handleTest() {
    setStatus("testing");
    setError("");
    try {
      await testConnection();
      setStatus("success");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Verbinding mislukt");
      setStatus("error");
    }
  }

  return <div className="settings-other">
    <header className="settings-section-header"><div><h2>Prospect Flow</h2><p>Maak vanuit een notule een conceptofferte in Prospect Flow.</p></div></header>
    <div className="settings-group">
      <CardHead icon={<DocumentText24Regular />} title="Prospect Flow-koppeling" subtitle="Conceptofferte uit notule en transcript" />
      <div style={{ padding: "0 14px 4px" }}>
        <SettingsField label="Basis-URL">
          <input type="url" aria-label="Basis-URL" className="input" value={settings.prospectflow_base_url} placeholder="https://prospectflow.yinga.ai"
            onChange={(e) => settings.updateSettings({ prospectflow_base_url: e.target.value })} />
        </SettingsField>
      </div>
      <div style={{ padding: "0 14px 14px" }}>
        <CredentialField credentialKey={PROSPECTFLOW_KEY} label="API-sleutel">
          <button onClick={handleTest} className="btn btn-secondary btn-sm" disabled={status === "testing"} style={{ alignSelf: "flex-start" }}>
            {status === "testing" ? "Testen..." :
             status === "success" ? <><CheckmarkCircle24Regular style={{ fontSize: 14 }} /> Verbonden</> :
             status === "error" ? <><ErrorCircle24Regular style={{ fontSize: 14 }} /> Mislukt</> :
             "Verbinding testen"}
          </button>
        </CredentialField>
        {status === "error" && error && <p className="settings-desc" role="alert">{error}</p>}
      </div>
    </div>
  </div>;
}
