import { useEffect, useState } from "react";
import { usePersonalCorrectionsStore } from "../../stores/personalCorrectionsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import type { PersonalCorrection } from "../../services/personalCorrections";

export function CorrectionFields({ entry, onChange }: { entry: PersonalCorrection; onChange: (entry: PersonalCorrection) => void }) {
  const profiles = useProfilesStore(s => s.profiles);
  return <>
    <label>Correcte term<input className="input" value={entry.canonical} onChange={e => onChange({...entry, canonical:e.target.value})} /></label>
    <label>Verkeerde spellingen (komma-gescheiden)<input className="input" value={entry.variants.join(",")} onChange={e => onChange({...entry, variants:e.target.value.split(",")})} /></label>
    <label>Toepassen op<select className="input" value={entry.scope ?? ""} onChange={e => onChange({...entry, scope:e.target.value || null})}>
      <option value="">Alle opnames</option>{profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
    </select></label>
    {entry.scope === null && <p className="text-secondary">Iedere passende vermelding wordt vervangen. Kies een opnameprofiel als de variant ook een andere betekenis heeft.</p>}
  </>;
}
export const newCorrection = (scope: string | null = null): PersonalCorrection => ({ id:crypto.randomUUID(), canonical:"", variants:[""], scope, enabled:true });
export function PersonalCorrections() {
  const store = usePersonalCorrectionsStore();
  const [draft,setDraft] = useState<PersonalCorrection | null>(null);
  const [error,setError] = useState("");
  const [busy,setBusy] = useState(false);
  useEffect(() => { void store.hydrate().catch(e => setError(String(e))); }, []);
  async function perform(operation: () => Promise<void>, close = false) {
    setBusy(true);setError("");
    try { await operation(); if(close)setDraft(null); } catch(e) { setError(e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  }
  return <section className="settings-group personal-corrections"><h3>Woorden en namen</h3>
    <p>Corrigeer een naam één keer en onthoud de juiste spelling voor volgende notulen. Deze lijst blijft op dit apparaat.</p>
    {store.entries.map(entry => <div className="correction-row" key={entry.id}>
      <label><input type="checkbox" checked={entry.enabled} disabled={busy} onChange={e => void perform(() => store.save({...entry, enabled:e.target.checked}))} /> {entry.canonical}</label>
      <span>{entry.variants.join(", ")} · {entry.scope ? useProfilesStore.getState().getProfile(entry.scope)?.name ?? entry.scope : "Alle opnames"}</span>
      <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => setDraft(entry)}>Bewerken</button>
      <button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => void perform(() => store.remove(entry.id))}>Verwijderen</button>
    </div>)}
    {!draft && <button className="btn btn-secondary btn-sm" onClick={() => setDraft(newCorrection())}>Woord toevoegen</button>}
    {draft && <div className="correction-fields"><CorrectionFields entry={draft} onChange={setDraft} />
      <div className="correction-actions"><button className="btn btn-secondary btn-sm" disabled={busy} onClick={() => setDraft(null)}>Annuleren</button><button className="btn btn-accent btn-sm" disabled={busy} onClick={() => void perform(() => store.save({...draft, canonical:draft.canonical.trim(), variants:draft.variants.map(v=>v.trim())}),true)}>Opslaan</button></div>
    </div>}
    {error && <p role="alert">{error}</p>}
  </section>;
}
