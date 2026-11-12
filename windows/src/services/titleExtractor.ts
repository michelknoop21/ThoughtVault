// Extracts a descriptive title from generated notule HTML. Port of the macOS
// NotuleTitleExtractor (itself a port of the backend `_extract_title_from_html`),
// so locally generated notulen get the same titles as the server produced.

const GENERIC_TITLES = new Set(
  [
    "notule", "notulen", "vergadering", "meeting", "gespreksverslag",
    "verslag", "samenvatting", "tl;dr", "tldr",
  ].map(normalize)
);

const SECTION_WORDS = new Set(
  [
    "gespreksverslag", "actiepunten", "samenvatting", "context",
    "conclusie", "agenda", "deelnemers", "besluitenlijst",
    "kernargumenten", "kernpunten", "key takeaways", "takeaways",
    "hoofdpunten", "besluiten", "vervolgstappen", "inleiding",
    "introductie", "achtergrond", "discussie", "toelichting",
    "analyse", "resultaten", "aanbevelingen", "bijlagen",
    "thema", "onderwerp", "overzicht", "tl;dr", "tldr",
    "belangrijkste besproken punten", "besproken punten",
    "technische beslissingen", "afspraken en vervolgstappen",
    "afspraken", "action items", "actie items", "wat nu",
    "ideeen inzichten", "ideeen en inzichten", "inhoud",
    "kernboodschap", "in het kort", "volgende stappen",
    "blokkades en techniek", "blokkades", "tech debt",
    "belangrijkste punten", "quotes", "highlights",
  ].map(normalize)
);

// A heading made only of genre words ("Verslag meeting", "Verslaggesprek") names
// the document type, not the conversation. Compounds are runs of these stems;
// a date ("10 november") adds nothing either.
const GENRE_WORD = /^(verslag|notulen?|meetings?|gespreks?|overleg|vergadering|prompts?|van|het|de|een|\d|januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december)+$/;

// lowercase, strip diacritics, strip punctuation, collapse whitespace.
function normalize(text: string): string {
  return text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function clean(input: string): string {
  let text = input;
  text = text.replace(/<[^>]+>/g, "");           // strip tags
  text = text.replace(/\[.*?\]/g, "");           // strip [bracketed]
  text = text.replace(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{27BF}]+/gu, ""); // emoji
  text = text.trim().replace(/^\d+\.\s*/, "");   // leading "1. "
  const entities: Record<string, string> = {
    "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'",
  };
  for (const [entity, char] of Object.entries(entities)) {
    text = text.split(entity).join(char);
  }
  return text.trim();
}

function isDescriptive(text: string): boolean {
  if (text.length < 6 || text.startsWith("[")) return false;
  const key = normalize(text);
  if (GENERIC_TITLES.has(key) || SECTION_WORDS.has(key)) return false;
  const words = key.split(" ").filter(Boolean);
  if (words.length <= 2 && words.some((w) => SECTION_WORDS.has(w))) return false;
  if (words.every((w) => GENRE_WORD.test(w))) return false;
  return true;
}

function firstSentence(text: string): string {
  return (text.split(/[.!?]/)[0] ?? text).trim();
}

function matches(pattern: RegExp, text: string, group: number): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(pattern)) {
    if (m[group] !== undefined) out.push(m[group]);
  }
  return out;
}

/** Returns a descriptive title from the HTML, or null if none qualifies. */
/** Heading of the source warning that notuleAudit appends last; never a title. */
export const SOURCE_WARNING_HEADING = "<h2>Even nalopen</h2>";

export function extractTitle(html: string): string | null {
  // The source warning is appended last; the title comes from the notule before it.
  const warning = html.indexOf(SOURCE_WARNING_HEADING);
  if (warning >= 0) html = html.slice(0, warning);
  // Strategy 1: first descriptive heading. When the notule has an h1, only h1 counts:
  // a rejected h1 must not promote a section heading ("Acties") to title.
  const headings = /<h1[\s>]/i.test(html) ? /<(h1)[^>]*>([\s\S]*?)<\/\1>/gi : /<(h[1-4])[^>]*>([\s\S]*?)<\/\1>/gi;
  for (const raw of matches(headings, html, 2)) {
    const title = clean(raw);
    if (isDescriptive(title)) return title.slice(0, 80);
  }

  // Strategy 2: TL;DR / summary box — the following <p>
  const tldr = matches(
    /(?:tl;?dr|samenvatting|in het kort)[^<]*<\/(?:h2|h3|strong|b|div|span)>[^<]*<p[^>]*>([\s\S]*?)<\/p>/gi,
    html,
    1
  )[0];
  if (tldr) {
    const summary = clean(tldr);
    if (summary.length > 20) {
      const sentence = firstSentence(summary);
      if (sentence.length > 10) return sentence.slice(0, 80);
    }
  }

  // Strategy 3: first substantial <p>
  for (const raw of matches(/<p[^>]*>([\s\S]*?)<\/p>/gi, html, 1)) {
    const text = clean(raw);
    if (text.length > 30 && !text.startsWith("📅")) {
      const sentence = firstSentence(text);
      if (sentence.length > 10) return sentence.slice(0, 80);
    }
  }

  return null;
}
