import { invoke } from "@tauri-apps/api/core";
import { Code24Regular, Copy24Regular, Edit24Regular } from "../ui/StudioIcons";
import { useSettingsStore } from "../../stores/settingsStore";
import { useToast } from "../ui/InfoBar";
import { CardHead } from "./SettingsFields";

function Toggle({ label, description, checked, onChange, icon, disabled }: { label: string; description: string; checked: boolean; onChange: (value: boolean) => void; icon: React.ReactNode; disabled?: boolean }) {
  return <div className="settings-row">
    <div className="flex-row gap-10 flex-1">
      {icon}
      <div className="flex-1">
        <p className="settings-label">{label}</p>
        <p className="settings-desc">{description}</p>
      </div>
      <label className="toggle-switch">
        <input type="checkbox" role="switch" aria-label={label} aria-checked={checked} checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
        <span className="toggle-slider" />
      </label>
    </div>
  </div>;
}

export function McpTab() {
  const settings = useSettingsStore();
  const toast = useToast();

  async function copy(text: (exe: string) => string, done: string) {
    try {
      await navigator.clipboard.writeText(text(await invoke<string>("mcp_executable_path")));
      toast.show(done, "success");
    } catch {
      toast.show("Kopiëren mislukt", "error");
    }
  }
  const off = !settings.mcp_enabled;

  return <div className="settings-other">
    <header className="settings-section-header"><div><h2>AI-koppeling (MCP)</h2><p>Laat een AI-programma op deze computer, zoals Claude Desktop of Claude Code, je notities lezen. Werkt alleen zolang ThoughtVault open is.</p></div></header>
    <div className="settings-group">
      <CardHead icon={<Code24Regular />} title="AI-koppeling" subtitle="Lokale MCP-server op deze computer" />
      <Toggle icon={<Code24Regular className="settings-icon" />} label="Koppeling aan" description="AI-programma's op deze computer kunnen je notities, profielen, personen en woordenlijst lezen"
        checked={settings.mcp_enabled} onChange={(value) => settings.updateSettings({ mcp_enabled: value })} />
      <Toggle icon={<Edit24Regular className="settings-icon" />} label="Wijzigingen toestaan" description="Ook notities maken en aanpassen, mappen, personen en termen bewaren, en notulen opnieuw laten maken"
        checked={settings.mcp_allow_write} disabled={off} onChange={(value) => settings.updateSettings({ mcp_allow_write: value })} />
      <div className="settings-row">
        <p className="settings-desc">Plak de configuratie in het MCP-instellingenbestand van je AI-programma, of voer de opdracht uit in een terminal voor Claude Code.</p>
        <div className="action-row">
          <button className="btn btn-secondary btn-sm" disabled={off}
            onClick={() => void copy((command) => JSON.stringify({ mcpServers: { thoughtvault: { command, args: ["--mcp"] } } }, null, 2), "Configuratie gekopieerd")}>
            <Copy24Regular style={{ fontSize: 14 }} /> Configuratie kopiëren
          </button>
          <button className="btn btn-secondary btn-sm" disabled={off}
            onClick={() => void copy((exe) => `claude mcp add thoughtvault -- "${exe}" --mcp`, "Opdracht gekopieerd")}>
            <Copy24Regular style={{ fontSize: 14 }} /> Opdracht voor Claude Code kopiëren
          </button>
          <button className="btn btn-secondary btn-sm" disabled={off}
            onClick={() => void copy((exe) => `codex mcp add thoughtvault -- "${exe}" --mcp`, "Opdracht gekopieerd")}>
            <Copy24Regular style={{ fontSize: 14 }} /> Opdracht voor Codex kopiëren
          </button>
        </div>
      </div>
    </div>
  </div>;
}
