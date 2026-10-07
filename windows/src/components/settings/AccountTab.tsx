import { ArrowSync24Regular, Person24Regular } from "@fluentui/react-icons";
import { useSettingsStore } from "../../stores/settingsStore";
import { ProfileSettings } from "./ProfileSettings";
import { CardHead } from "./SettingsFields";

export function AccountTab() {
  const settings = useSettingsStore();
  return <div className="settings-other"><header className="settings-section-header"><div><h2>Account</h2><p>Je profiel en de welkomststappen.</p></div></header>          {/* Profiel — self-profile, separate from notule-Profielen (D-08) */}
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
