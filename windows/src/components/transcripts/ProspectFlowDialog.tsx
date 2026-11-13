import { useEffect, useState } from "react";
import { DesktopDialog } from "../ui/DesktopDialog";
import { htmlToPlainText } from "../../utils/htmlToMarkdown";
import { createOffer, loadOfferRef, match, openOffer, searchCustomers, type OfferResult } from "../../services/prospectFlow";
import type { Transcript } from "../../types";

interface Option { id: number; label: string }
const NEW = "new";

export function ProspectFlowDialog({ transcript, onClose }: { transcript: Transcript; onClose: () => void }) {
  const taskId = transcript.task_id || transcript.id;
  const [options, setOptions] = useState<Option[]>([]);
  const [selected, setSelected] = useState<number | typeof NEW | null>(null);
  const [query, setQuery] = useState("");
  const [newName, setNewName] = useState("");
  const [matching, setMatching] = useState(true);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState<OfferResult | null>(null);

  function addOptions(found: Option[]) {
    setOptions((prev) => [...prev, ...found.filter((o) => !prev.some((p) => p.id === o.id))]);
  }

  useEffect(() => {
    let active = true;
    const ref = loadOfferRef(taskId);
    const pending = ref?.pendingRequestId ? ref.pendingCustomer : undefined;
    let pendingSelection: number | typeof NEW | null = null;
    if (pending?.startsWith("new:") && pending.slice(4).trim()) {
      pendingSelection = NEW;
      setNewName(ref?.pendingNewCustomerName?.toLowerCase() === pending.slice(4) ? ref.pendingNewCustomerName : pending.slice(4));
    } else if (pending && /^id:[1-9]\d*$/.test(pending) && Number.isSafeInteger(Number(pending.slice(3)))) {
      pendingSelection = Number(pending.slice(3));
    }
    setSelected(pendingSelection);
    // Participant organisations are not stored with a transcript, so only the notule text is matched.
    match(htmlToPlainText(transcript.notule_html ?? ""))
      .then((found) => {
        if (!active) return;
        const choices = found.map((k) => ({ id: k.id, label: k.plaats ? `${k.naam} (${k.plaats})` : k.naam }));
        if (typeof pendingSelection === "number" && !choices.some(k => k.id === pendingSelection)) {
          choices.unshift({ id: pendingSelection, label: `Eerder gekozen klant (${pendingSelection})` });
        }
        addOptions(choices);
        if (pendingSelection === null && found[0]) setSelected(found[0].id);
      })
      .catch((e) => { if (active) setError(e instanceof Error ? e.message : "Klanten zoeken mislukt"); })
      .finally(() => { if (active) setMatching(false); });
    return () => { active = false; };
  }, [taskId, transcript.notule_html]);

  async function search() {
    if (!query.trim()) return;
    setError("");
    try {
      const found = await searchCustomers(query.trim());
      addOptions(found.map((c) => ({ id: c.id, label: c.city ? `${c.name} (${c.city})` : c.name })));
      if (!found.length) setError("Geen klanten gevonden.");
    } catch (e) { setError(e instanceof Error ? e.message : "Zoeken mislukt"); }
  }

  const ready = selected === NEW ? newName.trim() !== "" : selected !== null;

  async function create() {
    if (!ready) return;
    setCreating(true);
    setError("");
    try {
      setResult(await createOffer({
        taskId, title: transcript.title, recordedAt: transcript.created_at,
        notuleHtml: transcript.notule_html ?? "", transcript: transcript.raw_transcription ?? "",
        ...(selected === NEW ? { newCustomerName: newName.trim() } : { customerId: selected as number }),
      }));
    } catch (e) { setError(e instanceof Error ? e.message : "Offerte maken mislukt"); }
    finally { setCreating(false); }
  }

  return <DesktopDialog label="Offerte in Prospect Flow" onClose={creating ? () => {} : onClose}>
    <div className="card-static correction-dialog" style={{ padding: 20, display: "flex", flexDirection: "column", gap: 12 }}>
      <h3>Offerte in Prospect Flow</h3>
      {result ? <>
        <p><strong>Offerte {result.number}</strong>{result.bestaand ? " (al eerder gemaakt)" : ""} voor {result.klant.naam}{result.klant.nieuw ? " (nieuwe klant)" : ""}.</p>
        <p>{result.regels} regels, waarvan {result.te_controleren} te controleren.</p>
        {result.terugval_gebruikt && <p className="settings-desc">Het terugvalmodel is gebruikt.</p>}
        <div className="action-row">
          <button className="btn btn-accent" onClick={() => void openOffer(result.url, result.instanceBaseUrl).catch((e) => setError(String(e)))}>Open offerte</button>
          <button className="btn btn-secondary" onClick={onClose}>Sluiten</button>
        </div>
      </> : <>
        {matching ? <p className="settings-desc">Klanten zoeken...</p> : <fieldset disabled={creating} style={{ border: 0, padding: 0, display: "flex", flexDirection: "column", gap: 6 }}>
          <legend>Klant</legend>
          {options.map((o) => <label key={o.id}><input type="radio" name="pf-customer" checked={selected === o.id} onChange={() => setSelected(o.id)} /> {o.label}</label>)}
          <label><input type="radio" name="pf-customer" checked={selected === NEW} onChange={() => setSelected(NEW)} /> Nieuwe klant</label>
          {selected === NEW && <input className="input" aria-label="Naam nieuwe klant" value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="Naam van de klant" />}
          <div className="action-row">
            <input className="input" aria-label="Zoek een andere klant" value={query} placeholder="Zoek een andere klant"
              onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void search(); }} />
            <button className="btn btn-secondary btn-sm" onClick={() => void search()}>Zoeken</button>
          </div>
        </fieldset>}
        {creating && <p className="settings-desc" role="status">Regels afleiden, dit kan tot 2 minuten duren.</p>}
        <div className="action-row">
          <button className="btn btn-accent" disabled={!ready || creating || matching} onClick={() => void create()}>Maak conceptofferte</button>
          <button className="btn btn-secondary" disabled={creating} onClick={onClose}>Annuleren</button>
        </div>
      </>}
      {error && <p role="alert" className="text-error">{error}</p>}
    </div>
  </DesktopDialog>;
}
