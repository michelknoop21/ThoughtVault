import { useState, useEffect } from "react";
import { ArrowSync24Regular, Info24Regular } from "../ui/StudioIcons";
import { getVersion } from "@tauri-apps/api/app";
import { useSettingsStore } from "../../stores/settingsStore";
import { CHECK_UPDATES_EVENT } from "../../hooks/useUpdateCheck";
import { CardHead } from "./SettingsFields";

export function GeneralTab() {
  const settings = useSettingsStore();
  const [appVersion, setAppVersion] = useState("");

  useEffect(() => {
    getVersion().then(setAppVersion).catch(() => setAppVersion("onbekend"));
  }, []);
  return <div className="settings-other"><header className="settings-section-header"><div><h2>Algemeen</h2><p>Updates en informatie over deze app.</p></div></header>          {/* Updates */}
          <div className="settings-group">
            <CardHead icon={<ArrowSync24Regular />} title="Updates" subtitle="Nieuwe versies" />
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <ArrowSync24Regular className="settings-icon" />
                <div className="flex-1">
                  <p className="settings-label">Automatisch bijwerken</p>
                  <p className="settings-desc">Nieuwe versies worden op de achtergrond gedownload en geïnstalleerd als je ThoughtVault afsluit. Nooit tijdens een opname of verwerking.</p>
                </div>
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    role="switch"
                    aria-label="Automatisch bijwerken"
                    aria-checked={settings.check_for_updates}
                    checked={settings.check_for_updates}
                    onChange={(e) => settings.updateSettings({ check_for_updates: e.target.checked })}
                  />
                  <span className="toggle-slider" />
                </label>
                <button className="btn btn-sm" onClick={() => window.dispatchEvent(new Event(CHECK_UPDATES_EVENT))}>Zoek naar updates</button>
              </div>
            </div>
          </div>

          <div className="settings-group">
            <div className="settings-row">
              <label className="flex-1" htmlFor="waveform-motion">
                <p className="settings-label">Beweging van de geluidsgolf</p>
                <p className="settings-desc">Windows kan beweging ook beperken tijdens een externe verbinding.</p>
              </label>
              <select id="waveform-motion" className="select" value={settings.waveform_motion ?? "system"}
                onChange={e => settings.updateSettings({ waveform_motion: e.target.value as "system" | "full" | "reduced" })}>
                <option value="system">Windows volgen</option>
                <option value="full">Beweging aan</option>
                <option value="reduced">Rustige weergave</option>
              </select>
            </div>
          </div>

          {/* Over */}
          <div className="settings-group">
            <CardHead icon={<Info24Regular />} title="Over" subtitle="Deze installatie" />
            <div className="settings-row">
              <div className="flex-row gap-10 flex-1">
                <Info24Regular className="settings-icon-muted" />
                <div className="flex-1">
                  <p className="settings-label">ThoughtVault</p>
                  <p className="settings-desc">Versie {appVersion || "..."} · Windows</p>
                </div>
              </div>
            </div>
          </div>
</div>;
}
