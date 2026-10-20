import { Bug24Regular, Person24Regular } from "../ui/StudioIcons";
import { CardHead } from "./SettingsFields";
import FeedbackWidget from "../FeedbackWidget";

export function AccountTab() {
  return <div className="settings-other">
    <header className="settings-section-header"><div><h2>Account</h2><p>Deze app werkt lokaal zonder ThoughtVault-login.</p></div></header>
    <div className="settings-group">
      <CardHead icon={<Person24Regular />} title="Lokale app" subtitle="Je profiel stel je in bij Notulen." />
    </div>
    <div className="settings-group">
      <CardHead icon={<Bug24Regular />} title="Feedback" subtitle="Probleem melden of suggestie" />
      <div className="settings-row"><FeedbackWidget /></div>
    </div>
  </div>;
}
