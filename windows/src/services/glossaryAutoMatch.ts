// Finds misheard spellings of glossary terms and directory names in a transcript, lets the
// minutes model confirm each one in context, and replaces the confirmed occurrences.
// Port of macos/Services/GlossaryAutoMatch.swift; tests/fixtures/glossary-automatch.json keeps both equal.
import { activeCorrections, learnedKey, type PersonalCorrection } from "./personalCorrections";

export interface MatchTarget {
  kind: "term" | "person";
  id: string;
  canonical: string;
  note?: string;
  /** Spellings replaced anyway (glossary variants): never a candidate. */
  fixed: string[];
  /** Known spellings (learned, person aliases): always a candidate, still checked in context. */
  known: string[];
}
export interface MatchCandidate { heard: string; start: number; end: number; sentence: string; target: MatchTarget; similarity: number }
export interface MatchResult { text: string; learned: { target: MatchTarget; heard: string }[] }

export const MAX_CANDIDATES = 12;
const MAX_PER_SPELLING = 3;
const PROMPT_BUDGET = 1500;
const SENTENCE_LIMIT = 160;

/** Lowercase without accents. */
export const fold = (text: string) => text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
const compact = (text: string) => fold(text).replace(/[^\p{L}\p{N}]/gu, "");
/** Folded words separated by one space: "Kuber netes" differs from "Kubernetes" here, not in `compact`. */
const words = (text: string) => fold(text).replace(/[^\p{L}\p{N}]+/gu, " ").trim();
/** Dutch sound-alikes made equal: ph/f, ch/g, ij/ei, ou/au, y/j, c/k, v/f, z/s, double letters. */
export function phonetic(text: string): string {
  return compact(text).replace(/ph/g, "f").replace(/ch/g, "g").replace(/ij|ei/g, "3").replace(/ou|au/g, "4")
    .replace(/y/g, "j").replace(/c/g, "k").replace(/v/g, "f").replace(/z/g, "s").replace(/(.)\1+/g, "$1");
}
/** Sound key: first sound plus the consonant skeleton of `phonetic`. */
export function soundKey(text: string): string {
  const p = phonetic(text);
  return p.slice(0, 1) + p.slice(1).replace(/[aeiou34]/g, "");
}
export function levenshtein(a: string, b: string): number {
  const x = Array.from(a), y = Array.from(b);
  let row = Array.from({ length: y.length + 1 }, (_, i) => i);
  for (let i = 1; i <= x.length; i++) {
    const next = [i];
    for (let j = 1; j <= y.length; j++) next[j] = Math.min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (x[i - 1] === y[j - 1] ? 0 : 1));
    row = next;
  }
  return row[y.length];
}
const ratio = (a: string, b: string) => { const max = Math.max(Array.from(a).length, Array.from(b).length); return max ? 1 - levenshtein(a, b) / max : 0; };
/** Best of the plain and the phonetic similarity, 0...1. */
export const similarity = (a: string, b: string) => Math.max(ratio(compact(a), compact(b)), ratio(phonetic(a), phonetic(b)));

/** Glossary terms of `profileId` and directory people, as match targets. */
export function matchTargets(entries: PersonalCorrection[], people: { id: string; name: string; aliases: string[] }[], profileId?: string): MatchTarget[] {
  return [
    ...activeCorrections(entries, profileId).map((e): MatchTarget => ({ kind: "term", id: e.id, canonical: e.canonical.trim(), note: e.note, fixed: e.variants, known: e.learned ?? [] })),
    // A partial name ("Michel" for "Michel Knoop") stays context only: replacing it would change every mention.
    ...people.map((p): MatchTarget => {
      const nameWords = new Set(fold(p.name).split(/\s+/));
      return { kind: "person", id: p.id, canonical: p.name.trim(), fixed: [], known: p.aliases.filter(a => !fold(a).split(/\s+/).every(w => nameWords.has(w))) };
    }),
  ].filter(t => t.canonical);
}

function sentenceAround(text: string, start: number, end: number): string {
  const before = text.slice(0, start).search(/[^.!?\n]*$/);
  const after = text.slice(end).search(/[.!?\n]/);
  const sentence = text.slice(before, after < 0 ? text.length : end + after + 1).trim();
  if (sentence.length <= SENTENCE_LIMIT) return sentence;
  const offset = start - before - Math.max(0, text.slice(before, start).length - text.slice(before, start).trimStart().length);
  const from = Math.max(0, Math.min(offset - SENTENCE_LIMIT / 2, sentence.length - SENTENCE_LIMIT));
  return sentence.slice(from, from + SENTENCE_LIMIT).trim();
}

/** Candidate occurrences, best first, without LLM. */
export function findCandidates(transcript: string, targets: MatchTarget[], dismissed: string[]): MatchCandidate[] {
  const spans = [...transcript.matchAll(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu)].map(m => ({ start: m.index!, end: m.index! + m[0].length }));
  // N-grams of 1 to 3 words, normalized once for all targets.
  const grams = [1, 2, 3].map(n => spans.slice(0, Math.max(0, spans.length - n + 1)).map((span, i) => {
    const start = span.start, end = spans[i + n - 1].end, heard = transcript.slice(start, end);
    return { start, end, heard, plain: compact(heard), spaced: words(heard) };
  }));
  const correct = new Set(targets.map(t => words(t.canonical)));
  const skip = new Set(dismissed);
  const found: MatchCandidate[] = [];
  // Unique n-gram text per target is scored once.
  const scores = new Map<string, number>();
  for (const target of targets) {
    const size = target.canonical.split(/\s+/).length;
    const fixed = new Set(target.fixed.map(words));
    const known = new Set(target.known.map(words));
    const key = soundKey(target.canonical);
    const length = compact(target.canonical).length;
    for (let n = Math.max(1, size - 1); n <= Math.min(3, size + 1); n++) {
      for (const { start, end, heard, plain, spaced } of grams[n - 1]) {
        if (plain.length < 4 || correct.has(spaced) || fixed.has(spaced) || skip.has(learnedKey(target.canonical, heard))) continue;
        const cacheKey = target.id + "\u0000" + spaced;
        let score = scores.get(cacheKey);
        if (score === undefined) {
          score = known.has(spaced) ? 1
            : Math.abs(plain.length - length) / Math.max(plain.length, length) > 0.5 ? 0
            : (() => { const s = similarity(heard, target.canonical); return s >= 0.75 || (s >= 0.5 && soundKey(heard) === key) ? s : 0; })();
          scores.set(cacheKey, score);
        }
        if (score > 0) found.push({ heard, start, end, sentence: "", target, similarity: score });
      }
    }
  }
  // Best first; a span is one thing, and one frequent spelling may not take every slot.
  found.sort((a, b) => b.similarity - a.similarity || a.start - b.start);
  const chosen: MatchCandidate[] = [];
  const perSpelling = new Map<string, number>();
  for (const candidate of found) {
    if (chosen.length >= MAX_CANDIDATES) break;
    const spelling = candidate.target.id + "\u0000" + words(candidate.heard);
    if ((perSpelling.get(spelling) ?? 0) >= MAX_PER_SPELLING) continue;
    if (chosen.some(c => candidate.start < c.end && c.start < candidate.end)) continue;
    perSpelling.set(spelling, (perSpelling.get(spelling) ?? 0) + 1);
    chosen.push({ ...candidate, sentence: sentenceAround(transcript, candidate.start, candidate.end) });
  }
  return chosen.sort((a, b) => a.start - b.start);
}

export const MATCH_SYSTEM = "Je controleert een spraaktranscriptie. Elke regel noemt een gehoord woord, de zin waarin het staat en een bekende naam of term. Beoordeel per regel of het gehoorde woord in die zin een verkeerd verstane vorm van die naam of term is. Antwoord alleen met het nummer en ja of nee, één regel per nummer, bijvoorbeeld: 1 ja";

/** One line per candidate; trailing candidates are dropped to stay within the prompt budget. */
export function matchPrompt(candidates: MatchCandidate[]): { user: string; count: number } {
  const lines: string[] = [];
  let used = MATCH_SYSTEM.length;
  for (const [index, c] of candidates.entries()) {
    const note = c.target.note?.trim().slice(0, 80);
    const line = `${index + 1}. "${c.heard}" in: ${c.sentence} | bedoeld: ${c.target.canonical}${note ? ` (${note})` : ""}`;
    if (used + line.length + 1 > PROMPT_BUDGET) break;
    lines.push(line); used += line.length + 1;
  }
  return { user: lines.join("\n"), count: lines.length };
}

/** Numbers answered "ja"; anything unreadable or contradictory counts as no. */
export function parseAnswers(answer: string, count: number): Set<number> {
  const yes = new Set<number>(), no = new Set<number>();
  for (const line of answer.split(/\r?\n/)) {
    const match = /^\s*(\d+)\s*[.):-]?\s*(ja|nee)\b/i.exec(line);
    if (!match) continue;
    const n = Number(match[1]);
    if (n >= 1 && n <= count) (match[2].toLowerCase() === "ja" ? yes : no).add(n);
  }
  return new Set([...yes].filter(n => !no.has(n)));
}

/** Replaces the confirmed occurrences; a spelling is learned only when none of its occurrences got no. */
export function applyAnswers(transcript: string, candidates: MatchCandidate[], yes: Set<number>): MatchResult {
  let text = transcript;
  for (const [index, c] of [...candidates.entries()].reverse()) {
    if (yes.has(index + 1)) text = text.slice(0, c.start) + c.target.canonical + text.slice(c.end);
  }
  const verdicts = new Map<string, { target: MatchTarget; heard: string; yes: boolean; no: boolean }>();
  candidates.forEach((c, index) => {
    const key = c.target.id + "\u0000" + words(c.heard);
    const verdict = verdicts.get(key) ?? { target: c.target, heard: c.heard, yes: false, no: false };
    if (yes.has(index + 1)) verdict.yes = true; else verdict.no = true;
    verdicts.set(key, verdict);
  });
  const learned = [...verdicts.values()]
    .filter(v => v.yes && !v.no && !v.target.known.some(k => words(k) === words(v.heard)))
    .map(({ target, heard }) => ({ target, heard }));
  return { text, learned };
}

/**
 * Whole step: candidates, one model call, replacements. Any failure, a timeout or no candidates
 * leave the transcript unchanged, so the minutes continue as before.
 */
export async function autoMatch(transcript: string, targets: MatchTarget[], dismissed: string[],
  complete: (system: string, user: string) => Promise<string>, timeoutMs = 20_000): Promise<MatchResult> {
  const unchanged = { text: transcript, learned: [] };
  const all = findCandidates(transcript, targets, dismissed);
  const { user, count } = matchPrompt(all);
  if (!count) return unchanged;
  const candidates = all.slice(0, count);
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const answer = await Promise.race([
      complete(MATCH_SYSTEM, user),
      new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("time-out")), timeoutMs); }),
    ]);
    return applyAnswers(transcript, candidates, parseAnswers(answer, count));
  } catch (error) {
    console.warn("[GlossaryAutoMatch] Overgeslagen:", error instanceof Error ? error.message : String(error));
    return unchanged;
  } finally {
    clearTimeout(timer);
  }
}
