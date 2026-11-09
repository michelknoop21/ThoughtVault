// After a notule is saved, one extra AI call proposes glossary terms and directory
// people from the conversation. Proposals are stored per recording in
// context-suggestions.json until the user accepts or rejects them; nothing is added to
// the glossary automatically. Port of the macOS ContextSuggestions, same prompt and format.
import { invoke } from "@tauri-apps/api/core";
import { containsWord, validTerm, type PersonalCorrection } from "./personalCorrections";
import { usePersonalCorrectionsStore, loadCorrectionsOrEmpty } from "../stores/personalCorrectionsStore";
import { usePersonProfileStore } from "../stores/personProfileStore";
import { LLMService, minutesContext } from "./llm";
import { link } from "./personMatcher";
import type { Participant } from "./participants";

export interface TermSuggestion { heard: string; canonical: string; note: string }
export interface PersonSuggestion {
  name: string;
  role: string;
  organization: string;
  responsibilities: string[];
  topics: string[];
  heardAs: string[];
  /** Directory person this suggestion updates; absent means a new person. */
  matchedPersonId?: string;
  /** Directory people this suggestion could be when the name was ambiguous. */
  candidateIds: string[];
}
export interface ContextSuggestionSet { terms: TermSuggestion[]; people: PersonSuggestion[] }
export type ContextSuggestionItem = { term: TermSuggestion } | { person: PersonSuggestion };

export const MAX_ITEMS = 8;
export const MAX_TRANSCRIPT_CHARACTERS = 64_000;
/** Window event after suggestions for a recording were stored; `detail` is the task id. */
export const SUGGESTIONS_UPDATED_EVENT = "context-suggestions-updated";
const FILE = "context-suggestions.json";

const trim = (text: string) => text.trim();
const list = (items: string[]) => items.map(trim).filter(Boolean);
export const isEmpty = (set: ContextSuggestionSet) => !set.terms.length && !set.people.length;

/** Key stored in the glossary's `dismissed` list when the user rejects a suggestion. */
export function dismissKey(item: ContextSuggestionItem): string {
  return ("term" in item ? `term:${trim(item.term.heard)}→${trim(item.term.canonical)}` : `person:${trim(item.person.name)}`).toLowerCase();
}

// Lenient decoding of AI output and stored sets: missing or mistyped fields become empty.
type Json = Record<string, unknown>;
const isObject = (value: unknown): value is Json => typeof value === "object" && value !== null && !Array.isArray(value);
const str = (value: unknown) => typeof value === "string" ? value : "";
const strs = (value: unknown) => Array.isArray(value) && value.every(v => typeof v === "string") ? value as string[] : [];
const objects = (value: unknown) => Array.isArray(value) && value.every(isObject) ? value : [];
function decodeSet(value: Json): ContextSuggestionSet {
  return {
    terms: objects(value.terms).map(t => ({ heard: str(t.heard), canonical: str(t.canonical), note: str(t.note) })),
    people: objects(value.people).map(p => ({
      name: str(p.name), role: str(p.role), organization: str(p.organization), responsibilities: strs(p.responsibilities),
      topics: strs(p.topics), heardAs: strs(p.heardAs), ...(typeof p.matchedPersonId === "string" ? { matchedPersonId: p.matchedPersonId } : {}),
      candidateIds: strs(p.candidateIds),
    })),
  };
}

/** A note valid for PersonalCorrection: one line, no angle brackets, at most 200 UTF-16 units. */
function noteText(text: string): string {
  const characters = Array.from(text.replace(/[\r\n<>]/g, " ").trim());
  while (characters.join("").length > 200) characters.pop();
  return characters.join("").trim();
}

/**
 * Turns the raw AI reply into checked suggestions. Never throws: anything unusable is dropped.
 * The user is never suggested: a name equal to `selfNames` or `selfAliases` is dropped, a heardAs
 * spelling only when it equals a self name (a bare first-name alias would otherwise drop everyone
 * else with that first name).
 */
export function parse(raw: string, transcript: string, entries: PersonalCorrection[], dismissed: string[], selfNames: string[] = [], selfAliases: string[] = []): ContextSuggestionSet {
  // Reasoning models may prefix their answer with a think block that can contain braces.
  const text = raw.replace(/<think>[\s\S]*?<\/think>/g, "");
  const start = text.indexOf("{"), end = text.lastIndexOf("}");
  let decoded: ContextSuggestionSet;
  try {
    const value: unknown = start >= 0 && start < end ? JSON.parse(text.slice(start, end + 1)) : undefined;
    if (!isObject(value)) return { terms: [], people: [] };
    decoded = decodeSet(value);
  } catch {
    return { terms: [], people: [] };
  }
  const rejected = new Set(dismissed.map(d => d.toLowerCase()));
  const known = new Set(entries.flatMap(e => [e.canonical, ...e.variants]).map(v => trim(v).toLowerCase()));
  const ownNames = new Set(selfNames.map(n => trim(n).toLowerCase()).filter(Boolean));
  const ownNamesAndAliases = new Set([...ownNames, ...selfAliases.map(a => trim(a).toLowerCase()).filter(Boolean)]);

  const seen = new Set<string>(), terms: TermSuggestion[] = [], people: PersonSuggestion[] = [];
  // "a / b" in heard is several spellings in one item: one term per spelling found.
  for (const term of decoded.terms) {
    for (const heard of term.heard.split(" / ")) {
      if (terms.length >= MAX_ITEMS) break;
      const cleaned = { heard: trim(heard), canonical: trim(term.canonical), note: noteText(term.note) };
      const key = dismissKey({ term: cleaned });
      if (!validTerm(cleaned.heard) || !validTerm(cleaned.canonical) || cleaned.heard.toLowerCase() === cleaned.canonical.toLowerCase()
        || known.has(cleaned.canonical.toLowerCase()) || rejected.has(key) || !containsWord(cleaned.heard, transcript) || seen.has(key)) continue;
      seen.add(key);
      terms.push(cleaned);
    }
  }
  for (const person of decoded.people) {
    if (people.length >= MAX_ITEMS) break;
    const cleaned: PersonSuggestion = {
      name: trim(person.name), role: trim(person.role), organization: trim(person.organization),
      responsibilities: list(person.responsibilities), topics: list(person.topics), heardAs: list(person.heardAs), candidateIds: [],
    };
    const key = dismissKey({ person: cleaned });
    if (!cleaned.name || rejected.has(key) || ownNamesAndAliases.has(cleaned.name.toLowerCase())
      || cleaned.heardAs.some(h => ownNames.has(h.toLowerCase())) || seen.has(key)) continue;
    seen.add(key);
    people.push(cleaned);
  }
  return { terms, people };
}

// MARK: Storage

/** Suggestions are disposable: an unreadable file counts as empty and is replaced on the next write. */
async function loadAll(): Promise<Record<string, ContextSuggestionSet>> {
  try {
    const value: unknown = JSON.parse(await invoke<string | null>("read_context_file", { name: FILE }) ?? "{}");
    if (!isObject(value) || !Object.values(value).every(isObject)) return {};
    return Object.fromEntries(Object.entries(value).map(([taskId, set]) => [taskId, decodeSet(set as Json)]));
  } catch {
    return {};
  }
}

let queue: Promise<unknown> = Promise.resolve();
function serial<T>(operation: () => Promise<T>): Promise<T> {
  const next = queue.then(operation);
  queue = next.catch(() => {});
  return next;
}

export const load = (taskId: string): Promise<ContextSuggestionSet | undefined> => serial(async () => (await loadAll())[taskId]);

async function write(set: ContextSuggestionSet, taskId: string) {
  const all = await loadAll();
  const next = isEmpty(set) ? undefined : set;
  if (JSON.stringify(all[taskId]) === JSON.stringify(next)) return;
  if (next) all[taskId] = next; else delete all[taskId];
  await invoke("write_context_file", { name: FILE, contents: JSON.stringify(all) });
}

/** Replaces the suggestions for `taskId`; an empty set removes them. */
export const save = (set: ContextSuggestionSet, taskId: string): Promise<void> => serial(() => write(set, taskId));

/** Removes one handled suggestion (matched on its dismiss key). */
export const remove = (taskId: string, item: ContextSuggestionItem): Promise<void> => serial(async () => {
  const set = (await loadAll())[taskId];
  if (!set) return;
  const key = dismissKey(item);
  await write({ terms: set.terms.filter(term => dismissKey({ term }) !== key), people: set.people.filter(person => dismissKey({ person }) !== key) }, taskId);
});

/** Swaps one person suggestion (matched on its dismiss key) for `next`, e.g. a remainder. */
export const replacePerson = (taskId: string, old: PersonSuggestion, next: PersonSuggestion): Promise<void> => serial(async () => {
  const set = (await loadAll())[taskId];
  if (!set) return;
  const key = dismissKey({ person: old });
  await write({ ...set, people: set.people.map(person => dismissKey({ person }) === key ? next : person) }, taskId);
});

/** Remembers a rejected suggestion so it is not offered again. */
export const dismiss = (key: string): Promise<void> => usePersonalCorrectionsStore.getState().addDismissed(key);

// MARK: AI step

/**
 * Starts the suggestion call after the notule was saved. Fire and forget: failures are only
 * logged and never touch the notule. Skipped for very long transcripts and under tests.
 */
export function runInBackground(taskId: string, transcript: string, participants: Participant[], profileId: string | undefined, profileName: string): void {
  if (import.meta.env.MODE === "test" || Array.from(transcript).length > MAX_TRANSCRIPT_CHARACTERS) return;
  void (async () => {
    try {
      const entries = await loadCorrectionsOrEmpty();
      const me = usePersonProfileStore.getState().profile;
      const message = userMessage(minutesContext(entries, transcript, profileId), participants, me?.name ?? "", transcript);
      const raw = await LLMService.complete(SYSTEM_PROMPT, message);
      const parsed = parse(raw, transcript, entries, usePersonalCorrectionsStore.getState().dismissed, [me?.name ?? ""], me?.aliases ?? []);
      // Matched people are filled in directly; only what needs the user is stored.
      const set = await link(parsed, taskId, profileName);
      await save(set, taskId);
      window.dispatchEvent(new CustomEvent(SUGGESTIONS_UPDATED_EVENT, { detail: taskId }));
      console.info(`[ContextSuggestions] ${set.terms.length} termen, ${set.people.length} personen`);
    } catch (error) {
      console.warn("[ContextSuggestions] Contextvoorstellen mislukt:", error instanceof Error ? error.message : String(error));
    }
  })();
}

export const SYSTEM_PROMPT = `Je helpt een persoonlijke woordenlijst en personenlijst bij te houden voor gespreksverslagen. Je krijgt de bekende context, de naam van de gebruiker, de deelnemers en een automatisch herkende transcriptie. Antwoord uitsluitend met één JSON-object, zonder uitleg en zonder code fences, in precies deze vorm:
{"terms":[{"heard":"","canonical":"","note":""}],"people":[{"name":"","role":"","organization":"","responsibilities":[],"topics":[],"heardAs":[]}]}

Regels:
- terms zijn alleen eigennamen, organisaties, producten, merken, afkortingen of vakjargon die de gebruiker in een persoonlijke woordenlijst zou willen hebben en die de spraakherkenning waarschijnlijk verkeerd heeft verstaan.
- Een gewoon Nederlands woord met een herkenningsfout is nooit een term.
- heard is precies één letterlijke schrijfwijze zoals die in de transcriptie staat. Komt een term in meerdere schrijfwijzen voor, herhaal het item dan per schrijfwijze.
- canonical is de juiste schrijfwijze. note is een korte toelichting van hooguit één zin.
- Stel geen term voor die al in de bekende context staat.
- people zijn alleen personen die in het gesprek met naam worden genoemd en een rol spelen. Laat personen zonder naam weg, zoals "mijn schoonvader". Stel de gebruiker zelf nooit voor.
- Vul role, organization en responsibilities alleen in als dat in het gesprek expliciet wordt gezegd. Anders laat je ze leeg.
- topics zijn de onderwerpen waar de persoon in dit gesprek bij betrokken is. heardAs bevat letterlijke schrijfwijzen van de naam uit de transcriptie.
- Liever een paar zekere items dan veel twijfelachtige: hooguit 8 terms en 8 people.
- Verzin geen feiten. Twijfel je, laat het item dan weg.
- Voldoet er niets, antwoord dan met {"terms":[],"people":[]}.`;

export function userMessage(context: string, participants: Participant[], selfName: string, transcript: string): string {
  const people = participants.map(person => {
    const detail = [person.role, person.organization].map(trim).filter(Boolean).join(", ");
    return "- " + trim(person.name) + (detail ? ` (${detail})` : "");
  });
  return "Bekende context:\n" + (trim(context) || "(leeg)")
    + (trim(selfName) ? "\n\nGebruiker (niet voorstellen): " + trim(selfName) : "")
    + "\n\nDeelnemers:\n" + (people.length ? people.join("\n") : "(niet opgegeven)")
    + "\n\nTranscriptie:\n" + transcript;
}
