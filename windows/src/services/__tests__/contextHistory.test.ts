// Version history for directory people and glossary entries.
import { expect, it, vi } from "vitest";
vi.mock("@tauri-apps/api/core", async () => (await import("./fakeAppData")).tauriCore);
import { files } from "./fakeAppData";
import type { PersonalCorrection } from "../personalCorrections";

async function fresh() {
  vi.resetModules();
  files.clear();
  const people = (await import("../../stores/peopleDirectoryStore")).usePeopleDirectoryStore;
  people.setState({ people: [] });
  return {
    history: await import("../contextHistory"),
    corrections: (await import("../../stores/personalCorrectionsStore")).usePersonalCorrectionsStore,
    people,
  };
}

const correction = (canonical: string, variants: string[], note?: string): PersonalCorrection =>
  ({ id: crypto.randomUUID(), canonical, variants, scope: null, enabled: true, ...(note ? { note } : {}) });

it("recordKeepsAtMost50PerItem", async () => {
  const { history } = await fresh();
  await history.record("term", "b", "handmatig", ["ander"]);
  for (let i = 0; i < 55; i++) await history.record("person", "a", "handmatig", [i]);
  const versions = await history.versions("person", "a");
  expect(versions.length).toBe(history.MAX_PER_ITEM);
  expect(versions[0].snapshotJSON).toBe("[54]");
  expect(versions[versions.length - 1].snapshotJSON).toBe("[5]");
  expect((await history.versions("term", "b")).map(v => v.snapshotJSON)).toEqual(['["ander"]']);
  expect(await history.versions("term", "a")).toEqual([]);
});

it("restoreCreatesNewVersionAndKeepsNewer", async () => {
  const { history, people } = await fresh();
  const person = people.getState().createDefaultPerson({ name: "Anke Bakker", role: "v0" });
  people.getState().addPerson(person);
  for (const role of ["v1", "v2", "v3"]) {
    await people.getState().recordUpdate(person.id, "handmatig", { role, responsibilities: [role] });
  }
  let versions = await history.versions("person", person.id);
  expect(versions.length).toBe(3);

  await people.getState().restorePerson(versions[versions.length - 1]);

  const current = people.getState().people.find(p => p.id === person.id)!;
  expect(current.role).toBe("v0");
  expect(current.responsibilities).toEqual([]);
  versions = await history.versions("person", person.id);
  expect(versions.length).toBe(4);
  expect(versions[0].source).toBe("herstel");
  expect(versions.slice(1).map(v => v.source)).toEqual(["handmatig", "handmatig", "handmatig"]);
  const kept = JSON.parse(versions[0].snapshotJSON);
  expect(kept.role).toBe("v3");
  expect(kept.responsibilities).toEqual(["v3"]);
});

it("updateWithoutChangeAddsNoVersion", async () => {
  const { history, people } = await fresh();
  const person = people.getState().createDefaultPerson({ name: "Anke Bakker", role: "PM" });
  people.getState().addPerson(person);
  await people.getState().recordUpdate(person.id, "handmatig", { role: "PM" });
  expect(await history.versions("person", person.id)).toEqual([]);
  await people.getState().recordUpdate(person.id, "handmatig", { role: "Projectleider" });
  expect((await history.versions("person", person.id)).length).toBe(1);
});

it("overlappingUpdatesRecordEachPreState", async () => {
  const { history, people } = await fresh();
  const person = people.getState().createDefaultPerson({ name: "Anke Bakker", role: "v0" });
  people.getState().addPerson(person);
  await Promise.all([
    people.getState().recordUpdate(person.id, "handmatig", { role: "v1" }),
    people.getState().recordUpdate(person.id, "handmatig", { role: "v2" }),
  ]);
  expect((await history.versions("person", person.id)).map(v => JSON.parse(v.snapshotJSON).role)).toEqual(["v1", "v0"]);
  expect(people.getState().people[0].role).toBe("v2");
});

it("damagedHistoryIsMovedAsideNotOverwritten", async () => {
  const { history } = await fresh();
  files.set("context-history.json", "geen json");
  await history.record("term", "a", "handmatig", ["x"]);
  expect((await history.versions("term", "a")).length).toBe(1);
  files.set("context-history.json", "weer kapot");
  await history.record("term", "a", "handmatig", ["y"]);
  expect([...files.keys()].filter(name => name.includes("unreadable-")).length).toBe(2);
});

it("saveRecordingTwiceKeepsFirstStateAndRestores", async () => {
  const { history, corrections } = await fresh();
  const entry = correction("Yinga", ["Jengo"]);
  await corrections.getState().save(entry);
  expect(await history.versions("term", entry.id)).toEqual([]);

  await corrections.getState().save({ ...entry, variants: ["Jengo", "Django"] });

  let versions = await history.versions("term", entry.id);
  expect(versions.length).toBe(1);
  expect(JSON.parse(versions[0].snapshotJSON).variants).toEqual(["Jengo"]);
  expect(corrections.getState().entries.map(e => e.variants)).toEqual([["Jengo", "Django"]]);

  await corrections.getState().restore(versions[0]);

  expect(corrections.getState().entries.map(e => e.variants)).toEqual([["Jengo"]]);
  versions = await history.versions("term", entry.id);
  expect(versions.map(v => v.source)).toEqual(["herstel", "handmatig"]);
});

it("deletedTermCanBeRestored", async () => {
  const { history, corrections } = await fresh();
  const keep = correction("Prezent", []);
  const entry = correction("Yinga", ["Jengo"], "Merknaam");
  await corrections.getState().save(keep);
  await corrections.getState().save(entry);

  await corrections.getState().remove(entry.id);

  expect(corrections.getState().entries).toEqual([keep]);
  const versions = await history.versions("term", entry.id);
  expect(versions.length).toBe(1);
  await corrections.getState().restore(versions[0]);
  expect(corrections.getState().entries).toEqual([keep, entry]);
});

it("saveRecordingMergeRecordsExistingEntry", async () => {
  const { history, corrections } = await fresh();
  const first = correction("Yinga", ["Jengo"]);
  const other = correction("Prezent", []);
  await corrections.getState().save(first);
  await corrections.getState().save(other);

  const saved = await corrections.getState().save(correction("yinga", ["Django"]), "gesprek:t1");

  expect(saved.map(e => e.canonical)).toEqual(["Prezent", "yinga"]);
  expect(saved[saved.length - 1].id).toBe(first.id);
  expect(saved[saved.length - 1].variants).toEqual(["Jengo", "Django"]);
  const versions = await history.versions("term", first.id);
  expect(versions.map(v => v.source)).toEqual(["gesprek:t1"]);
  expect(JSON.parse(versions[0].snapshotJSON)).toEqual(first);
  expect(await history.versions("term", other.id)).toEqual([]);
});

it("personSnapshotRoundTrip", async () => {
  const { history, people } = await fresh();
  const person = people.getState().createDefaultPerson({ name: "Bram", role: "PM", emails: ["b@x.nl"], isInternal: false, responsibilities: ["Planning"] });
  const snapshot = history.personSnapshot(person);
  const other = history.applySnapshot(JSON.parse(JSON.stringify(snapshot)), people.getState().createDefaultPerson());
  expect(history.personSnapshot(other)).toEqual(snapshot);
});
