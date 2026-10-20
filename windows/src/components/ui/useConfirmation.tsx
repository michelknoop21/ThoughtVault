import { useEffect, useRef, useState } from "react";
import { DesktopDialog } from "./DesktopDialog";

type Confirmation = { title: string; message: string; acceptLabel: string };

/** Reuses the app sheet and resolves cancellation on Escape, dismissal or unmount. */
export function useConfirmation() {
  const [request, setRequest] = useState<Confirmation | null>(null);
  const pending = useRef<((accepted: boolean) => void) | null>(null);
  useEffect(() => () => { pending.current?.(false); }, []);
  function finish(accepted: boolean) {
    pending.current?.(accepted);
    pending.current = null;
    setRequest(null);
  }
  function confirm(message: string, title: string, acceptLabel: string) {
    pending.current?.(false);
    return new Promise<boolean>(resolve => {
      pending.current = resolve;
      setRequest({ title, message, acceptLabel });
    });
  }
  const confirmation = request && <DesktopDialog label={request.title} onClose={() => finish(false)}>
    <section className="td-confirm" onClick={event => event.stopPropagation()}>
      <h3 className="td-confirm-title">{request.title}</h3>
      <p className="td-confirm-text">{request.message}</p>
      <div className="td-confirm-actions">
        <button autoFocus className="btn btn-secondary" onClick={() => finish(false)}>Annuleren</button>
        <button className="btn btn-accent" onClick={() => finish(true)}>{request.acceptLabel}</button>
      </div>
    </section>
  </DesktopDialog>;
  return { confirm, confirmation };
}
