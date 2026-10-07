import { useState, useEffect } from "react";
import type { ReactNode } from "react";
import { loadCredential, storeCredential, deleteCredential } from "../../services/tauriCommands";

export function SettingsField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="form-field">
      <label className="form-label-sm">{label}</label>
      {children}
    </div>
  );
}


export function CredentialField({ credentialKey, label, children }: { credentialKey: string; label: string; children?: ReactNode }) {
  const [draft, setDraft] = useState("");
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    loadCredential(credentialKey).then((key) => { if (active) setSaved(Boolean(key)); })
      .catch(() => { if (active) setError("Sleutelopslag niet beschikbaar"); });
    return () => { active = false; };
  }, [credentialKey]);

  async function save() {
    try {
      await storeCredential(credentialKey, draft.trim());
      setDraft("");
      setSaved(true);
      setError("");
    } catch {
      setError("Opslaan in Windows Credential Manager mislukt");
    }
  }

  async function remove() {
    try {
      await deleteCredential(credentialKey);
      setDraft("");
      setSaved(false);
      setError("");
    } catch {
      setError("Verwijderen uit Windows Credential Manager mislukt");
    }
  }

  return <SettingsField label={label}>
    <input className="input" type="password" value={draft} onChange={(e) => setDraft(e.target.value)}
      placeholder={saved ? "Sleutel opgeslagen · vul in om te vervangen" : "API-sleutel invoeren"} />
    <div className="action-row">
      <button className="btn btn-secondary btn-sm" disabled={!draft.trim()} onClick={save}>Opslaan</button>
      {saved && <button className="btn btn-secondary btn-sm" onClick={remove}>Verwijderen</button>}
      {children}
    </div>
    {error && <p className="settings-desc" role="alert">{error}</p>}
  </SettingsField>;
}

export function CardHead({ icon, title, subtitle }: { icon: ReactNode; title: string; subtitle: string }) {
  return <header className="card-head"><span className="card-icon">{icon}</span><div><h3>{title}</h3><p>{subtitle}</p></div></header>;
}
