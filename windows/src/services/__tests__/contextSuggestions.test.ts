// Parsing and storage of the term and people suggestions made after a notule.
import { expect, it, vi } from "vitest";
vi.mock("@tauri-apps/api/core", async () => (await import("./fakeAppData")).tauriCore);
import { files } from "./fakeAppData";
import { dismissKey, parse, type PersonSuggestion, type TermSuggestion } from "../contextSuggestions";
import type { PersonalCorrection } from "../personalCorrections";

const transcript = "We bespraken het dossier met Pieter van Kaskop. De schade aan het dak is groot.";

it("parseStripsFencesAndLeadingText", () => {
  const raw = 'Hier is het:\n```json\n{"terms": [{"heard": "Kaskop", "canonical": "Kascop", "note": "Expertisebureau"}]}\n```';
  const set = parse(raw, transcript, [], []);
  expect(set.terms).toEqual([{ heard: "Kaskop", canonical: "Kascop", note: "Expertisebureau" }]);
  expect(set.people).toEqual([]);
});

it("parseInvalidJSONReturnsEmpty", () => {
  expect(parse('{"terms": [ {', transcript, [], [])).toEqual({ terms: [], people: [] });
  expect(parse("geen json", transcript, [], [])).toEqual({ terms: [], people: [] });
});

it("parseDropsTermWhoseHeardTextIsNotInTranscript", () => {
  const raw = '{"terms": [{"heard": "Kas", "canonical": "Kascop"}, {"heard": "Gamma", "canonical": "Gama"}, {"heard": "kaskop", "canonical": "Kascop"}]}';
  const set = parse(raw, transcript, [], []);
  expect(set.terms.map(t => t.heard)).toEqual(["kaskop"]);
  expect(set.terms[0].note).toBe("");
});

it("parseDropsAlreadyKnownAndDismissed", () => {
  const raw = `{"terms": [
    {"heard": "dak", "canonical": "Dakwerk BV"},
    {"heard": "schade", "canonical": "Schade"},
    {"heard": "dossier", "canonical": "Dossier-X"},
    {"heard": "Kaskop", "canonical": "Kascop", "note": "regel1\\nregel2 <b>${"x".repeat(300)}"}
  ],
  "people": [
    {"name": "Pieter van Kaskop", "role": " schade-expert ", "matchedPersonId": "verzonnen"},
    {"name": "Anke Bakker"},
    {"name": "  "}
  ]}`;
  const entries: PersonalCorrection[] = [{ id: "a", canonical: "dakwerk bv", variants: ["dakwerk"], scope: null, enabled: true }];
  const dismissed = [dismissKey({ term: { heard: "Dossier", canonical: "dossier-x", note: "" } }), "person:anke bakker"];
  const set = parse(raw, transcript, entries, dismissed);
  expect(set.terms.map(t => t.canonical)).toEqual(["Kascop"]);
  const note = set.terms[0].note;
  expect(note.length).toBeLessThanOrEqual(200);
  expect(/[\r\n<>]/.test(note)).toBe(false);
  expect(set.people.map(p => p.name)).toEqual(["Pieter van Kaskop"]);
  expect(set.people[0].role).toBe("schade-expert");
  expect(set.people[0].matchedPersonId).toBeUndefined();
  expect(dismissKey({ term: { heard: "Kaskop", canonical: "Kascop", note: "" } })).toBe("term:kaskop→kascop");
});

it("parseCapsAtEightTermsAndEightPeople", () => {
  const words = Array.from({ length: 12 }, (_, i) => `woord${i}`);
  const terms = words.map(w => `{"heard": "${w}", "canonical": "Term${w}"}`).join(",");
  const people = words.map((_, i) => `{"name": "Persoon ${i}"}`).join(",");
  const set = parse(`{"terms": [${terms}], "people": [${people}]}`, words.join(" "), [], []);
  expect(set.terms.length).toBe(8);
  expect(set.people.length).toBe(8);
});

it("parseSplitsSlashSeparatedSpellings", () => {
  const raw = '{"terms": [{"heard": "Kaskop / Kazkop / dossier", "canonical": "Kascop", "note": "Bureau"}]}';
  expect(parse(raw, transcript, [], []).terms).toEqual([
    { heard: "Kaskop", canonical: "Kascop", note: "Bureau" },
    { heard: "dossier", canonical: "Kascop", note: "Bureau" },
  ]);
});

it("parseDropsUnnamedPeopleAndTheUser", () => {
  const raw = '{"people": [{"name": ""}, {"name": "michel knoop"}, {"name": "M. Knoop"}, {"name": "Peter", "heardAs": ["Michel Knoop"]}, {"name": "Mike de Boer", "heardAs": ["Mike"]}, {"name": "Pieter van Kaskop"}]}';
  const set = parse(raw, transcript, [], [], ["Michel Knoop"], ["M. Knoop", "Mike"]);
  expect(set.people.map(p => p.name)).toEqual(["Mike de Boer", "Pieter van Kaskop"]);
});

it("parseIgnoresThinkBlock", () => {
  const raw = '<think>Eerst {"terms": []} overwegen.</think>\n{"terms": [{"heard": "Kaskop", "canonical": "Kascop"}]}';
  expect(parse(raw, transcript, [], []).terms.map(t => t.canonical)).toEqual(["Kascop"]);
});

it("storeRoundTripRemoveAndDismiss", async () => {
  vi.resetModules();
  files.clear();
  const suggestions = await import("../contextSuggestions");
  const corrections = (await import("../../stores/personalCorrectionsStore")).usePersonalCorrectionsStore;
  const term: TermSuggestion = { heard: "Kaskop", canonical: "Kascop", note: "" };
  const person: PersonSuggestion = { name: "Pieter", role: "", organization: "", responsibilities: [], topics: [], heardAs: [], candidateIds: [] };
  await suggestions.save({ terms: [term], people: [person] }, "t1");
  await suggestions.save({ terms: [term], people: [] }, "t2");

  const remainder = { ...person, role: "Teamleider", matchedPersonId: "p1" };
  await suggestions.replacePerson("t1", person, remainder);
  expect((await suggestions.load("t1"))?.people).toEqual([remainder]);
  await suggestions.replacePerson("t1", remainder, person);

  await suggestions.remove("t1", { term });
  expect((await suggestions.load("t1"))?.terms).toEqual([]);
  expect((await suggestions.load("t1"))?.people).toEqual([person]);
  expect((await suggestions.load("t2"))?.terms).toEqual([term]);
  await suggestions.remove("t1", { person });
  expect(await suggestions.load("t1")).toBeUndefined();

  await corrections.getState().save({ id: "k", canonical: "Kascop", variants: ["Kaskop"], scope: null, enabled: true });
  const key = dismissKey({ person });
  await suggestions.dismiss(key);
  await suggestions.dismiss(key);
  const document = JSON.parse(files.get("personal-corrections.json")!);
  expect(document.dismissed).toEqual(["person:pieter"]);
  expect(document.entries.map((e: PersonalCorrection) => e.canonical)).toEqual(["Kascop"]);
});
