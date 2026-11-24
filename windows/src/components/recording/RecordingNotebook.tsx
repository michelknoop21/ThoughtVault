import { useState } from "react";
import { parseNotebook, serializeNotebook, type NotebookDocument } from "../../services/quickNotes";

export function RecordingNotebook({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  const [tab, setTab] = useState<"notes" | "actions">("actions");
  const [expanded, setExpanded] = useState(true);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState("");
  const document = parseNotebook(value);
  const edit = (change: (next: NotebookDocument) => void) => {
    const next = parseNotebook(value);
    change(next);
    try { onChange(serializeNotebook(next)); setError(""); }
    catch { setError("Opslaan mislukt. Je tekst staat nog in het kladblok; probeer opnieuw."); }
  };
  const add = () => {
    if (!draft.trim()) return;
    edit(next => next.items.push({ text: draft.trim(), done: false }));
    setDraft("");
  };
  return <section className="recording-notebook" aria-label="Kladblok">
    <header><h2>Kladblok</h2><button type="button" aria-label={expanded ? "Kladblok inklappen" : "Kladblok uitklappen"} aria-expanded={expanded} onClick={() => setExpanded(!expanded)}>{expanded ? "⌃" : "⌄"}</button></header>
    {expanded && <>
      <div role="tablist" aria-label="Kladblokonderdelen" className="notebook-tabs">
        <button type="button" role="tab" id="notebook-notes-tab" aria-controls="notebook-notes" aria-selected={tab === "notes"} onClick={() => setTab("notes")}>Notities</button>
        <button type="button" role="tab" id="notebook-actions-tab" aria-controls="notebook-actions" aria-selected={tab === "actions"} onClick={() => setTab("actions")}>Actiepunten <span>{document.items.filter(item => !item.done).length} open</span></button>
      </div>
      {tab === "notes" ? <div role="tabpanel" id="notebook-notes" aria-labelledby="notebook-notes-tab" className="notebook-body">
        <textarea aria-label="Eigen notities" placeholder="Schrijf hier je notities…" value={document.notes} onChange={e => edit(next => { next.notes = e.target.value; })} />
      </div> : <div role="tabpanel" id="notebook-actions" aria-labelledby="notebook-actions-tab" className="notebook-body">
        {document.items.map((item, index) => <div className={`notebook-action ${item.done ? "done" : ""}`} key={index}>
          <input type="checkbox" aria-label={`Actiepunt ${index + 1} afronden`} checked={item.done} onChange={e => edit(next => { next.items[index].done = e.target.checked; })} />
          <textarea rows={2} aria-label={`Actiepunt ${index + 1}`} value={item.text} onChange={e => edit(next => { next.items[index].text = e.target.value; })} />
          <button type="button" aria-label={`Actiepunt ${index + 1} verwijderen`} onClick={() => edit(next => { next.items.splice(index, 1); })}>×</button>
        </div>)}
        <form className="notebook-add" onSubmit={e => { e.preventDefault(); add(); }}>
          <input aria-label="Nieuw actiepunt" placeholder="Nieuw actiepunt…" value={draft} onChange={e => setDraft(e.target.value)} />
          <button type="submit" className="btn btn-sm" disabled={!draft.trim()}>Toevoegen</button>
        </form>
      </div>}
      <footer><span>Blijft bij deze opname bewaard</span><span>{document.items.filter(item => item.done).length} van {document.items.length} afgerond</span></footer>
    </>}
    {error && <p role="alert">{error}</p>}
  </section>;
}
