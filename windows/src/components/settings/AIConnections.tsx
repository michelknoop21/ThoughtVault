import { useState } from "react";
import { PlugConnected24Regular } from "@fluentui/react-icons";
import { useAIConnection, pairAIConnection, updateAIPermissions, disconnectAIConnection, type AIScope } from "../../services/aiConnections";

const rights: { scope: AIScope; label: string; description: string }[] = [
  { scope: "read", label: "Transcripts en notulen lezen", description: "MCP-clients kunnen inhoud ophalen en uitvoer downloaden." },
  { scope: "write", label: "Notulen en sjablonen wijzigen", description: "Wijzigingen opslaan en schermen openen in deze app." },
  { scope: "record", label: "Opnames bedienen", description: "Eenmalig toestaan: starten, pauzeren, hervatten en stoppen. De opname blijft zichtbaar." },
];

export function AIConnections() {
  const { connection, busy, status } = useAIConnection();
  const [selected, setSelected] = useState<AIScope[]>(["read"]);
  const scopes = connection?.scopes ?? selected;
  function change(scope: AIScope, checked: boolean) {
    const updated = checked ? [...scopes, scope] : scopes.filter((value) => value !== scope);
    if (connection) void updateAIPermissions(updated).catch(() => {});
    else setSelected(updated);
  }
  return <section className="settings-group" aria-labelledby="ai-connections-title">
    <p id="ai-connections-title" className="settings-group-label">AI-koppelingen</p>
    <div className="settings-row flex-row gap-10">
      <PlugConnected24Regular className="settings-icon" />
      <div className="flex-1">
        <p className="settings-label">Lokale MCP</p>
        <p className="settings-desc" role="status" style={{ overflowWrap: "anywhere" }}>{status}</p>
      </div>
    </div>
    {rights.map(({ scope, label, description }) => <div className="settings-row flex-row gap-10" key={scope}>
      <div className="flex-1"><label className="settings-label" htmlFor={`ai-${scope}`}>{label}</label><p className="settings-desc">{description}</p></div>
      <label className="toggle-switch">
        <input id={`ai-${scope}`} type="checkbox" role="switch" aria-checked={scopes.includes(scope)} checked={scopes.includes(scope)} disabled={busy}
          onChange={(event) => change(scope, event.target.checked)} /><span className="toggle-slider" />
      </label>
    </div>)}
    <div className="flex-col gap-10" style={{ padding: "12px 14px" }}>
      <p className="settings-desc">Optioneel. Je inhoud blijft op dit apparaat en wordt alleen op verzoek opgehaald. Alleen bereikbaar op deze pc, zonder account. Gebruik een MCP-client met lokale HTTP-ondersteuning en houd ThoughtVault geopend.</p>
      <button className="btn btn-secondary btn-sm" style={{ alignSelf: "flex-start" }} disabled={busy || !connection && scopes.length === 0}
        onClick={() => void (connection ? disconnectAIConnection() : pairAIConnection(scopes)).catch(() => {})}>
        {busy ? "Even wachten…" : connection ? "Ontkoppelen" : "Lokale MCP inschakelen"}
      </button>
      {connection && <button className="btn btn-secondary btn-sm" onClick={() => void navigator.clipboard.writeText(JSON.stringify({ url: "http://127.0.0.1:11219/mcp", headers: { Authorization: `Bearer ${connection.credential}` } }, null, 2))}>Kopieer MCP-configuratie</button>}
      {connection && <p className="settings-desc" style={{ overflowWrap: "anywhere" }}>MCP-server: http://127.0.0.1:11219/mcp</p>}
    </div>
  </section>;
}
