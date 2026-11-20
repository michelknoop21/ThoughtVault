import { useEffect, useState } from "react";
import { DesktopDialog } from "../ui/DesktopDialog";
import { htmlToPlainText } from "../../utils/htmlToMarkdown";
import { createOffer, loadOfferRef, match, openOffer, searchCustomers, type OfferResult } from "../../services/prospectFlow";
import { customerSources, meetingContext, suggestCustomer, type CustomerSuggestion } from "../../services/customerSuggestion";
import { useCalendarStore } from "../../stores/calendarStore";
import "./prospectFlowDialog.css";
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
  const [suggestion, setSuggestion] = useState<CustomerSuggestion | null>(null);
  const [notice, setNotice] = useState("");
  const [approved, setApproved] = useState(false);
  const [searching, setSearching] = useState(false);
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
    setApproved(false);
    setSuggestion(null);
    setNotice("");
    setError("");
    setMatching(true);
    setOptions([]);
    const sources = customerSources(transcript.title, htmlToPlainText(transcript.notule_html ?? ""),
      transcript.raw_transcription ?? "", meetingContext(transcript.created_at, useCalendarStore.getState().events));
    async function load() {
      let proposed: CustomerSuggestion | null = null;
      try {
        proposed = await suggestCustomer(sources);
        if (!active) return;
        setSuggestion(proposed);
        setNotice(proposed ? "" : "Geen eenduidige klantnaam gevonden. Kies of vul een klant in.");
      } catch {
        if (!active) return;
        setNotice("Klantvoorstel niet beschikbaar. Kies of vul zelf een klant in.");
      }
      if (pendingSelection === null) setNewName(proposed?.name ?? "");
      const found = await match(Object.values(sources).join("\n"));
      if (!active) return;
      const choices = found.map((k) => ({ id: k.id, label: k.plaats ? `${k.naam} (${k.plaats})` : k.naam }));
      if (typeof pendingSelection === "number" && !choices.some(k => k.id === pendingSelection)) {
        choices.unshift({ id: pendingSelection, label: `Eerder gekozen klant (${pendingSelection})` });
      }
      addOptions(choices);
      if (pendingSelection === null) {
        const exact = proposed ? found.filter(c => c.naam.toLowerCase() === proposed.name.toLowerCase()) : found;
        setSelected(exact.length === 1 ? exact[0].id : NEW);
      }
    }
    void load().catch((e) => { if (active) setError(e instanceof Error ? e.message : "Klanten zoeken mislukt"); })
      .finally(() => { if (active) { setMatching(false); setSelected(s => s ?? NEW); } });
    return () => { active = false; };
  }, [taskId, transcript.title, transcript.raw_transcription, transcript.notule_html, transcript.created_at]);

  async function search() {
    if (!query.trim()) return;
    setError("");
    setSearching(true);
    try {
      const found = await searchCustomers(query.trim());
      addOptions(found.map((c) => ({ id: c.id, label: c.city ? `${c.name} (${c.city})` : c.name })));
      if (!found.length) setError("Geen klanten gevonden.");
    } catch (e) { setError(e instanceof Error ? e.message : "Zoeken mislukt"); }
    finally { setSearching(false); }
  }

  const ready = selected === NEW ? newName.trim() !== "" : selected !== null;

  async function create() {
    if (!ready || !approved || matching || creating) return;
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
    <div className="card-static correction-dialog pf-dialog">
      <header><span className="pf-eyebrow">PROSPECT FLOW</span><h3>Van gesprek naar conceptofferte</h3>
        <p className="settings-desc">Controleer je notule en kies de opdrachtgever.</p></header>
      {result ? <>
        <p><strong>Offerte {result.number}</strong>{result.bestaand ? " (al eerder gemaakt)" : ""} voor {result.klant.naam}{result.klant.nieuw ? " (nieuwe klant)" : ""}.</p>
        <p>{result.regels} regels, waarvan {result.te_controleren} te controleren.</p>
        {result.terugval_gebruikt && <p className="settings-desc">Het terugvalmodel is gebruikt.</p>}
        <div className="action-row">
          <button className="btn btn-accent" onClick={() => void openOffer(result.url, result.instanceBaseUrl).catch((e) => setError(String(e)))}>Open offerte</button>
          <button className="btn btn-secondary" onClick={onClose}>Sluiten</button>
        </div>
      </> : <>
        {matching ? <div className="pf-loading" role="status" aria-label="Klant zoeken"><span /><span /><p>Klantnaam afleiden en bestaande klanten zoeken…</p></div> : <>
          {suggestion ? <section className="pf-suggestion" aria-label="Klantvoorstel">
            <span className="pf-eyebrow">Voorgestelde opdrachtgever</span><strong>{suggestion.name}</strong>
            <small>Bron: {{ notes: "notule", transcript: "transcriptie", meeting: "agenda-afspraak", title: "titel" }[suggestion.source]}</small>
            <blockquote>{suggestion.quote}</blockquote>
          </section> : <p className="settings-desc">{notice}</p>}
          <fieldset disabled={creating} className="pf-picker">
            <legend>Klant</legend>
            <div className="pf-search">
              <input className="input" aria-label="Zoek een andere klant" value={query} placeholder="Zoek een andere klant"
                onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void search(); } }} />
              <button className="btn btn-secondary btn-sm" disabled={searching || !query.trim()} onClick={() => void search()}>{searching ? "Zoeken…" : "Zoeken"}</button>
            </div>
            {!!options.length && <div className="pf-options">{options.map((o) => <label key={o.id} className="pf-option"><input type="radio" name="pf-customer" checked={selected === o.id} onChange={() => setSelected(o.id)} /> <span>{o.label}</span></label>)}</div>}
            <label className="pf-option"><input type="radio" name="pf-customer" checked={selected === NEW} onChange={() => setSelected(NEW)} /> Nieuwe klant</label>
            {selected === NEW && <input className="input" aria-label="Naam nieuwe klant" value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="Naam van de klant" />}
          </fieldset>
          <details className="pf-review"><summary>Controleer de definitieve notule</summary><div>{htmlToPlainText(transcript.notule_html ?? "")}</div></details>
          <p className="settings-desc">Beoordeel eerst de woordenboekvoorstellen en sla eventuele wijzigingen op in de notule.</p>
          <label className="pf-approval"><input type="checkbox" checked={approved} disabled={creating} onChange={e => setApproved(e.target.checked)} /> Ik accordeer deze notule voor Prospect Flow</label>
        </>}
        {creating && <p className="settings-desc" role="status">Regels afleiden, dit kan tot 2 minuten duren.</p>}
        <p className="settings-desc">Je maakt een concept. Er wordt niets naar de klant verstuurd.</p>
        <div className="action-row pf-footer">
          <button className="btn btn-accent" disabled={!approved || !ready || creating || matching} onClick={() => void create()}>Maak conceptofferte</button>
          <button className="btn btn-secondary" disabled={creating} onClick={onClose}>Annuleren</button>
        </div>
      </>}
      {error && <p role="alert" className="text-error">{error}</p>}
    </div>
  </DesktopDialog>;
}
