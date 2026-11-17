import { useEffect, useState } from "react";
import { usePersonalCorrectionsStore } from "../../stores/personalCorrectionsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import { heardAs, learnedKey, type PersonalCorrection } from "../../services/personalCorrections";
import { DesktopDialog } from "../ui/DesktopDialog";
import { Dismiss24Regular, Edit24Regular } from "../ui/StudioIcons";
import { HistoryList } from "./HistoryList";
import { CardHead, SettingsField } from "./SettingsFields";
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
  const withoutLearned = (spelling: string): PersonalCorrection => {
    const { learned, ...rest } = entry;
    const left = (learned ?? []).filter(l => l !== spelling);
    return left.length ? { ...rest, learned: left } : rest;
  };
  return <>
    <SettingsField label="Juiste schrijfwijze">
      <input className="input" aria-label="Juiste schrijfwijze" value={entry.canonical} placeholder="Bijvoorbeeld Yinga" onChange={e => onChange({...entry, canonical:e.target.value})} />
    </SettingsField>
    <SettingsField label="Fout gehoorde spellingen (optioneel)">
      <input className="input" aria-label="Fout gehoorde spellingen" value={entry.variants.join(", ")} placeholder="Bijvoorbeeld Jengo, Django" onChange={e => onChange({...entry, variants:e.target.value.split(",")})} />
      <p className="settings-desc">Meestal niet nodig. ThoughtVault vindt vergelijkbare woorden zelf. Vul alleen in wat altijd vervangen moet worden.</p>
    </SettingsField>
    {!!entry.learned?.length && <SettingsField label="Automatisch geleerd">
      <ul className="learned-list">{entry.learned.map(spelling => <li key={spelling}>
        <span className="tag-chip-pill">{spelling}</span>
        <button className="btn btn-ghost btn-sm" onClick={() => { const next = withoutLearned(spelling); onChange({ ...next, variants: [...next.variants.filter(v => v.trim()), spelling] }); }}>Vast maken</button>
        <button className="btn btn-ghost btn-sm learned-remove" onClick={() => onChange(withoutLearned(spelling))}>Verwijderen</button>
      </li>)}</ul>
      <p className="settings-desc">Gevonden op basis van de context. Vast maken vervangt de spelling voortaan altijd.</p>
    </SettingsField>}
    <SettingsField label="Toelichting (optioneel)">
      <input className="input" aria-label="Toelichting" value={entry.note ?? ""} placeholder="Bijvoorbeeld Klant uit Utrecht" onChange={e => setNote(e.target.value)} />
      <p className="settings-desc">Nog {NOTE_LIMIT - (entry.note?.length ?? 0)} tekens</p>
    </SettingsField>
    <SettingsField label="Toepassen op">
      <select className="input" aria-label="Toepassen op" value={entry.scope ?? ""} onChange={e => onChange({...entry, scope:e.target.value || null})}>
        <option value="">Alle opnames</option>{profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
      </select>
      {entry.scope === null && <p className="settings-desc">Iedere passende vermelding wordt vervangen. Kies een opnameprofiel als de spelling ook een andere betekenis heeft.</p>}
    </SettingsField>
  </>;
}
export const newCorrection = (scope: string | null = null): PersonalCorrection => ({ id:crypto.randomUUID(), canonical:"", variants:[""], scope, enabled:true });

/** Glossary page: rows with search and counter; a row opens the edit panel with history. */
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
    .filter(e => !q || [e.canonical, e.note ?? "", ...heardAs(e)].some(text => text.toLowerCase().includes(q)));
  const scopeName = (e: PersonalCorrection) => e.scope ? profiles.find(p => p.id === e.scope)?.name ?? e.scope : "Alle profielen";
  async function toggle(entry: PersonalCorrection, enabled: boolean) {
    setError("");
    try { await store.save({...entry, enabled}); } catch (e) { setError(errorText(e)); }
  }
  return <section className="settings-group personal-corrections">
    <CardHead icon={<Edit24Regular />} title="Woorden en namen" subtitle="Juiste spelling voor je notulen" />
    <div className="personal-corrections-body">
      <p className="settings-desc">Voer de juiste schrijfwijze in. ThoughtVault zoekt in elke opname zelf naar woorden die erop lijken. Deze lijst blijft op dit apparaat.</p>
      <div className="glossary-toolbar">
        <span className="text-secondary">{store.entries.length === 1 ? "1 term" : `${store.entries.length} termen`}</span>
        {store.entries.length > 0 && <input className="input" type="search" aria-label="Zoeken in woordenlijst" placeholder="Zoeken" value={query} onChange={e => setQuery(e.target.value)} />}
        <button className="btn btn-secondary btn-sm" onClick={() => setEditing({ entry: {...newCorrection(), variants: []}, isNew: true })}>Term toevoegen</button>
      </div>
      {store.entries.length === 0
        ? <p className="text-secondary">Nog geen termen. Voeg een term toe of corrigeer een woord in een notule.</p>
        : <ul className="glossary-rows">{shown.map(entry => <li key={entry.id} className={entry.enabled ? "" : "is-off"}>
          <div className="glossary-row-main">
            <div className="glossary-row-title">
              <button className="glossary-term" onClick={() => setEditing({ entry, isNew: false })}>{entry.canonical}</button>
              <span className="tag-chip glossary-scope">{scopeName(entry)}</span>
            </div>
            {(entry.variants.some(v => v.trim()) || !!entry.learned?.length) && <div className="glossary-chips">
              {entry.variants.filter(v => v.trim()).map(v => <span key={v} className="tag-chip">{v}</span>)}
              {entry.learned?.map(v => <span key={v} className="tag-chip learned" title="Automatisch geleerd">{v}</span>)}
            </div>}
            {entry.note && <p className="settings-desc">{entry.note}</p>}
          </div>
          <input type="checkbox" aria-label={`${entry.canonical} aan`} checked={entry.enabled} onChange={e => void toggle(entry, e.target.checked)} />
        </li>)}</ul>}
      {error && <p className="settings-desc" role="alert">{error}</p>}
    </div>
    {editing && <CorrectionEditor initial={editing.entry} isNew={editing.isNew} onClose={() => setEditing(null)} />}
  </section>;
}

/** Edit panel for one glossary entry: fields, delete and version history. */
function CorrectionEditor({ initial, isNew, onClose }: { initial: PersonalCorrection; isNew: boolean; onClose: () => void }) {
  const store = usePersonalCorrectionsStore();
  const [entry,setEntry] = useState(initial);
  const [error,setError] = useState("");
  const [busy,setBusy] = useState(false);
  const title = isNew ? "Term toevoegen" : "Term bewerken";
  async function perform(operation: () => Promise<void>) {
    setBusy(true); setError("");
    try { await operation(); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  }
  const save = () => perform(async () => {
    const note = entry.note?.trim();
    const { note: _old, ...rest } = entry;
    const variants = entry.variants.map(v => v.trim()).filter(Boolean);
    const stored = store.entries.find(e => e.id === entry.id)?.learned ?? [];
    await store.save({ ...rest, canonical: entry.canonical.trim(), variants, ...(note ? { note } : {}) });
    // A learned spelling removed by hand must not be learned again.
    const kept = new Set([...(entry.learned ?? []), ...variants]);
    for (const spelling of stored.filter(s => !kept.has(s))) await store.addDismissed(learnedKey(entry.canonical, spelling));
    onClose();
  });
  const restore = (version: HistoryEntry) => perform(async () => {
    await store.restore(version);
    const fresh = usePersonalCorrectionsStore.getState().entries.find(e => e.id === entry.id);
    if (fresh) setEntry(fresh); else onClose();
  });
  return <DesktopDialog label={title} onClose={() => { if (!busy) onClose(); }}>
    <div className="correction-dialog" role="dialog" aria-modal="true" aria-label={title}>
      <header className="correction-dialog-head">
        <h2>{title}</h2>
        <button className="btn btn-ghost btn-sm" aria-label="Sluiten" title="Sluiten" disabled={busy} onClick={onClose}><Dismiss24Regular style={{ fontSize: 16 }} /></button>
      </header>
      <div className="correction-fields">
        <CorrectionFields entry={entry} onChange={setEntry} />
        <SettingsField label="Status">
          <label className="settings-desc"><input type="checkbox" checked={entry.enabled} onChange={e => setEntry({...entry, enabled: e.target.checked})} /> Gebruiken in notulen</label>
        </SettingsField>
        {!isNew && <SettingsField label="Geschiedenis"><HistoryList kind="term" itemId={entry.id} onRestore={restore} disabled={busy} /></SettingsField>}
      </div>
      <footer className="correction-footer">
        {error && <p className="settings-desc" role="alert">{error}</p>}
        <div className="correction-actions">
          {!isNew && <button className="btn btn-secondary btn-sm correction-delete" disabled={busy} onClick={() => void perform(async () => { await store.remove(entry.id); onClose(); })}>Verwijderen</button>}
          <button className="btn btn-secondary btn-sm" disabled={busy} onClick={onClose}>Annuleer</button>
          <button className="btn btn-primary btn-sm" disabled={busy || !entry.canonical.trim()} onClick={() => void save()}>{isNew ? "Term toevoegen" : "Wijzigingen opslaan"}</button>
        </div>
      </footer>
    </div>
  </DesktopDialog>;
}
