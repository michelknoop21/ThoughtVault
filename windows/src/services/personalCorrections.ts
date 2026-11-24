import { similarity } from "./glossaryAutoMatch";
export interface PersonalCorrection {
  id: string;
  canonical: string;
  variants: string[];
  scope: string | null;
  enabled: boolean;
  /** Short explanation for the minutes AI (max 200 characters). Absent in version 1 files. */
  note?: string;
  /** Spellings matched automatically from context. Unlike `variants` they are never replaced
   * blindly: they go along as known candidates and pass the context check per recording. */
  learned?: string[];
}
/** Variants plus learned spellings, trimmed and non-empty: what the minutes AI may have heard. */
export const heardAs = (entry: PersonalCorrection): string[] =>
  [...entry.variants, ...(entry.learned ?? []).filter(l => isMisspelling(l, entry.canonical))].map(v => v.trim()).filter(Boolean);
/**
 * Whether `heard` can be a misheard form of `canonical` (DEC-076). Not when it holds the term as a
 * whole word ("de Prospectflow"), for an acronym not when the letter count differs ("API" for "AI"),
 * and for a term of several words not when it keeps a word and swaps another for an unlike one
 * ("de antwoorden" for "AI Antwoorden"; "Sanne Backer" for "Sanne Bakker" stays).
 */
export function isMisspelling(heard: string, canonical: string): boolean {
  const words = (text: string) => text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  const term = canonical.trim();
  if (` ${words(heard)} `.includes(` ${words(term)} `)) return false;
  const heardWords = words(heard).split(" "), termWords = words(term).split(" ");
  if (termWords.length > 1 && heardWords.length === termWords.length && heardWords.some((w, i) => w === termWords[i])
    && heardWords.some((w, i) => w !== termWords[i] && similarity(w, termWords[i]) < 0.5)) return false;
  return !/^[A-Z]{2,4}$/.test(term) || words(heard).replace(/ /g, "").length === term.length;
}
/** Dismissed key for a learned spelling, so automatic matching does not learn it again. Same as macOS. */
export const learnedKey = (canonical: string, heard: string) => `learned:${canonical.trim().toLowerCase()}:${heard.trim().toLowerCase()}`;
export interface CorrectionDocument {
  version: 1 | 2;
  entries: PersonalCorrection[];
  /** Suggestions the user rejected, so they are not offered again. */
  dismissed?: string[];
}
/** A directory person as seen by the minutes AI. */
export interface PersonContext { name: string; role: string; organization: string; responsibilities: string[]; aliases: string[] }

/** Same budget as macOS for every provider except Apple Intelligence, which Windows lacks. */
export const CONTEXT_BUDGET = 6000;

export const validTerm = (text: unknown): text is string =>
  typeof text === "string" && !!text.trim() && text.length <= 120 && !/[\r\n<>]/.test(text);

export function validateCorrections(document: CorrectionDocument): void {
  if ((document.version !== 1 && document.version !== 2) || !Array.isArray(document.entries)) throw Error("Onbekend woordenlijstformaat.");
  const ids = new Set<string>();
  for (const entry of document.entries) {
    if (!entry.id || ids.has(entry.id) || !validTerm(entry.canonical)
      || typeof entry.enabled !== "boolean" || !(entry.scope === null || typeof entry.scope === "string" && !!entry.scope)
      || !Array.isArray(entry.variants)
      || !(entry.note == null || typeof entry.note === "string" && entry.note.length <= 200 && !/[\r\n<>]/.test(entry.note))) {
      throw Error("Vul een correcte term in (maximaal 120 tekens) en houd de toelichting onder 200 tekens, zonder regeleinden of haakjes.");
    }
    ids.add(entry.id);
    const seen = new Set<string>();
    for (const variant of entry.variants) {
      if (!validTerm(variant)) throw Error("Ongeldige variant.");
      const key = variant.trim().toLowerCase();
      if (seen.has(key) || key === entry.canonical.trim().toLowerCase()) throw Error("Een variant moet afwijken van de correcte term en mag niet dubbel voorkomen.");
      seen.add(key);
      for (const other of document.entries) {
        if (other.id === entry.id || !other.enabled || !entry.enabled) continue;
        if ((entry.scope === null || other.scope === null || entry.scope === other.scope) && other.variants.some(v => typeof v === "string" && v.trim().toLowerCase() === key)) throw Error("Deze variant heeft al een regel binnen dit bereik.");
      }
    }
    if (!(entry.learned === undefined || Array.isArray(entry.learned) && entry.learned.every(validTerm))) throw Error("Ongeldige geleerde spelling.");
  }
}
export function upsertCorrection(entries: PersonalCorrection[], entry: PersonalCorrection): PersonalCorrection[] {
  const previous = entries.find(e => e.id !== entry.id && e.scope === entry.scope && e.canonical.toLowerCase() === entry.canonical.toLowerCase());
  const variants = new Map([...(previous?.variants ?? []), ...entry.variants].map(v => [v.trim().toLowerCase(),v.trim()]));
  // A learned spelling that is also a fixed variant is redundant.
  const learned = new Map([...(previous?.learned ?? []), ...(entry.learned ?? [])].map(v => [v.trim().toLowerCase(),v.trim()] as const).filter(([key]) => !variants.has(key)));
  const { learned: _old, ...rest } = entry;
  return [...entries.filter(e => e.id !== entry.id && e.id !== previous?.id), {...rest, id:previous?.id ?? entry.id, variants:[...variants.values()], ...(learned.size ? { learned: [...learned.values()] } : {})}];
}
/**
 * Enabled entries for `profileId`. Entries are appended on upsert, so on a contradiction the last
 * one wins: an older variant that a newer entry names as the correct term is ignored, and an older
 * entry that says the reverse of a newer one ("A-E" for "AI" after "AI" for "A-E") is left out.
 */
export function activeCorrections(entries: PersonalCorrection[], profileId?: string): PersonalCorrection[] {
  const key = (text: string) => spellingKey(text.trim());
  const correct = new Set<string>(), wrong = new Set<string>(), kept: PersonalCorrection[] = [];
  for (const entry of [...entries].reverse()) {
    if (!entry.enabled || !(entry.scope === null || entry.scope === profileId)) continue;
    const variants = entry.variants.filter(v => !correct.has(key(v)));
    if (variants.length !== entry.variants.length && wrong.has(key(entry.canonical))) continue;
    correct.add(key(entry.canonical));
    variants.forEach(v => wrong.add(key(v)));
    kept.push({ ...entry, variants });
  }
  return kept.reverse();
}
const escapeRegex = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const escapeHTML = (text: string) => text.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");

const spellingKey = (text: string) => text.toLowerCase().replace(/[‐‑‒–—−]/g, "-");

export function correctText(text: string, entries: PersonalCorrection[], profileId?: string, html = false): string {
  const replacements = new Map(activeCorrections(entries, profileId).flatMap(e => e.variants.map(v => [spellingKey(v.trim()), e.canonical.trim()] as const)));
  if (!replacements.size) return text;
  const alternatives = [...replacements.keys()].sort((a,b) => b.length-a.length).map(v => escapeRegex(v).replace(/-/g, "[-‐‑‒–—−]")).join("|");
  // Protected tokens win before word alternatives, so replacements never cascade.
  const entity = "&(?:#\\d+|#x[\\da-f]+|[a-z]+);";
  const word = `(?<![\\p{L}\\p{N}_])(?:${alternatives})(?![\\p{L}\\p{N}_])`;
  const pattern = new RegExp(`${entity}|(?:https?:\\/\\/|www\\.)[^\\s<>]+|[\\p{L}\\p{N}._%+-]+@[\\p{L}\\p{N}.-]+\\.[\\p{L}]{2,}|\\x60[^\\x60]*\\x60|${word}`,"giu");
  const inner = new RegExp(`${entity}|${word}`,"giu");
  const output = (canonical: string) => html ? escapeHTML(canonical) : canonical;
  return text.replace(pattern, match => {
    if (/^[&`]/.test(match)) return match;
    const canonical = replacements.get(spellingKey(match));
    if (canonical !== undefined) return output(canonical);
    // An e-mail address or URL: variants inside it become the term in lowercase (DEC-075).
    return match.replace(inner, part => {
      const term = replacements.get(spellingKey(part));
      return term === undefined || /\s/.test(term) ? part : output(term.toLowerCase());
    });
  });
}
export function correctHTML(html: string, entries: PersonalCorrection[], profileId?: string): string {
  // Preserve source markup exactly, including head styles and attribute quoting.
  const tokens = html.split(/(<!--[\s\S]*?-->|<\/?[A-Za-z!](?:"[^"]*"|'[^']*'|[^'">])*>)/g);
  const stack: string[] = [];
  return tokens.map(token => {
    if (token.startsWith("<")) {
      const tag = /^<\s*(\/?)\s*(script|style|code|pre|a)\b/i.exec(token);
      if (tag) {
        const name = tag[2].toLowerCase();
        if (tag[1]) { if (stack[stack.length - 1] === name) stack.pop(); }
        else if (!stack.length && !token.endsWith("/>")) stack.push(name);
      }
      return token;
    }
    return stack.length ? token : correctText(token, entries, profileId, true);
  }).join("");
}
/** Applies one correction to a recording's notule and transcript. */
export function correctRecording(entry: PersonalCorrection, notule: string, transcript?: string, title = ""): { notule: string; transcript?: string; title: string } {
  const profileId = entry.scope ?? undefined;
  return { notule: correctHTML(notule, [entry], profileId), transcript: transcript === undefined ? undefined : correctText(transcript, [entry], profileId), title: correctText(title, [entry], profileId) };
}
/**
 * Correction that writes `name` over the heard spellings of a person. Skips empty spellings,
 * the name itself and spellings that are part of the name ("Sanne" for "Sanne Bakker").
 * Null when no spelling is left.
 */
export function personCorrection(name: string, heardAs: string[], scope: string | null): PersonalCorrection | null {
  const canonical = name.trim();
  const seen = new Set<string>();
  const variants = heardAs.map(h => h.trim()).filter(h => {
    if (!h || containsWord(h, canonical) || seen.has(h.toLowerCase())) return false;
    seen.add(h.toLowerCase());
    return true;
  });
  return validTerm(canonical) && variants.length ? { id: crypto.randomUUID(), canonical, variants, scope, enabled: true } : null;
}
/** Case-insensitive whole-word match, same boundaries as correctText(). */
export function containsWord(word: string, text: string): boolean {
  return new RegExp(`(?<![\\p{L}\\p{N}_])${escapeRegex(word)}(?![\\p{L}\\p{N}_])`, "iu").test(text);
}

/**
 * Glossary and people block for the minutes AI. `maxCharacters` limits the lines, not the fixed header.
 * Order: lines matching the transcript, then lines for `profileId`, then the newest. Port of the macOS
 * PersonalCorrections.contextBlock; the output must stay identical.
 */
export function contextBlock(entries: PersonalCorrection[], people: PersonContext[], transcript: string, profileId: string | undefined, maxCharacters: number, extraTerms: string[] = [], includeRoles = false): string {
  const clean = (items: string[]) => items.map(item => item.trim()).filter(Boolean);
  const found = (names: string[]) => clean(names).some(name => containsWord(name, transcript));
  const candidates: { line: string; rank: number }[] = [];
  // Entries are appended on upsert, so the last one is the newest.
  for (const entry of [...activeCorrections(entries, profileId)].reverse()) {
    const variants = heardAs(entry);
    let line = "- " + entry.canonical.trim();
    if (variants.length) line += ` (ook gehoord als: ${variants.join(", ")})`;
    const note = entry.note?.trim();
    if (note) line += ": " + note;
    candidates.push({ line, rank: found([entry.canonical, ...variants]) ? 0 : profileId !== undefined && entry.scope === profileId ? 1 : 2 });
  }
  for (const person of people) {
    let line = "- " + person.name;
    // Role and organization only for the suggestion step: models copied them into the notule.
    const detail = (includeRoles ? clean([person.role, person.organization]) : clean(person.aliases)).join(", ");
    if (detail) line += includeRoles ? ` (${detail})` : ` (ook gehoord als: ${detail})`;
    const tasks = clean(person.responsibilities);
    if (tasks.length) line += ", taken: " + tasks.join("; ");
    candidates.push({ line, rank: found([person.name, ...person.aliases]) ? 0 : 2 });
  }
  // Extra terms go last, skipping anything already covered.
  const covered = new Set<string>();
  for (const entry of activeCorrections(entries, profileId)) {
    covered.add(entry.canonical.toLowerCase());
    heardAs(entry).forEach(v => covered.add(v.toLowerCase()));
  }
  people.forEach(person => covered.add(person.name.trim().toLowerCase()));
  for (const term of clean(extraTerms)) {
    if (covered.has(term.toLowerCase())) continue;
    covered.add(term.toLowerCase());
    candidates.push({ line: "- " + term, rank: 3 });
  }
  // Array.prototype.sort is stable, so equal ranks keep their order.
  const lines: string[] = [];
  let used = 0;
  for (const { line } of [...candidates].sort((a, b) => a.rank - b.rank)) {
    const length = Array.from(line).length;
    if (used + length + 1 > maxCharacters) continue;
    lines.push(line);
    used += length + 1;
  }
  if (!lines.length) return "";
  return "\n\nWoordenboek en personen (juiste spelling en betekenis; corrigeer verkeerd herkende varianten stil, voeg geen feiten toe; noem een functie of organisatie alleen als het transcript die noemt; koppel een actie alleen aan een persoon die het transcript noemt):\n" + lines.join("\n");
}
