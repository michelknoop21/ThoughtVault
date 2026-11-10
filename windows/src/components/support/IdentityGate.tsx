import { useRef, useState, type FormEvent, type JSX } from "react";
import { isValidEmail, useSupportStore } from "../../stores/supportStore";

export function IdentityGate(): JSX.Element {
  const [name, setName] = useState(() => useSupportStore.getState().name);
  const [email, setEmail] = useState(() => useSupportStore.getState().email);
  const [emailTouched, setEmailTouched] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const submitting = useRef(false);
  const valid = !!name.trim() && isValidEmail(email);
  const emailInvalid = emailTouched && !isValidEmail(email);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!valid || submitting.current) return;
    submitting.current = true;
    setSubmitted(true);
    const support = useSupportStore.getState();
    support.setIdentity(name.trim(), email.trim());
    // The durable queue retries on startup/online; continuing must work offline.
    void support.flushQueue().catch(() => {});
  }

  return (
    <main style={{ flex: 1, minHeight: 0, overflowY: "auto", display: "flex", padding: 16 }}>
      <form noValidate onSubmit={submit} aria-labelledby="identity-heading" aria-describedby="identity-introduction identity-reporting identity-setting"
        className="flex-col" style={{ width: "100%", maxWidth: 440, margin: "auto", gap: 16, fontSize: 16, lineHeight: 1.5, overflowWrap: "break-word" }}>
        <h1 id="identity-heading" style={{ fontSize: "var(--font-title)", fontWeight: 600, lineHeight: 1.2 }}>Even voorstellen</h1>
        <p id="identity-introduction">Met je naam en e-mailadres kan de ontwikkelaar je meldingen beantwoorden.</p>
        <p id="identity-reporting" style={{ color: "var(--text-secondary)" }}>Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee.</p>
        <p id="identity-setting" style={{ color: "var(--text-secondary)" }}>Automatisch versturen zet je uit bij Instellingen, Account.</p>
        <div className="form-field">
          <label className="form-label" htmlFor="identity-name">Naam</label>
          <input id="identity-name" className="input" type="text" name="name" autoComplete="name" required autoFocus
            style={{ minHeight: 44, fontSize: 16 }} value={name} onChange={event => setName(event.target.value)} />
        </div>
        <div className="form-field">
          <label className="form-label" htmlFor="identity-email">E-mailadres</label>
          <input id="identity-email" className="input" type="email" inputMode="email" name="email" autoComplete="email" required
            style={{ minHeight: 44, fontSize: 16 }} value={email} onChange={event => setEmail(event.target.value)} onBlur={() => setEmailTouched(true)}
            aria-invalid={emailInvalid} aria-describedby={emailInvalid ? "identity-email-error" : undefined} />
          {emailInvalid && <p id="identity-email-error" role="alert" style={{ color: "var(--status-error)" }}>Vul een geldig e-mailadres in.</p>}
        </div>
        <button className="btn btn-accent" type="submit" disabled={!valid || submitted} style={{ minHeight: 44 }}>Doorgaan</button>
      </form>
    </main>
  );
}
