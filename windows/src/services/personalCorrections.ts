export interface PersonalCorrection {
  id: string;
  canonical: string;
  variants: string[];
  scope: string | null;
  enabled: boolean;
  /** Short explanation for the minutes AI (max 200 characters). Absent in version 1 files. */
  note?: string;
}
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
  }
}
export function upsertCorrection(entries: PersonalCorrection[], entry: PersonalCorrection): PersonalCorrection[] {
  const previous = entries.find(e => e.id !== entry.id && e.scope === entry.scope && e.canonical.toLowerCase() === entry.canonical.toLowerCase());
  const variants = new Map([...(previous?.variants ?? []), ...entry.variants].map(v => [v.trim().toLowerCase(),v.trim()]));
  return [...entries.filter(e => e.id !== entry.id && e.id !== previous?.id), {...entry, id:previous?.id ?? entry.id, variants:[...variants.values()]}];
}
export function activeCorrections(entries: PersonalCorrection[], profileId?: string): PersonalCorrection[] {
  return entries.filter(e => e.enabled && (e.scope === null || e.scope === profileId));
}
const escapeRegex = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const escapeHTML = (text: string) => text.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");

export function correctText(text: string, entries: PersonalCorrection[], profileId?: string, html = false): string {
  const replacements = new Map(activeCorrections(entries, profileId).flatMap(e => e.variants.map(v => [v.trim().toLowerCase(), e.canonical.trim()] as const)));
  if (!replacements.size) return text;
  const alternatives = [...replacements.keys()].sort((a,b) => b.length-a.length).map(escapeRegex).join("|");
  // Protected tokens win before word alternatives, so replacements never cascade.
  const pattern = new RegExp(`&(?:#\\d+|#x[\\da-f]+|[a-z]+);|(?:https?:\\/\\/|www\\.)[^\\s<>]+|[\\p{L}\\p{N}._%+-]+@[\\p{L}\\p{N}.-]+\\.[\\p{L}]{2,}|\\x60[^\\x60]*\\x60|(?<![\\p{L}\\p{N}_])(?:${alternatives})(?![\\p{L}\\p{N}_])`,"giu");
  return text.replace(pattern, match => {
    if (/^(?:https?:\/\/|www\.|&|`)/i.test(match) || match.includes("@")) return match;
    const canonical = replacements.get(match.toLowerCase());
    return canonical === undefined ? match : html ? escapeHTML(canonical) : canonical;
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
    const variants = clean(entry.variants);
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
    entry.variants.forEach(v => covered.add(v.trim().toLowerCase()));
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
