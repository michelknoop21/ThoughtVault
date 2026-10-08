import { ProfilesPage } from "../../pages/ProfilesPage";
import { ProfileSettings } from "./ProfileSettings";
import { ArrowSync24Regular, Person24Regular, DocumentText24Regular } from "../ui/StudioIcons";
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

          <div className="settings-group">
            <CardHead icon={<Person24Regular />} title="Profiel" subtitle="Over jou" />
            <div style={{ padding: "12px 14px" }}>
              <ProfileSettings />
            </div>
            {/* Onboarding re-entry — in local-only mode there is no login window,
                so the onboarding flow must be reachable from Settings. */}
            <div style={{ padding: "0 14px 14px", display: "flex", flexDirection: "column", gap: 6 }}>
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

  </div>;
}
