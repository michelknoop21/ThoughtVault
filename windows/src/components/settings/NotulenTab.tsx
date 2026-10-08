import { ProfilesPage } from "../../pages/ProfilesPage";
import { DocumentText24Regular } from "../ui/StudioIcons";
import { useSettingsStore } from "../../stores/settingsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import { CardHead } from "./SettingsFields";

export function NotulenTab() {
  const settings = useSettingsStore();
  const profiles = useProfilesStore((s) => s.profiles);
  return <div className="settings-other"><header className="settings-section-header"><div><h2>Notulen</h2><p>Kies de standaardstijl voor je notulen.</p></div></header>
    <div className="settings-group">
      <CardHead icon={<DocumentText24Regular />} title="Notulen" subtitle="Standaardprofiel en schrijfstijl" />
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
      <div style={{ padding: "0 14px 14px" }}>
        <div className="form-field">
          <label className="form-label-sm">Standaard notulentemplate</label>
          <select className="select" value={settings.default_profile_id} onChange={e => settings.updateSettings({ default_profile_id: e.target.value })}>{profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select>
        </div>
        <details className="settings-profile-manager"><summary>Profielen beheren</summary><ProfilesPage embedded /></details>
      </div>
    </div>
  </div>;
}
