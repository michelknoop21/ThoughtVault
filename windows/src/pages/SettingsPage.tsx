import { invoke } from "@tauri-apps/api/core";
import { useState, useEffect } from "react";
import {
  DocumentText24Regular,
  Info24Regular,
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  ArrowSync24Regular,
  Notebook24Regular,
  Settings24Regular,
  Options24Regular,
  Calendar24Regular,
} from "@fluentui/react-icons";
import { useCalendarStore } from "../stores/calendarStore";
import { MicrosoftGraphService } from "../services/microsoftGraph";
import { testObsidian } from "../services/obsidian";
import { useSettingsStore } from "../stores/settingsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { getVersion } from "@tauri-apps/api/app";
import { LocalModelSetup } from "../components/settings/LocalModelSetup";
import { BrandFooter } from "../components/brand/BrandFooter";
import { ProfileSettings } from "../components/settings/ProfileSettings";
import { AIConnections } from "../components/settings/AIConnections";

export function SettingsPage() {
  const [tab, setTab] = useState("Verwerking");
  const [appVersion, setAppVersion] = useState("");

  useEffect(() => {
    getVersion().then(setAppVersion).catch(() => setAppVersion("onbekend"));
  }, []);
  const settings = useSettingsStore();
  const calendar = useCalendarStore();
  const [calendarStatus, setCalendarStatus] = useState("");
  const profiles = useProfilesStore((s) => s.profiles);

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

  return <div className="page-scroll northstar-settings" data-theme="dark">
    <h1>Instellingen</h1>
    <nav className="settings-tabs" aria-label="Instellingen">
      {[["Algemeen", <Settings24Regular />], ["Verwerking", <Options24Regular />], ["Notulen", <DocumentText24Regular />], ["Agenda", <Calendar24Regular />], ["Obsidian", <Notebook24Regular />], ["Geavanceerd", <Settings24Regular />]].map(([name, icon]) => <button key={String(name)} aria-current={tab === name ? "page" : undefined} className={tab === name ? "active" : ""} onClick={() => setTab(String(name))}>{icon}{name}</button>)}
    </nav>
    {tab === "Algemeen" && <div className="settings-other">          {/* Profiel — self-profile, separate from notule-Profielen (D-08) */}
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

</div>}
    {tab === "Notulen" && <div className="settings-other">          {/* Notulen */}
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

</div>}
    {tab === "Verwerking" && <><header className="settings-section-header"><h2>Verwerking</h2><p>Lokale transcriptie, met jouw keuze voor lokale of cloud-AI.</p></header><div className="processing-columns"><div><section className="settings-group"><h3 className="settings-group-label">Transcriptie en notulen</h3><div className="restored-model-settings"><LocalModelSetup /></div></section><AIConnections /></div><ProcessingSide /></div></>}
    {tab === "Obsidian" && <div className="settings-other">          <div className="settings-group">
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

</div>}
    {tab === "Agenda" && <div className="settings-other">          <div className="settings-group" style={{ padding: 14 }}>
            <p className="settings-group-label">Agenda en updates</p>
            <label>Microsoft client-ID<input className="input" value={settings.ms365_client_id ?? ""} onChange={(e) => settings.updateSettings({ ms365_client_id: e.target.value })} /></label>
            <label>Microsoft tenant-ID<input className="input" value={settings.ms365_tenant_id ?? ""} onChange={(e) => settings.updateSettings({ ms365_tenant_id: e.target.value })} /></label>
            <button className="btn btn-secondary" onClick={() => { if (calendar.isConnected) calendar.disconnect(); else void MicrosoftGraphService.initiateAuth().catch((error) => setCalendarStatus(String(error))); }}>{calendar.isConnected ? "Agenda ontkoppelen" : "Microsoft 365 verbinden"}</button>
            <p role="status">{calendarStatus || calendar.accountEmail}</p>
            <label><input type="checkbox" checked={settings.check_for_updates} onChange={(e) => settings.updateSettings({ check_for_updates: e.target.checked })} /> Controleer op updates</label>
          </div>
</div>}
    {tab === "Geavanceerd" && <div className="settings-other">          {/* Over */}
          <div className="settings-group">
            <p className="settings-group-label">Over</p>
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Info24Regular className="settings-icon-muted" />
                <div className="flex-1">
                  <p className="settings-label">ThoughtVault</p>
                  <p className="settings-desc">Versie {appVersion || "..."} · Windows · Lokale opslag en transcriptie</p>
                </div>
              </div>
            </div>
          </div>
</div>}
    <BrandFooter />
  </div>;
}

interface SystemSpecs { cpu: string; architecture: string; memory_gb: number; threads: number; os_version: string; free_storage_gb: number | null; }
function ProcessingSide() {
  const [specs, setSpecs] = useState<SystemSpecs | null>(null);
  const [error, setError] = useState("");
  useEffect(() => { let active = true; invoke<SystemSpecs>("get_system_specs").then(value => { if(active) setSpecs(value); }).catch(() => { if(active) setError("Systeemgegevens niet beschikbaar."); }); return () => { active = false; }; }, []);
  const medium = Boolean(specs && specs.memory_gb >= 16 && specs.threads >= 8);
  return <aside className="processing-side" aria-label="Jouw pc en modeladvies">
    <section className="northstar-card"><h3>Jouw pc</h3>{specs ? <dl className="system-specs">{[["Processor", specs.cpu], ["Architectuur", specs.architecture], ["Geheugen", `${specs.memory_gb} GB`], ["Processorkernen", specs.threads], ["Windows", specs.os_version], ...(specs.free_storage_gb === null ? [] : [["Opslag vrij", `${specs.free_storage_gb} GB`]])].map(([label,value]) => <div key={String(label)}><dt>{label}</dt><dd>{value}</dd></div>)}</dl> : <p role="status">{error || "Systeemgegevens laden…"}</p>}</section>
    <section className="northstar-card"><h3>Aanbevolen model</h3><h4>{medium ? "Whisper Medium" : "Whisper Small"}</h4><p>{medium ? "Voldoende geheugen en processorkernen voor Medium." : "Small vraagt minder geheugen en is een veilige start."} Je kiest het model zelf bij transcriptie.</p></section>
    <section className="northstar-card"><h3>Jouw gegevens</h3><p>Opnames, transcriptie en opslag blijven op deze pc. Kies je cloud-AI voor notulen, dan wordt de transcriptie naar die provider gestuurd.</p></section>
  </aside>;
}

function SettingsField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="form-field">
      <label className="form-label-sm">{label}</label>
      {children}
    </div>
  );
}
