import { useState, useEffect } from "react";
import { ArrowSync24Regular, Info24Regular } from "@fluentui/react-icons";
import { getVersion } from "@tauri-apps/api/app";
import { useSettingsStore } from "../../stores/settingsStore";
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
                  <p className="settings-label">Controleer op updates</p>
                  <p className="settings-desc">Toon een melding op de homepage als er een nieuwe versie beschikbaar is</p>
                </div>
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    role="switch"
                    aria-checked={settings.check_for_updates}
                    checked={settings.check_for_updates}
                    onChange={(e) => settings.updateSettings({ check_for_updates: e.target.checked })}
                  />
                  <span className="toggle-slider" />
                </label>
              </div>
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
                  <p className="settings-desc">Versie {appVersion || "..."} · Windows (Tauri 2)</p>
                </div>
              </div>
            </div>
          </div>
</div>;
}
