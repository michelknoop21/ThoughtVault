import { open } from "@tauri-apps/plugin-shell";
import { PRIVACY_URL } from "../../services/supportRelay";
import { useEffect, useState } from "react";
import { isCompleteIdentity, useSupportStore } from "../../stores/supportStore";
import { Bug24Regular, Person24Regular } from "../ui/StudioIcons";
import { CardHead } from "./SettingsFields";
import FeedbackWidget from "../FeedbackWidget";

export function AccountTab() {
  const [privacyError, setPrivacyError] = useState(false);
  const { auto_report, setAutoReport, name, email, setIdentity } = useSupportStore();
  const [draftName, setDraftName] = useState(name);
  const [draftEmail, setDraftEmail] = useState(email);
  useEffect(() => { setDraftName(name); setDraftEmail(email); }, [name, email]);
  function saveContact() {
    if (isCompleteIdentity(draftName, draftEmail)) {
      setIdentity(draftName.trim(), draftEmail.trim());
      setDraftName(draftName.trim());
      setDraftEmail(draftEmail.trim());
    }
  }
  return <div className="settings-other">
    <header className="settings-section-header"><div><h2>Account</h2><p>Deze app werkt lokaal zonder ThoughtVault-login.</p></div></header>
    <div className="settings-group">
      <CardHead icon={<Person24Regular />} title="Lokale app" subtitle="Je profiel stel je in bij Notulen." />
    </div>
    <div className="settings-group">
      <CardHead icon={<Bug24Regular />} title="Feedback" subtitle="Probleem melden of suggestie" />
      <div className="settings-row">
        <div className="flex-row gap-10">
        <div className="flex-1" style={{ minWidth: 0 }}>
          <label className="settings-label" htmlFor="support-auto-report">Foutrapporten automatisch versturen</label>
          <p className="settings-desc" id="support-auto-report-help">Bij een mislukte opname, transcriptie of notule en bij een crash. Zelf melden werkt altijd.</p>
        </div>
        <label className="toggle-switch">
          <input id="support-auto-report" type="checkbox" role="switch" aria-label="Foutrapporten automatisch versturen"
            aria-describedby="support-auto-report-help" aria-checked={auto_report} checked={auto_report}
            onChange={event => setAutoReport(event.target.checked)} />
          <span className="toggle-slider" />
        </label>
        </div>
      </div>
      <div className="settings-row" style={{ display: "block" }}>
        <button type="button" className="studio-link" style={{ minHeight: 44 }} onClick={() => {
          setPrivacyError(false);
          void open(PRIVACY_URL).catch(() => setPrivacyError(true));
        }}>Privacyverklaring</button>
        {privacyError && <p role="status" style={{ color: "var(--status-error)" }}>De privacyverklaring kon niet worden geopend. Probeer het opnieuw.</p>}
      </div>
      <div className="settings-row" style={{ display: "block" }}>
        <h3 className="settings-label">Contact voor meldingen</h3>
        {!isCompleteIdentity(draftName, draftEmail) && <p role="alert">Vul een naam (maximaal 200 tekens) en geldig e-mailadres (maximaal 320 tekens) in.</p>}
        <div className="form-field">
          <label className="form-label-sm" htmlFor="support-contact-name">Naam</label>
          <input id="support-contact-name" className="input" autoComplete="name" value={draftName}
            onChange={event => setDraftName(event.target.value)} onBlur={saveContact} />
        </div>
        <div className="form-field">
          <label className="form-label-sm" htmlFor="support-contact-email">E-mailadres</label>
          <input id="support-contact-email" className="input" type="email" inputMode="email" autoComplete="email" value={draftEmail}
            onChange={event => setDraftEmail(event.target.value)} onBlur={saveContact} />
        </div>
      </div>
      <div className="settings-row"><FeedbackWidget /></div>
    </div>
  </div>;
}
