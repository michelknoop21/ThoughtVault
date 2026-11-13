import { useEffect, useRef, useState } from "react";
import { DesktopDialog } from "./ui/DesktopDialog";
import { Bug24Regular, Dismiss16Regular, Send20Regular } from "./ui/StudioIcons";
import { useToast } from "./ui/InfoBar";
import { listTickets } from "../services/supportRelay";
import type { ReportCategory, SupportTicket } from "../services/supportRelay";
import { useSupportStore, withInstallation } from "../stores/supportStore";
import { SupportThread, TicketRow } from "./support/SupportThread";

type Tab = "new" | "history";
const CATEGORY_OPTIONS: { value: ReportCategory; label: string }[] = [
  { value: "BUG", label: "Probleem" }, { value: "FEATURE_REQUEST", label: "Suggestie" }, { value: "QUESTION", label: "Vraag" },
];
export default function FeedbackWidget({ initialOpen = false }: { initialOpen?: boolean }) {
  const [open, setOpen] = useState(initialOpen);
  const [tab, setTab] = useState<Tab>("new");
  const [category, setCategory] = useState<ReportCategory>("BUG");
  const [description, setDescription] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [replying, setReplying] = useState(false);
  const [tickets, setTickets] = useState<SupportTicket[]>([]);
  const [selected, setSelected] = useState<SupportTicket | null>(null);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);
  const locked = useRef(false);
  const historyRequest = useRef(0);
  const unread = useSupportStore(state => state.unread_count);
  const toast = useToast();
  const busy = submitting || replying;
  const close = () => { if (!locked.current) setOpen(false); };
  useEffect(() => {
    if (!open || tab !== "history" || selected) return;
    const generation = ++historyRequest.current;
    setLoading(true);
    void withInstallation(listTickets).then(items => {
      if (generation === historyRequest.current) setTickets(items);
    }).catch(() => {
      if (generation !== historyRequest.current) return;
      setTickets([]); toast.show("Meldingen ophalen lukt nu niet.", "error");
    }).finally(() => { if (generation === historyRequest.current) setLoading(false); });
    return () => { historyRequest.current++; };
  }, [open, tab, selected, toast.show]);
  const submit = async () => {
    const body = description.trim();
    if (locked.current || !body || Array.from(body).length > 5000) return;
    locked.current = true; setSubmitting(true);
    try {
      const outcome = await useSupportStore.getState().submitManual(category, body);
      if (outcome === "sent" || outcome === "queued") {
        setDescription(""); setCategory("BUG");
        toast.show(outcome === "sent" ? "Melding verstuurd." : "Geen verbinding. De melding wordt verstuurd zodra er weer internet is.", outcome === "sent" ? "success" : "info");
      } else toast.show("Melding versturen lukt nu niet. Je tekst blijft bewaard.", "error");
    } catch {
      toast.show("Melding versturen lukt nu niet. Je tekst blijft bewaard.", "error");
    } finally { locked.current = false; setSubmitting(false); }
  };
  return <>
    <button onClick={() => setOpen(true)} className="btn btn-secondary feedback-trigger" aria-label="Feedback openen" title="Feedback">
      <Bug24Regular />Probleem melden of suggestie
      {unread > 0 && <span aria-label={`${unread} ongelezen reacties`} style={{ position: "absolute", top: -2, right: -2, minWidth: 18, height: 18, borderRadius: 9, background: "var(--status-error)", color: "oklch(0.98 0.005 80)", fontSize: "var(--font-micro)", fontWeight: 700, padding: "0 5px" }}>{unread}</span>}
    </button>
    {open && <DesktopDialog label="Feedback" onClose={close}>
      <div className="feedback-panel" style={{ width: Math.min(360, window.innerWidth - 40), maxHeight: "calc(100dvh - 32px)", background: "var(--card-bg)", backdropFilter: "blur(var(--card-blur))", border: "1px solid var(--card-border)", borderRadius: "var(--radius-sm)", boxShadow: "0 8px 32px rgba(0,0,0,0.16)", display: "flex", flexDirection: "column", overflow: "hidden", animation: "feedbackSlideIn 150ms var(--ease-smooth)" }}>
        <div className="flex-row" style={{ padding: "12px 16px", borderBottom: "1px solid var(--border-secondary)", alignItems: "center", justifyContent: "space-between", gap: 8, flexShrink: 0 }}>
          <span style={{ fontSize: "var(--font-headline)", fontWeight: 600, color: "var(--text-primary)" }}>Feedback</span>
          <button className="btn btn-ghost" onClick={close} disabled={busy} aria-label="Feedback sluiten" style={{ minWidth: 44, minHeight: 44, padding: 8 }}><Dismiss16Regular /></button>
        </div>
        <div className="flex-row" aria-label="Feedbackweergave" style={{ padding: "0 16px", borderBottom: "1px solid var(--border-secondary)", gap: 0, flexShrink: 0 }}>
          {(["new", "history"] as Tab[]).map(item => <button key={item} disabled={busy} aria-pressed={tab === item} onClick={() => { if (!locked.current) { setSelected(null); setTab(item); } }} style={{ background: "none", border: "none", borderBottom: tab === item ? "2px solid var(--brand-primary)" : "2px solid transparent", color: tab === item ? "var(--brand-primary)" : "var(--text-secondary)", fontSize: "var(--font-body)", fontWeight: tab === item ? 600 : 400, padding: "10px 16px", minHeight: 44 }}>{item === "new" ? "Nieuw" : "Mijn meldingen"}</button>)}
        </div>
        <div style={{ flex: 1, minHeight: 0, overflowY: "auto", padding: 16 }}>
          {tab === "new" ? <div className="flex-col" style={{ gap: 12 }}>
            <label className="form-label">Categorie
              <select className="select" value={category} disabled={submitting} onChange={event => setCategory(event.target.value as ReportCategory)} style={{ width: "100%", minHeight: 44 }}>{CATEGORY_OPTIONS.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select>
            </label>
            <label className="form-label">Beschrijving
              <textarea className="input" rows={4} maxLength={5000} value={description} disabled={submitting} onChange={event => setDescription(event.target.value)} placeholder="Beschrijf je melding..." style={{ display: "block", width: "100%", resize: "vertical" }} />
            </label>
            <p className="text-caption" style={{ color: "var(--text-secondary)" }}>Je melding wordt met je naam, e-mailadres en technische log naar ThoughtVault verstuurd. Voeg geen wachtwoorden of andere gevoelige gegevens toe.</p>
            <button className="btn btn-accent" onClick={() => void submit()} disabled={submitting || !description.trim() || Array.from(description.trim()).length > 5000} style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 6, minHeight: 44 }}><Send20Regular />{submitting ? "Versturen..." : "Versturen"}</button>
          </div> : selected ? <SupportThread key={selected.id} ticket={selected} onBack={() => setSelected(null)} draft={drafts[selected.id] ?? ""} onDraftChange={value => setDrafts(current => ({ ...current, [selected.id]: value }))} onBusyChange={value => { locked.current = value; setReplying(value); }} /> : <div className="flex-col" style={{ gap: 8 }}>
            {loading ? <p role="status" className="text-caption">Meldingen laden...</p> : tickets.length === 0 ? <p className="text-caption" style={{ textAlign: "center", padding: 24, color: "var(--text-secondary)" }}>Nog geen meldingen verstuurd.</p> : tickets.map(ticket => <TicketRow key={ticket.id} ticket={ticket} onOpen={() => setSelected(ticket)} />)}
          </div>}
        </div>
      </div>
    </DesktopDialog>}
  </>;
}
