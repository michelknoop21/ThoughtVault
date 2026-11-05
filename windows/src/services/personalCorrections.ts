export interface PersonalCorrection {
  id: string;
  canonical: string;
  variants: string[];
  scope: string | null;
  enabled: boolean;
}
export interface CorrectionDocument { version: 1; entries: PersonalCorrection[] }

export function validateCorrections(document: CorrectionDocument): void {
  if (document.version !== 1 || !Array.isArray(document.entries)) throw Error("Onbekend woordenlijstformaat.");
  const ids = new Set<string>();
  for (const entry of document.entries) {
    if (!entry.id || ids.has(entry.id) || typeof entry.canonical !== "string" || !entry.canonical.trim() || entry.canonical.length > 120 || /[\r\n<>]/.test(entry.canonical)
      || typeof entry.enabled !== "boolean" || !(entry.scope === null || typeof entry.scope === "string" && !!entry.scope)
      || !Array.isArray(entry.variants) || !entry.variants.length) throw Error("Vul een correcte term en minstens één variant in (maximaal 120 tekens).");
    ids.add(entry.id);
    const seen = new Set<string>();
    for (const variant of entry.variants) {
      if (typeof variant !== "string" || !variant.trim() || variant.length > 120 || /[\r\n<>]/.test(variant)) throw Error("Ongeldige variant.");
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
export function correctionPrompt(entries: PersonalCorrection[], profileId?: string): string {
  const rules = activeCorrections(entries, profileId).slice(0,30);
  return rules.length ? "\n\nGoedgekeurde spellingcorrecties (geen nieuwe feiten):\n" + rules.map(e => `${e.variants.join(", ")} -> ${e.canonical}`).join("\n") : "";
}
