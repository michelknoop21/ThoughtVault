import { useState } from "react";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import type { LibraryEntry } from "../../services/libraryOrganization";
import { cancelLabeling, labelAutomatically, useLabelingProgress } from "../../services/automaticLabels";
import { DesktopDialog } from "../ui/DesktopDialog";
import { useConfirmation } from "../ui/useConfirmation";

export function LibraryNavigation({ selection, onSelect, selectedIDs }: {
  selection: string; onSelect: (id: string) => void; selectedIDs: string[];
}) {
  const store = useLocalTranscriptsStore();
  const progress = useLabelingProgress();
  const [editor, setEditor] = useState<LibraryEntry | null>(null);
  const [labelsOpen, setLabelsOpen] = useState(false);
  const [error, setError] = useState<string>();
  const { confirm, confirmation } = useConfirmation();
  const folders = store.library.filter(e => e.kind === "folder");
  const labels = store.library.filter(e => e.kind === "label");
  const smart = store.library.filter(e => e.kind === "smart");
  const current = store.library.find(e => e.id === selection);
  const failed = store.items.filter(t => t.auto_label_error);
  async function perform(action: () => Promise<void>) {
    try { setError(undefined); await action(); } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  }
  function create(kind: LibraryEntry["kind"]) {
    setEditor({ id: crypto.randomUUID(), name: "", kind, labelIDs: [], description: "", automatic: false });
  }
  async function adoptLabels() {
    for (const name of new Set(store.items.flatMap(t => t.tags))) {
      if (!useLocalTranscriptsStore.getState().library.some(e => e.kind === "label" && e.name === name)) {
        await store.saveEntry({ id: crypto.randomUUID(), name, kind: "label", description: "", automatic: false, labelIDs: [] });
      }
    }
  }
  return <nav aria-label="Mappen en labels" className="library-navigation">
    {confirmation}
    <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
      <button className="btn btn-sm" aria-pressed={selection === "all"} onClick={() => onSelect("all")}>Alle notulen</button>
      <button className="btn btn-sm" aria-pressed={selection === "unfiled"} onClick={() => onSelect("unfiled")}>Zonder map</button>
      <button className="btn btn-sm" onClick={() => create("folder")}>Nieuwe map…</button>
      <button className="btn btn-sm" onClick={() => void perform(async () => { await adoptLabels(); create("smart"); })}>Nieuwe slimme map…</button>
      <button className="btn btn-sm" onClick={() => void perform(async () => { await adoptLabels(); setLabelsOpen(true); })}>Labels beheren…</button>
    </div>
    {([['Mappen', folders], ['Slimme mappen', smart]] as const).map(([title, entries]) => <div key={title}>
      <span className="text-caption text-secondary">{title}</span>
      <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>{entries.map(e => <button key={e.id} className="btn btn-sm"
        aria-pressed={selection === e.id} onClick={() => onSelect(e.id)}
        onDragOver={event => { if (e.kind === "folder" && event.dataTransfer.types.includes("application/x-thoughtvault-notes")) event.preventDefault(); }}
        onDrop={event => {
          event.preventDefault();
          if (e.kind !== "folder") return;
          void perform(async () => {
            const ids: unknown = JSON.parse(event.dataTransfer.getData("application/x-thoughtvault-notes"));
            if (!Array.isArray(ids) || !ids.every(id => typeof id === "string")) throw new Error("Ongeldige selectie.");
            await store.move(ids, e.id);
          });
        }}>{e.name}</button>)}</div>
    </div>)}
    {current && <div className="flex-row gap-8">
      <button className="btn btn-sm" onClick={() => setEditor(current)}>Map wijzigen…</button>
      <button className="btn btn-sm" onClick={() => void perform(async () => {
        if (await confirm("De notulen blijven bewaard en staan daarna onder Zonder map.", "Map verwijderen", "Verwijderen")) {
          await store.removeEntry(current.id); onSelect("unfiled");
        }
      })}>Map verwijderen</button>
    </div>}
    {selectedIDs.length > 0 && <div className="flex-row gap-8" style={{ flexWrap: "wrap" }}>
      <select className="select" aria-label="Verplaats naar" value="" onChange={e => {
        const value = e.target.value;
        if (value) void perform(() => store.move(selectedIDs, value === "unfiled" ? undefined : value));
      }}>
        <option value="">Verplaats naar…</option><option value="unfiled">Zonder map</option>
        {folders.map(e => <option key={e.id} value={e.id}>{e.name}</option>)}
      </select>
      <button className="btn btn-sm" disabled={progress.busy || !labels.some(e => e.automatic)} onClick={() => void perform(async () => {
        if (await confirm(`${selectedIDs.length} notulen worden verwerkt met de ingestelde AI-provider. Titel en notuletekst worden gebruikt; handmatige labels blijven bewaard.`, "Bestaande notulen labelen", "Labelen")) await labelAutomatically(selectedIDs);
      })}>Bestaande notulen labelen… ({selectedIDs.length})</button>
    </div>}
    {progress.busy && <div role="status" className="flex-row gap-8">
      <progress max={Math.max(1, progress.total)} value={progress.completed} aria-label="Labelvoortgang" />
      {progress.completed} / {progress.total}
      <button className="btn btn-sm" disabled={progress.cancelled} onClick={cancelLabeling}>Annuleren</button>
    </div>}
    {progress.busy && progress.cancelled && <p role="status">De huidige AI-aanvraag wordt afgerond. Het resultaat wordt niet opgeslagen.</p>}
    {failed.length > 0 && <button className="btn btn-sm" disabled={progress.busy} onClick={() => void labelAutomatically(failed.map(t => t.id))}>Automatisch labelen opnieuw proberen ({failed.length})</button>}
    {(error || progress.error) && <p role="alert">{error || progress.error}</p>}
    {labelsOpen && <DesktopDialog label="Labels beheren" className="td-overlay" onClose={() => setLabelsOpen(false)}>
      <div className="td-tags-dialog"><h3>Labels beheren</h3>
        {labels.map(e => <p key={e.id}><button className="btn" onClick={() => { setLabelsOpen(false); setEditor(e); }}>{e.name}</button></p>)}
        <button className="btn" onClick={() => { setLabelsOpen(false); create("label"); }}>Nieuw label…</button>
        <button className="btn" onClick={() => setLabelsOpen(false)}>Sluiten</button>
      </div>
    </DesktopDialog>}
    {editor && <DesktopDialog label={editor.kind === "label" ? "Labelinstellingen" : "Map bewerken"} className="td-overlay" onClose={() => setEditor(null)}>
      <form className="td-tags-dialog" onSubmit={e => { e.preventDefault(); void perform(async () => { await store.saveEntry(editor); setEditor(null); }); }}>
        <h3>{editor.kind === "label" ? "Labelinstellingen" : "Map bewerken"}</h3>
        <label>Naam<input className="input" required value={editor.name} disabled={editor.kind === "label" && labels.some(e => e.id === editor.id)} onChange={e => setEditor({ ...editor, name: e.target.value })} /></label>
        {editor.kind === "label" && <>
          <label>Omschrijving<textarea className="input" value={editor.description} onChange={e => setEditor({ ...editor, description: e.target.value })} /></label>
          <label><input type="checkbox" checked={editor.automatic} onChange={e => setEditor({ ...editor, automatic: e.target.checked })} /> Automatisch toekennen</label>
          <p className="text-caption">De ingestelde AI-provider gebruikt de omschrijving. Labels blijven handmatig corrigeerbaar.</p>
        </>}
        {editor.kind === "smart" && <fieldset><legend>Minstens één passend label</legend>{labels.map(label => <label key={label.id} style={{ display: "block" }}>
          <input type="checkbox" checked={editor.labelIDs.includes(label.id)} onChange={e => setEditor({ ...editor, labelIDs: e.target.checked ? [...editor.labelIDs, label.id] : editor.labelIDs.filter(id => id !== label.id) })} /> {label.name}
        </label>)}</fieldset>}
        {error && <p role="alert">{error}</p>}
        <div className="flex-row gap-8"><button type="button" className="btn" onClick={() => setEditor(null)}>Annuleren</button><button className="btn btn-accent" disabled={!editor.name.trim() || (editor.kind === "smart" && !editor.labelIDs.length)}>Opslaan</button></div>
      </form>
    </DesktopDialog>}
  </nav>;
}
