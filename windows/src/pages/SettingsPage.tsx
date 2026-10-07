import { useState, useEffect } from "react";
import {
  DocumentText24Regular,
  Info24Regular,
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  ArrowSync24Regular,
  Notebook24Regular,
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

  return (
    <div className="page-scroll">
      {/* Page header */}
      <div className="page-header">
        <h1 className="page-title-sm">Instellingen</h1>
      </div>

      {/* Scrollable settings groups */}
      <div className="page-content">
        <div className="page-content-narrow">

          {/* Profiel — self-profile, separate from notule-Profielen (D-08) */}
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

          <div className="settings-group">
            <p className="settings-group-label">Verwerking</p>
            <div style={{ padding: "12px 14px" }}><LocalModelSetup /></div>
          </div>

          {/* Obsidian */}
          <AIConnections />
          <div className="settings-group">
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

          <div className="settings-group" style={{ padding: 14 }}>
            <p className="settings-group-label">Agenda en updates</p>
            <label>Microsoft client-ID<input className="input" value={settings.ms365_client_id ?? ""} onChange={(e) => settings.updateSettings({ ms365_client_id: e.target.value })} /></label>
            <label>Microsoft tenant-ID<input className="input" value={settings.ms365_tenant_id ?? ""} onChange={(e) => settings.updateSettings({ ms365_tenant_id: e.target.value })} /></label>
            <button className="btn btn-secondary" onClick={() => { if (calendar.isConnected) calendar.disconnect(); else void MicrosoftGraphService.initiateAuth().catch((error) => setCalendarStatus(String(error))); }}>{calendar.isConnected ? "Agenda ontkoppelen" : "Microsoft 365 verbinden"}</button>
            <p role="status">{calendarStatus || calendar.accountEmail}</p>
            <label><input type="checkbox" checked={settings.check_for_updates} onChange={(e) => settings.updateSettings({ check_for_updates: e.target.checked })} /> Controleer op updates</label>
          </div>
          <BrandFooter />

          {/* Over */}
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
