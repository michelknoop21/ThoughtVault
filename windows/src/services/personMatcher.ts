// Links people suggested from a conversation to directory people. A clear match is
// filled in automatically (meeting type, topics, responsibilities); changes to role,
// organization or aliases are only ever proposed, never written. Port of the macOS PersonMatcher.
import { usePeopleDirectoryStore } from "../stores/peopleDirectoryStore";
import { personSnapshot, type PersonSnapshot } from "./contextHistory";
import type { ContextSuggestionSet, PersonSuggestion } from "./contextSuggestions";
import type { PersonProfile } from "../types";

export type MatchResult = { kind: "existing"; id: string } | { kind: "ambiguous"; ids: string[] } | { kind: "new" };
export type Candidate = { id: string; snapshot: PersonSnapshot };

/** Comparison form: case and diacritics folded, whitespace collapsed. */
const key = (text: string) => text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().split(/\s+/).filter(Boolean).join(" ");
const words = (text: string) => text.split(/\s+/).filter(Boolean);
const names = (person: PersonSnapshot) => new Set([person.name, ...person.aliases].map(key).filter(Boolean));
const firstWord = (name: string) => words(key(name))[0] ?? "";
const differs = (next: string, old: string) => !!key(next) && key(next) !== key(old);
const result = (ids: string[]): MatchResult =>
  ids.length === 0 ? { kind: "new" } : ids.length === 1 ? { kind: "existing", id: ids[0] } : { kind: "ambiguous", ids };

/** Appends new items that are not there yet (case-insensitive), keeping existing spelling. */
function merged(existing: string[], added: string[]): string[] {
  const seen = new Set(existing.map(key));
  return [...existing, ...added.map(item => item.trim()).filter(item => {
    if (!item || seen.has(key(item))) return false;
    seen.add(key(item));
    return true;
  })];
}

/** Directory people as match candidates. The self profile is never one. */
export function candidates(people: PersonProfile[]): Candidate[] {
  return people.filter(p => !p.isSelf).map(p => ({ id: p.id, snapshot: personSnapshot(p) }));
}

/**
 * Exact name or alias first (the suggested name, plus heardAs spellings of more than one
 * word); then a suggested name that is a bare first name links only when exactly one
 * person has it. More than one candidate is ambiguous. A one-word heardAs never links.
 */
export function match(s: PersonSuggestion, people: Candidate[]): MatchResult {
  const name = key(s.name);
  const spellings = [name, ...s.heardAs.map(key).filter(h => words(h).length > 1)].filter(Boolean);
  const exact = people.filter(p => spellings.some(spelling => names(p.snapshot).has(spelling))).map(p => p.id);
  if (exact.length) return result(exact);
  if (words(name).length !== 1) return { kind: "new" };
  return result(people.filter(p => firstWord(p.snapshot.name) === name).map(p => p.id));
}

/**
 * Adds the meeting type, topics and responsibilities to the person (no duplicates, existing
 * spelling kept) and returns what is left to propose: a different or new role or organization,
 * and new spellings of the name. null when nothing is left.
 */
export async function autoApply(s: PersonSuggestion, id: string, profileName: string, taskId: string): Promise<PersonSuggestion | null> {
  const store = usePeopleDirectoryStore.getState();
  const person = store.people.find(p => p.id === id);
  if (!person) return s;
  await store.recordUpdate(id, `gesprek:${taskId}`, {
    meetingTypes: merged(person.meetingTypes, [profileName]),
    expertiseTags: merged(person.expertiseTags, s.topics),
    responsibilities: merged(person.responsibilities ?? [], s.responsibilities),
  });
  const role = differs(s.role, person.role) ? s.role.trim() : "";
  const organization = differs(s.organization, person.organization) ? s.organization.trim() : "";
  const known = names(personSnapshot(person));
  // A bare first name is never proposed as an alias: it would bypass the first-name uniqueness check.
  const aliases = [...(words(key(s.name)).length > 1 ? [s.name] : []), ...s.heardAs].map(a => a.trim()).filter(a => {
    if (!a || known.has(key(a))) return false;
    known.add(key(a));
    return true;
  });
  if (!role && !organization && !aliases.length) return null;
  return { name: s.name, role, organization, responsibilities: [], topics: [], heardAs: aliases, matchedPersonId: id, candidateIds: [] };
}

/**
 * Runs after the AI step: fills in matched people and returns only what still needs the user
 * (remainders, ambiguous and new people). Windows keeps no participants per recording, so the
 * macOS participant-linking step has nothing to link here.
 */
export async function link(set: ContextSuggestionSet, taskId: string, profileName: string): Promise<ContextSuggestionSet> {
  const people = candidates(usePeopleDirectoryStore.getState().people);
  const kept: ContextSuggestionSet = { terms: set.terms, people: [] };
  for (const suggestion of set.people) {
    const found = match(suggestion, people);
    if (found.kind === "existing") {
      try {
        const rest = await autoApply(suggestion, found.id, profileName, taskId);
        if (rest) kept.people.push(rest);
      } catch (error) {
        console.warn("[PersonMatcher] Automatisch aanvullen mislukt:", error instanceof Error ? error.message : String(error));
        kept.people.push({ ...suggestion, matchedPersonId: found.id });
      }
    } else if (found.kind === "ambiguous") {
      kept.people.push({ ...suggestion, candidateIds: found.ids });
    } else {
      kept.people.push(suggestion);
    }
  }
  return kept;
}
