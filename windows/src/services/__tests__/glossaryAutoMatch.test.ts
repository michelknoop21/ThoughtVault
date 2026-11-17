import { expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { applyAnswers, autoMatch, findCandidates, matchTargets, parseAnswers, soundKey, matchPrompt } from "../glossaryAutoMatch";
import { correctRecording, type PersonalCorrection } from "../personalCorrections";

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
    expect(candidates.every(x => x.sentence.includes(`⟦${x.heard}⟧`)), c.name).toBe(true);
    if (c.name === "same sentence, different meanings") expect(new Set(candidates.map(x => x.sentence)).size).toBe(2);
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
  expect(candidates).toHaveLength(40);
  expect(matchPrompt(candidates).count).toBeLessThanOrEqual(12);
  expect(candidates.every(c => Array.from(c.sentence).length <= 160 && c.sentence.includes(c.heard))).toBe(true);
});

it("checks every occurrence in bounded batches, including different meanings", async () => {
  const transcript = Array(30).fill("AE modellen.").join(" ") + " AE is een andere afkorting.";
  const targets = matchTargets([{ id: "ai", canonical: "AI", variants: [], scope: null, enabled: true }], []);
  let calls = 0;
  const result = await autoMatch(transcript, targets, [], async (_, user) => {
    calls++;
    const lines = user.split("\n");
    expect(lines.length).toBeLessThanOrEqual(12);
    return lines.map((line, i) => `${i + 1} ${line.includes("andere afkorting") ? "nee" : "ja"}`).join("\n");
  });
  expect(calls).toBeGreaterThan(1);
  expect(result.text).toBe(Array(30).fill("AI modellen.").join(" ") + " AE is een andere afkorting.");
  expect(result.learned).toEqual([]);
});

it("corrects title, all paragraphs and transcript using shared recording cases", () => {
  const { recordings } = JSON.parse(readFileSync(`${process.cwd()}/../tests/fixtures/glossary-automatch.json`, "utf8"));
  for (const c of recordings) {
    const entry: PersonalCorrection = { id: "ai", canonical: "AI", variants: ["A-E"], scope: null, enabled: true };
    expect(correctRecording(entry, c.notule, c.transcript, c.title)).toEqual({ title: c.expectedTitle, notule: c.expectedNotule, transcript: c.expectedTranscript });
    expect(correctRecording({ ...entry, enabled: false }, c.notule, c.transcript, c.title).title).toBe(c.title);
  }
});

it("finds separated letters in abbreviations of four letters", () => {
  const targets = matchTargets([{ id: "api", canonical: "ABCD", variants: [], scope: null, enabled: true }], []);
  expect(findCandidates("A B C D modules. A–B–C–E systemen.", targets, []).map(c => c.heard)).toEqual(["A B C D", "A–B–C–E"]);
});
