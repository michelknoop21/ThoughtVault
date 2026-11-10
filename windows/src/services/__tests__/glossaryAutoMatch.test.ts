import { expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { applyAnswers, autoMatch, findCandidates, matchTargets, parseAnswers, soundKey } from "../glossaryAutoMatch";
import type { PersonalCorrection } from "../personalCorrections";

interface Case { name: string; transcript: string; entries: PersonalCorrection[]; people: { id: string; name: string; aliases: string[] }[];
  dismissed: string[]; candidates: [string, string][]; answer: string; text: string; learned: [string, string][] }
const fixture = JSON.parse(readFileSync(`${process.cwd()}/../tests/fixtures/glossary-automatch.json`, "utf8")) as { soundKeys: [string, string][]; cases: Case[] };

it("testSoundKeys", () => {
  for (const [word, key] of fixture.soundKeys) expect(soundKey(word), word).toBe(key);
});

it("testFixture", () => {
  for (const c of fixture.cases) {
    const candidates = findCandidates(c.transcript, matchTargets(c.entries, c.people), c.dismissed);
    expect(candidates.map(x => [x.heard, x.target.canonical]), c.name).toEqual(c.candidates);
    const result = applyAnswers(c.transcript, candidates, parseAnswers(c.answer, candidates.length));
    expect(result.text, c.name).toBe(c.text);
    expect(result.learned.map(l => [l.target.canonical, l.heard]), c.name).toEqual(c.learned);
  }
});

it("testGarbageMeansNo", async () => {
  const c = fixture.cases[0];
  const targets = matchTargets(c.entries, c.people);
  expect(await autoMatch(c.transcript, targets, [], async () => "geen idee")).toEqual({ text: c.transcript, learned: [] });
  expect(await autoMatch(c.transcript, targets, [], async () => { throw new Error("offline"); })).toEqual({ text: c.transcript, learned: [] });
  expect(await autoMatch(c.transcript, targets, [], () => new Promise(() => {}), 10)).toEqual({ text: c.transcript, learned: [] });
});

it("keeps the prompt within the budget and sentences short", () => {
  const long = Array.from({ length: 40 }, (_, i) => `Zin ${i} met Jengo erin en verder heel veel woorden om de zin lang te maken tot ver voorbij de grens van honderdzestig tekens zodat inkorten nodig is.`).join(" ");
  const candidates = findCandidates(long, matchTargets([{ id: "y", canonical: "Yinga", variants: [], scope: null, enabled: true }], []), []);
  expect(candidates.length).toBeLessThanOrEqual(12);
  expect(candidates.every(c => Array.from(c.sentence).length <= 160 && c.sentence.includes(c.heard))).toBe(true);
});
