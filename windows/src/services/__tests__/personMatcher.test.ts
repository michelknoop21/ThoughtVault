// Linking people from a conversation to the directory and filling in their profiles.
import { expect, it, vi } from "vitest";
vi.mock("@tauri-apps/api/core", async () => (await import("./fakeAppData")).tauriCore);
import { files } from "./fakeAppData";
import { candidates, match } from "../personMatcher";
import type { PersonSuggestion } from "../contextSuggestions";
import type { PersonProfile } from "../../types";

const suggestion = (name: string, extra: Partial<PersonSuggestion> = {}): PersonSuggestion =>
  ({ name, role: "", organization: "", responsibilities: [], topics: [], heardAs: [], candidateIds: [], ...extra });

const profile = (name: string, extra: Partial<PersonProfile> = {}): PersonProfile => ({
  id: crypto.randomUUID(), name, role: "", organization: "", aliases: [], meetingTypes: [], expertiseTags: [],
  responsibilities: [], emails: [], isSelf: false, isInternal: null, createdAt: "", updatedAt: "", ...extra,
});

async function fresh(people: PersonProfile[]) {
  vi.resetModules();
  files.clear();
  const store = (await import("../../stores/peopleDirectoryStore")).usePeopleDirectoryStore;
  store.setState({ people });
  return { store, matcher: await import("../personMatcher"), history: await import("../contextHistory") };
}
const person = (store: Awaited<ReturnType<typeof fresh>>["store"], id: string) => store.getState().people.find(p => p.id === id)!;

// MARK: match

it("exactNameMatches", () => {
  const anke = profile("Anke Bakker");
  const people = candidates([anke, profile("Jan Smit")]);
  expect(match(suggestion("anke bakker"), people)).toEqual({ kind: "existing", id: anke.id });
  expect(match(suggestion("Kees"), people)).toEqual({ kind: "new" });
  expect(match(suggestion(" Ánke  Bakker "), people)).toEqual({ kind: "existing", id: anke.id });
});

it("oneWordHeardAsNeverFallsBackToFirstName", () => {
  const people = candidates([profile("Pieter Jansen")]);
  expect(match(suggestion("Pieter van Kaskop", { heardAs: ["Pieter"] }), people)).toEqual({ kind: "new" });
});

it("oneWordHeardAsDoesNotMatchAliasExactly", () => {
  const people = candidates([profile("Anke Bakker", { aliases: ["Anke"] })]);
  expect(match(suggestion("Anke de Boer", { heardAs: ["Anke"] }), people)).toEqual({ kind: "new" });
});

it("aliasMatches", () => {
  const anke = profile("Anke Bakker", { aliases: ["Anke B."] });
  const people = candidates([anke]);
  expect(match(suggestion("A. Bakker", { heardAs: ["anke b."] }), people)).toEqual({ kind: "existing", id: anke.id });
  expect(match(suggestion("Anke B."), people)).toEqual({ kind: "existing", id: anke.id });
});

it("ambiguousFirstNameIsNotAutoLinked", () => {
  const devries = profile("Jan de Vries"), smit = profile("Jan Smit"), anke = profile("Anke Bakker");
  const people = candidates([devries, smit, anke]);
  expect(match(suggestion("Jan"), people)).toEqual({ kind: "ambiguous", ids: [devries.id, smit.id] });
  expect(match(suggestion("Anke"), people)).toEqual({ kind: "existing", id: anke.id });
});

it("selfProfileIsIgnored", () => {
  expect(match(suggestion("Michel Knoop"), candidates([profile("Michel Knoop", { isSelf: true })]))).toEqual({ kind: "new" });
});

// MARK: autoApply

it("autoApplyAddsResponsibilitiesWithoutDuplicates", async () => {
  const anke = profile("Anke Bakker", { expertiseTags: ["Dakschade"], responsibilities: ["rapport opstellen"] });
  const { store, matcher } = await fresh([anke]);
  const rest = await matcher.autoApply(
    suggestion("Anke Bakker", { responsibilities: ["Rapport opstellen", "Offerte sturen"], topics: ["dakschade", "Vochtmeting"] }),
    anke.id, "Schade-expertise", "T1");
  expect(rest).toBeNull();
  expect(person(store, anke.id).responsibilities).toEqual(["rapport opstellen", "Offerte sturen"]);
  expect(person(store, anke.id).expertiseTags).toEqual(["Dakschade", "Vochtmeting"]);
  expect(person(store, anke.id).meetingTypes).toEqual(["Schade-expertise"]);
});

it("autoApplyNeverOverwritesRoleButReturnsProposal", async () => {
  const anke = profile("Anke Bakker", { role: "Projectleider", aliases: ["Anke B."] });
  const { store, matcher } = await fresh([anke]);
  const rest = (await matcher.autoApply(
    suggestion("Anke Bakker", { role: "Directeur", organization: "Kascop", heardAs: ["Anke B.", "Anke Bakkers"] }),
    anke.id, "", "T1"))!;
  expect(person(store, anke.id).role).toBe("Projectleider");
  expect(person(store, anke.id).organization).toBe("");
  expect(rest.role).toBe("Directeur");
  expect(rest.organization).toBe("Kascop");
  expect(rest.heardAs).toEqual(["Anke Bakkers"]);
  expect(rest.matchedPersonId).toBe(anke.id);
});

it("autoApplyRecordsHistoryEntry", async () => {
  const anke = profile("Anke Bakker");
  const { matcher, history } = await fresh([anke]);
  await matcher.autoApply(suggestion("Anke Bakker", { topics: ["Dakschade"] }), anke.id, "Overleg", "T1");
  expect((await history.versions("person", anke.id)).map(v => v.source)).toEqual(["gesprek:T1"]);
});

it("autoApplyProposesOnlyMultiWordNameAsAlias", async () => {
  const anke = profile("Anke Bakker");
  const { matcher } = await fresh([anke]);
  expect((await matcher.autoApply(suggestion("A. Bakker"), anke.id, "", "T1"))?.heardAs).toEqual(["A. Bakker"]);
  expect(await matcher.autoApply(suggestion("Anke", { topics: ["X"] }), anke.id, "", "T1")).toBeNull();
});

// MARK: link (Windows stores no participants per recording, so there is no participant step)

it("linkRoutesAmbiguousMatchedAndNewPeople", async () => {
  const devries = profile("Jan de Vries"), smit = profile("Jan Smit"), anke = profile("Anke Bakker");
  const { store, matcher } = await fresh([devries, smit, anke]);
  const set = {
    terms: [{ heard: "Kaskop", canonical: "Kascop", note: "" }],
    people: [suggestion("Jan"), suggestion("Anke Bakker", { topics: ["Dakschade"] }), suggestion("Kees de Wit")],
  };
  const kept = await matcher.link(set, "T1", "Overleg");
  expect(kept.terms).toEqual(set.terms);
  expect(kept.people.map(p => p.name)).toEqual(["Jan", "Kees de Wit"]);
  expect(new Set(kept.people[0].candidateIds)).toEqual(new Set([devries.id, smit.id]));
  expect(kept.people[0].matchedPersonId).toBeUndefined();
  expect(kept.people[1].candidateIds).toEqual([]);
  expect(kept.people[1].matchedPersonId).toBeUndefined();
  expect(person(store, anke.id).expertiseTags).toEqual(["Dakschade"]);
  expect(person(store, anke.id).meetingTypes).toEqual(["Overleg"]);
});
