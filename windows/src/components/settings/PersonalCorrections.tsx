import { useEffect, useState } from "react";
import { usePersonalCorrectionsStore } from "../../stores/personalCorrectionsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import type { PersonalCorrection } from "../../services/personalCorrections";
import { DesktopDialog } from "../ui/DesktopDialog";
import { HistoryList } from "./HistoryList";
import type { HistoryEntry } from "../../services/contextHistory";

const NOTE_LIMIT = 200;
const errorText = (e: unknown) => e instanceof Error ? e.message : String(e);

export function CorrectionFields({ entry, onChange }: { entry: PersonalCorrection; onChange: (entry: PersonalCorrection) => void }) {
  const profiles = useProfilesStore(s => s.profiles);
  // Blocks input beyond the limit and the characters the glossary does not allow.
  const setNote = (value: string) => {
    const note = value.replace(/[\r\n<>]/g, "").slice(0, NOTE_LIMIT);
    const { note: _old, ...rest } = entry;
    onChange(note ? { ...rest, note } : rest);
  };
  return <>
    <label>Correcte term<input className="input" value={entry.canonical} placeholder="Bijvoorbeeld Yinga" onChange={e => onChange({...entry, canonical:e.target.value})} /></label>
    <label>Verkeerde spellingen (komma-gescheiden)<input className="input" value={entry.variants.join(",")} placeholder="Bijvoorbeeld Jengo, Django" onChange={e => onChange({...entry, variants:e.target.value.split(",")})} /></label>
    <label>Toelichting (optioneel)<input className="input" value={entry.note ?? ""} placeholder="Bijvoorbeeld Klant uit Utrecht" onChange={e => setNote(e.target.value)} />
      <small className="text-secondary">Nog {NOTE_LIMIT - (entry.note?.length ?? 0)} tekens</small></label>
    <label>Toepassen op<select className="input" value={entry.scope ?? ""} onChange={e => onChange({...entry, scope:e.target.value || null})}>
      <option value="">Alle opnames</option>{profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
    </select></label>
    {entry.scope === null && <p className="text-secondary">Iedere passende vermelding wordt vervangen. Kies een opnameprofiel als de variant ook een andere betekenis heeft.</p>}
  </>;
}
export const newCorrection = (scope: string | null = null): PersonalCorrection => ({ id:crypto.randomUUID(), canonical:"", variants:[""], scope, enabled:true });

/** Glossary page: table with search and counter; a row opens the edit panel with history. */
export function PersonalCorrections() {
  const store = usePersonalCorrectionsStore();
  const profiles = useProfilesStore(s => s.profiles);
  const [editing,setEditing] = useState<{ entry: PersonalCorrection; isNew: boolean } | null>(null);
  const [query,setQuery] = useState("");
  const [error,setError] = useState("");
  useEffect(() => { void store.hydrate().catch(e => setError(errorText(e))); }, []);
  const q = query.trim().toLowerCase();
  const shown = [...store.entries]
    .sort((a, b) => a.canonical.localeCompare(b.canonical, "nl", { sensitivity: "base" }))
    .filter(e => !q || [e.canonical, e.note ?? "", ...e.variants].some(text => text.toLowerCase().includes(q)));
  const variantsText = (e: PersonalCorrection) => e.variants.map(v => v.trim()).filter(Boolean).join(", ");
  const scopeName = (e: PersonalCorrection) => e.scope ? profiles.find(p => p.id === e.scope)?.name ?? e.scope : "Alle profielen";
  async function toggle(entry: PersonalCorrection, enabled: boolean) {
    setError("");
    try { await store.save({...entry, enabled}); } catch (e) { setError(errorText(e)); }
  }
  return <section className="settings-group personal-corrections"><h3>Woorden en namen</h3>
    <p>Corrigeer een naam één keer en onthoud de juiste spelling voor volgende notulen. Deze lijst blijft op dit apparaat.</p>
    <div className="glossary-toolbar">
      <span className="text-secondary">{store.entries.length === 1 ? "1 term" : `${store.entries.length} termen`}</span>
      {store.entries.length > 0 && <input className="input" type="search" aria-label="Zoeken in woordenlijst" placeholder="Zoeken" value={query} onChange={e => setQuery(e.target.value)} />}
      <button className="btn btn-secondary btn-sm" onClick={() => setEditing({ entry: {...newCorrection(), variants: []}, isNew: true })}>Term toevoegen</button>
    </div>
    {store.entries.length === 0
      ? <p className="text-secondary">Nog geen termen. Voeg een term toe of corrigeer een woord in een notule.</p>
      : <div className="log-table-wrapper glossary-table"><table className="log-table">
        <thead><tr><th>Term</th><th>Herkend als</th><th>Toelichting</th><th>Profiel</th><th>Aan</th></tr></thead>
        <tbody>{shown.map(entry => <tr key={entry.id} onClick={() => setEditing({ entry, isNew: false })}>
          <td><button className="glossary-term" onClick={e => { e.stopPropagation(); setEditing({ entry, isNew: false }); }}>{entry.canonical}</button></td>
          <td>{variantsText(entry)}</td>
          <td>{entry.note ?? ""}</td>
          <td>{scopeName(entry)}</td>
          <td onClick={e => e.stopPropagation()}><input type="checkbox" aria-label={`${entry.canonical} aan`} checked={entry.enabled} onChange={e => void toggle(entry, e.target.checked)} /></td>
        </tr>)}</tbody>
      </table></div>}
    {error && <p role="alert">{error}</p>}
    {editing && <CorrectionEditor initial={editing.entry} isNew={editing.isNew} onClose={() => setEditing(null)} />}
  </section>;
}

/** Edit panel for one glossary entry: fields, delete and version history. */
function CorrectionEditor({ initial, isNew, onClose }: { initial: PersonalCorrection; isNew: boolean; onClose: () => void }) {
  const store = usePersonalCorrectionsStore();
  const [entry,setEntry] = useState(initial);
  const [error,setError] = useState("");
  const [busy,setBusy] = useState(false);
  async function perform(operation: () => Promise<void>) {
    setBusy(true); setError("");
    try { await operation(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }
  const save = () => perform(async () => {
    const note = entry.note?.trim();
    const { note: _old, ...rest } = entry;
    await store.save({ ...rest, canonical: entry.canonical.trim(), variants: entry.variants.map(v => v.trim()).filter(Boolean), ...(note ? { note } : {}) });
    onClose();
  });
  const restore = (version: HistoryEntry) => perform(async () => {
    await store.restore(version);
    const fresh = usePersonalCorrectionsStore.getState().entries.find(e => e.id === entry.id);
    if (fresh) setEntry(fresh); else onClose();
  });
  return <DesktopDialog label={isNew ? "Term toevoegen" : "Term bewerken"} onClose={() => { if (!busy) onClose(); }}>
    <div className="card-static correction-dialog"><h3>{isNew ? "Term toevoegen" : "Term bewerken"}</h3><div className="correction-fields">
      <CorrectionFields entry={entry} onChange={setEntry} />
      <label><span><input type="checkbox" checked={entry.enabled} onChange={e => setEntry({...entry, enabled: e.target.checked})} /> Aan</span></label>
      {!isNew && <><h4>Geschiedenis</h4><HistoryList kind="term" itemId={entry.id} onRestore={restore} disabled={busy} /></>}
      {error && <p role="alert">{error}</p>}
      <div className="correction-actions">
        {!isNew && <button className="btn btn-secondary btn-sm correction-delete" disabled={busy} onClick={() => void perform(async () => { await store.remove(entry.id); onClose(); })}>Verwijderen</button>}
        <button className="btn btn-secondary btn-sm" disabled={busy} onClick={onClose}>Annuleren</button>
        <button className="btn btn-accent btn-sm" disabled={busy} onClick={() => void save()}>Opslaan</button>
      </div>
    </div></div>
  </DesktopDialog>;
}
