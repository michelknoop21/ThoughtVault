// Compact bar above the notule with the term and people suggestions from the context
// step. Each suggestion is accepted, applied or ignored here; handled suggestions
// disappear and the bar hides when none are left. Mirrors the macOS ContextSuggestionBar.
import { useCallback, useEffect, useState, type ReactNode } from "react";
import { ChevronRight24Regular, Sparkle24Regular } from "../ui/StudioIcons";
import { usePeopleDirectoryStore } from "../../stores/peopleDirectoryStore";
import { dismiss, dismissKey, load, remove, replacePerson, SKIP_NOTICES, SUGGESTIONS_UPDATED_EVENT, type ContextSuggestionItem, type ContextSuggestionSet, type PersonSuggestion, type TermSuggestion } from "../../services/contextSuggestions";
import { autoApply } from "../../services/personMatcher";
import { personSnapshot } from "../../services/contextHistory";
import type { PersonalCorrection } from "../../services/personalCorrections";
import type { PersonProfile } from "../../types";
import { PersonEditModal } from "../../pages/PersonEditModal";
import { ambiguousQuestion, applyRemainder, changeSummary, counter } from "./contextSuggestionBarLogic";

interface ContextSuggestionBarProps {
  taskId: string;
  /** Meeting type added to a person chosen from an ambiguous suggestion. */
  profileName: string;
  /** Profile scope for a new glossary term (same default as "Woord corrigeren"). */
  scope: string | null;
  /** Opens the word-correction dialog with `entry`; calls `done` once the correction was applied. */
  onAddTerm: (entry: PersonalCorrection, done: () => void) => void;
}

const message = (error: unknown) => error instanceof Error ? error.message : String(error);

export function ContextSuggestionBar({ taskId, profileName, scope, onAddTerm }: ContextSuggestionBarProps) {
  const people = usePeopleDirectoryStore((s) => s.people);
  const [set, setSet] = useState<ContextSuggestionSet>({ terms: [], people: [] });
  const [expanded, setExpanded] = useState(false);
  const [error, setError] = useState("");
  const [adding, setAdding] = useState<{ suggestion: PersonSuggestion; person: PersonProfile } | null>(null);

  const reload = useCallback(async () => {
    setSet((await load(taskId)) ?? { terms: [], people: [] });
  }, [taskId]);

  useEffect(() => {
    setError("");
    void reload();
    const onUpdate = (event: Event) => { if ((event as CustomEvent<string>).detail === taskId) void reload(); };
    window.addEventListener(SUGGESTIONS_UPDATED_EVENT, onUpdate);
    return () => window.removeEventListener(SUGGESTIONS_UPDATED_EVENT, onUpdate);
  }, [taskId, reload]);

  /** Removes a handled suggestion; `dismissed` also keeps it from being offered again. */
  async function finish(item: ContextSuggestionItem, dismissed = false) {
    try {
      if (dismissed) await dismiss(dismissKey(item));
      await remove(taskId, item);
      setError("");
    } catch (e) {
      setError(`Voorstel verwerken mislukt: ${message(e)}`);
    }
    await reload();
  }

  async function replace(old: PersonSuggestion, next: PersonSuggestion) {
    try {
      await replacePerson(taskId, old, next);
      setError("");
    } catch (e) {
      setError(`Voorstel verwerken mislukt: ${message(e)}`);
    }
    await reload();
  }

  /** Applies a remainder to the matched person; the row showed the changes beforehand. */
  async function update(s: PersonSuggestion) {
    const person = people.find(p => p.id === s.matchedPersonId);
    if (!person) { setError("Deze persoon staat niet meer in de personenlijst."); return; }
    try {
      const next = applyRemainder(s, personSnapshot(person));
      await usePeopleDirectoryStore.getState().recordUpdate(person.id, `voorstel:${taskId}`, { role: next.role, organization: next.organization, aliases: next.aliases });
      await finish({ person: s });
    } catch (e) {
      setError(`Bijwerken mislukt: ${message(e)}`);
    }
  }

  /** Fills in the chosen person; what still needs the user stays as a remainder row. */
  async function choose(id: string, s: PersonSuggestion) {
    try {
      const rest = await autoApply(s, id, profileName, taskId);
      if (rest) await replace(s, rest); else await finish({ person: s });
    } catch (e) {
      setError(`Koppelen mislukt: ${message(e)}`);
    }
  }

  function addTerm(term: TermSuggestion) {
    onAddTerm({ id: crypto.randomUUID(), canonical: term.canonical, variants: [term.heard], scope, enabled: true, ...(term.note ? { note: term.note } : {}) },
      () => void finish({ term }));
  }

  function addPerson(s: PersonSuggestion) {
    const meetingType = profileName.trim();
    const person = usePeopleDirectoryStore.getState().createDefaultPerson({
      name: s.name, role: s.role, organization: s.organization, aliases: s.heardAs, expertiseTags: s.topics,
      responsibilities: s.responsibilities, meetingTypes: meetingType ? [meetingType] : [],
    });
    setAdding({ suggestion: s, person });
  }

  const ignore = (item: ContextSuggestionItem) =>
    <button className="btn btn-secondary btn-sm" onClick={() => void finish(item, true)}>Negeren</button>;

  function personRow(s: PersonSuggestion) {
    const candidates = s.candidateIds.map(id => people.find(p => p.id === id)).filter((p): p is PersonProfile => !!p);
    if (s.matchedPersonId) {
      const current = people.find(p => p.id === s.matchedPersonId);
      return <Row key={dismissKey({ person: s })} title={current?.name ?? s.name} detail={current ? changeSummary(s, personSnapshot(current)) : []}>
        <button className="btn btn-accent btn-sm" onClick={() => void update(s)}>Bijwerken</button>{ignore({ person: s })}
      </Row>;
    }
    if (candidates.length > 1) {
      return <Row key={dismissKey({ person: s })} title={ambiguousQuestion(candidates.map(p => p.name))} detail={[s.name]}>
        {candidates.map(p => <button key={p.id} className="btn btn-secondary btn-sm" onClick={() => void choose(p.id, s)}>{p.name}</button>)}
        <button className="btn btn-secondary btn-sm" onClick={() => void replace(s, { ...s, candidateIds: [] })}>{candidates.length > 2 ? "Geen van deze" : "Geen van beiden"}</button>
        {ignore({ person: s })}
      </Row>;
    }
    const detail = [[s.role, s.organization].filter(Boolean).join(", "), s.responsibilities.length ? "Taken: " + s.responsibilities.join(", ") : ""];
    return <Row key={dismissKey({ person: s })} title={s.name} detail={detail}>
      <button className="btn btn-accent btn-sm" onClick={() => addPerson(s)}>Toevoegen</button>{ignore({ person: s })}
    </Row>;
  }

  const hasItems = set.terms.length > 0 || set.people.length > 0;
  const count = counter(set.terms.length, set.people.length);
  // The add-person sheet stays open after its suggestion is handled, even when the bar empties.
  return <>{(hasItems || set.skipped || error) && <section className="context-bar" aria-label="Voorstellen">
    {hasItems && <button className="context-bar-header" onClick={() => setExpanded(!expanded)} aria-expanded={expanded} aria-label={`Voorstellen, ${count}`}>
      <Sparkle24Regular className="context-bar-icon" />
      <strong>Voorstellen</strong>
      <span className="context-bar-count">{count}</span>
      <ChevronRight24Regular className={`context-bar-chevron${expanded ? " open" : ""}`} />
    </button>}
    {expanded && set.terms.map(term => <Row key={dismissKey({ term })} title={`${term.heard} → ${term.canonical}`} detail={[term.note]}>
      <button className="btn btn-accent btn-sm" onClick={() => addTerm(term)}>Toevoegen</button>{ignore({ term })}
    </Row>)}
    {expanded && set.people.map(personRow)}
    {set.skipped && <p className="context-bar-detail">{SKIP_NOTICES[set.skipped]}</p>}
    {error && <p className="context-bar-error" role="alert">{error}</p>}
  </section>}
  {adding && <PersonEditModal person={adding.person} isNew
    onAdded={() => void finish({ person: adding.suggestion })}
    onClose={() => setAdding(null)} />}
  </>;
}

/** Title, secondary lines and buttons that wrap when the row is too narrow. */
function Row({ title, detail, children }: { title: string; detail: string[]; children: ReactNode }) {
  return <div className="context-bar-row">
    <strong>{title}</strong>
    {detail.filter(Boolean).map((line, index) => <span key={index} className="context-bar-detail">{line}</span>)}
    <div className="context-bar-buttons">{children}</div>
  </div>;
}
