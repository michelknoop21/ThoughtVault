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
export function extractTitle(html: string): string | null {
  // Strategy 1: first descriptive heading (h1-h4)
  for (const raw of matches(/<(h[1-4])[^>]*>([\s\S]*?)<\/\1>/gi, html, 2)) {
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
