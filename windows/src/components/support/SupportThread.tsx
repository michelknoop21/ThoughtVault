import { useEffect, useRef, useState } from "react";
import { postMessage, ticketMessages } from "../../services/supportRelay";
import type { HubStatus, SupportMessage, SupportTicket } from "../../services/supportRelay";
import { useSupportStore, withInstallation } from "../../stores/supportStore";
import { useToast } from "../ui/InfoBar";

export const STATUS_LABELS: Record<HubStatus, string> = {
  NEW: "Nieuw", IN_PROGRESS: "In behandeling", WAITING_FOR_USER: "Wacht op jou",
  RESOLVED: "Opgelost", CLOSED: "Gesloten",
};
const statusLabel = (status: HubStatus): string => Object.prototype.hasOwnProperty.call(STATUS_LABELS, status) ? STATUS_LABELS[status] : status;
const ordered = (messages: SupportMessage[]) => [...messages].sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
function formatDate(value: string): string {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toLocaleString("nl-NL", { dateStyle: "medium", timeStyle: "short" }) : "";
}
export function TicketRow({ ticket, onOpen }: { ticket: SupportTicket; onOpen: () => void }) {
  return <button className="btn btn-secondary" onClick={onOpen} style={{ display: "flex", flexDirection: "column", alignItems: "stretch", textAlign: "left", padding: 12, gap: 8, whiteSpace: "normal", overflowWrap: "anywhere", minHeight: 44 }}>
    <span className="flex-row" style={{ justifyContent: "space-between", gap: 8 }}>
      <strong>{ticket.ref}{ticket.unread && <span aria-label="Ongelezen"> •</span>}</strong>
      <span className={ticket.status === "RESOLVED" || ticket.status === "CLOSED" ? "status-badge-success" : "status-badge-neutral"}>{statusLabel(ticket.status)}</span>
    </span>
    <span style={{ whiteSpace: "pre-wrap" }}>{ticket.description}</span>
    {ticket.lastMessage && <span className="text-caption">{ticket.lastMessage.excerpt}</span>}
    <span className="text-caption" style={{ color: "var(--text-secondary)" }}>{formatDate(ticket.updatedAt ?? ticket.createdAt)}</span>
  </button>;
}

export function SupportThread({ ticket, onBack, draft, onDraftChange, onBusyChange }: {
  ticket: SupportTicket; onBack: () => void; draft?: string;
  onDraftChange?: (value: string) => void; onBusyChange?: (busy: boolean) => void;
}) {
  const [loaded, setLoaded] = useState<{ ticketId: string; messages: SupportMessage[] }>({ ticketId: ticket.id, messages: [] });
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const request = useRef(0);
  const locked = useRef(false);
  const toast = useToast();
  const value = draft ?? drafts[ticket.id] ?? "";
  const setDraft = (next: string) => {
    if (onDraftChange) onDraftChange(next);
    else setDrafts(current => ({ ...current, [ticket.id]: next }));
  };
  useEffect(() => {
    const generation = ++request.current;
    setLoading(true); setError("");
    void withInstallation(inst => ticketMessages(inst, ticket.id)).then(messages => {
      if (generation !== request.current) return;
      setLoaded({ ticketId: ticket.id, messages: ordered(messages) });
      void useSupportStore.getState().refreshUnread();
    }).catch(() => {
      if (generation === request.current) setError("Berichten ophalen lukt nu niet.");
    }).finally(() => { if (generation === request.current) setLoading(false); });
    return () => { request.current++; };
  }, [ticket.id]);
  const reply = async () => {
    const body = value.trim();
    if (locked.current || !body || Array.from(body).length > 5000) return;
    locked.current = true; setSending(true); onBusyChange?.(true);
    const generation = request.current;
    try {
      const message = await withInstallation(inst => postMessage(inst, ticket.id, body));
      if (generation !== request.current) return;
      setLoaded(current => ({ ticketId: ticket.id, messages: ordered([
        ...(current.ticketId === ticket.id ? current.messages.filter(item => item.id !== message.id) : []), message,
      ]) }));
      setDraft("");
    } catch {
      if (generation === request.current) toast.show("Antwoord versturen lukt nu niet. Je tekst blijft bewaard.", "error");
    } finally {
      locked.current = false; setSending(false); onBusyChange?.(false);
    }
  };
  const messages = loaded.ticketId === ticket.id ? loaded.messages : [];
  return <section className="flex-col" aria-label={`Melding ${ticket.ref}`} style={{ gap: 12, overflowWrap: "anywhere" }}>
    <button className="btn btn-secondary" aria-label="Terug naar mijn meldingen" disabled={sending} onClick={onBack} style={{ minHeight: 44 }}>Terug naar mijn meldingen</button>
    <div className="flex-row" style={{ justifyContent: "space-between", gap: 8 }}><strong>{ticket.ref}</strong><span className="status-badge-neutral">{statusLabel(ticket.status)}</span></div>
    <p style={{ whiteSpace: "pre-wrap" }}>{ticket.description}</p>
    {loading && <p role="status">Berichten laden...</p>}
    {error && <p role="alert">{error}</p>}
    {messages.map(message => <article key={message.id} style={{ padding: 12, borderRadius: "var(--radius-xs)", background: message.senderRole.toLowerCase() === "user" ? "var(--surface-secondary)" : "var(--accent-bg-secondary)", border: "1px solid var(--border-secondary)" }}>
      <strong>{message.senderRole.toLowerCase() === "user" ? "Jij" : "ThoughtVault"}</strong>
      <p style={{ whiteSpace: "pre-wrap", margin: "8px 0" }}>{message.body}</p>
      <time className="text-caption" dateTime={message.createdAt}>{formatDate(message.createdAt)}</time>
    </article>)}
    <label className="form-label">Antwoord
      <textarea className="input" rows={4} maxLength={5000} value={value} disabled={sending} onChange={event => setDraft(event.target.value)} style={{ display: "block", width: "100%", resize: "vertical" }} />
    </label>
    <button className="btn btn-accent" disabled={sending || loading || !value.trim() || Array.from(value.trim()).length > 5000} onClick={() => void reply()} style={{ minHeight: 44 }}>{sending ? "Versturen..." : "Antwoord versturen"}</button>
  </section>;
}
