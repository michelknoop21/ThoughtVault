// peopleDirectoryStore.test.ts
// RED until Plan 02-05 implements usePeopleDirectoryStore.
// Importing from ../peopleDirectoryStore (module does not exist) makes this fail immediately —
// that is the intended RED state anchoring the Windows people-directory behavior.
//
// Pitfall 4 guard: store name MUST be "people-directory-store" (distinct from
// "person-profile-store" / "profiles-store" / "settings-store").

import { afterEach, beforeEach, describe, expect, it } from "vitest";

// RED: this module does not exist yet (Plan 02-05 creates it)
import { usePeopleDirectoryStore } from "../peopleDirectoryStore";

// Reset zustand + localStorage between tests
beforeEach(() => {
  usePeopleDirectoryStore.setState({ people: [] });
  localStorage.clear();
});

afterEach(() => {
  usePeopleDirectoryStore.setState({ people: [] });
  localStorage.clear();
});

// ---------------------------------------------------------------------------
// Test 1: addPerson / updatePerson / removePerson round-trip
// ---------------------------------------------------------------------------
describe("people-directory-store", () => {
  it("add → update → remove round-trip leaves the store empty (no isSelf entries)", () => {
    const { addPerson, updatePerson, removePerson } = usePeopleDirectoryStore.getState();

    // Add a directory person (isSelf must always be false in this store)
    const newPerson = {
      id: crypto.randomUUID(),
      name: "Anke Bakker",
      role: "Designer",
      organization: "Prezent BV",
      aliases: [],
      meetingTypes: [],
      expertiseTags: [],
      emails: [],
      isSelf: false,             // isSelf: false is invariant for directory entries
      isInternal: null,          // null = onbekend (D-09)
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    addPerson(newPerson);

    // isSelf entries must NEVER be present in the directory store
    const afterAdd = usePeopleDirectoryStore.getState().people;
    expect(afterAdd.every((p) => p.isSelf === false)).toBe(true);
    expect(afterAdd.length).toBe(1);
    expect(afterAdd[0].name).toBe("Anke Bakker");

    // Update name
    updatePerson(newPerson.id, { name: "Anke B. Bakker" });
    const afterUpdate = usePeopleDirectoryStore.getState().people;
    expect(afterUpdate[0].name).toBe("Anke B. Bakker");

    // Remove
    removePerson(newPerson.id);
    const afterRemove = usePeopleDirectoryStore.getState().people;
    expect(afterRemove).toHaveLength(0);
  });

  // -------------------------------------------------------------------------
  // Test 2: factory defaults — isInternal === null, emails === []
  // -------------------------------------------------------------------------
  it("new-person factory defaults: isInternal is null and emails is []", () => {
    const { addPerson } = usePeopleDirectoryStore.getState();

    // createDefaultPerson() is a helper that returns a new PersonProfile
    // with the D-09 defaults (isInternal=null, emails=[])
    const { createDefaultPerson } = usePeopleDirectoryStore.getState();
    const defaultPerson = createDefaultPerson({ name: "Pieter Jansen" });

    // isInternal must default to null (= onbekend, D-09)
    expect(defaultPerson.isInternal).toBeNull();

    // emails must default to empty array
    expect(defaultPerson.emails).toEqual([]);

    // Sanity: isSelf must always be false
    expect(defaultPerson.isSelf).toBe(false);

    // Persist and re-read to confirm defaults round-trip through the store
    addPerson(defaultPerson);
    const stored = usePeopleDirectoryStore.getState().people.find((p) => p.id === defaultPerson.id);
    expect(stored?.isInternal).toBeNull();
    expect(stored?.emails).toEqual([]);
  });

  // -------------------------------------------------------------------------
  // Test 3: distinct localStorage key — must be "people-directory-store"
  // (Pitfall 4: must NOT equal "person-profile-store"/"profiles-store"/"settings-store")
  // -------------------------------------------------------------------------
  it("persist store uses the distinct key people-directory-store (Pitfall 4)", () => {
    const { addPerson } = usePeopleDirectoryStore.getState();

    // Trigger a write by adding a person
    addPerson({
      id: crypto.randomUUID(),
      name: "Test Person",
      role: "",
      organization: "",
      aliases: [],
      meetingTypes: [],
      expertiseTags: [],
      emails: [],
      isSelf: false,
      isInternal: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    // The directory store must write to "people-directory-store"
    expect(localStorage.getItem("people-directory-store")).not.toBeNull();

    // The singleton profile store must be unaffected (Pitfall 4)
    expect(localStorage.getItem("person-profile-store")).toBeNull();

    // Verify it does NOT accidentally overwrite other stores
    expect(localStorage.getItem("profiles-store")).toBeNull();
    expect(localStorage.getItem("settings-store")).toBeNull();
  });

  // -------------------------------------------------------------------------
  // Test 4: dedup helper — filters known directory emails + self/account email
  // (case-insensitive, D-10)
  // -------------------------------------------------------------------------
  it("dedup filters already-known and self emails case-insensitively", () => {
    const { addPerson, newSeedCandidates } = usePeopleDirectoryStore.getState();

    // Seed with a person whose email is known
    addPerson({
      id: crypto.randomUUID(),
      name: "Anke Bakker",
      role: "Designer",
      organization: "Prezent BV",
      aliases: [],
      meetingTypes: [],
      expertiseTags: [],
      emails: ["a@x.nl"],
      isSelf: false,
      isInternal: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    // Candidates: known (uppercased → case-insensitive match), new, self
    const candidates = ["A@X.NL", "new@x.nl", "self@x.nl"];
    const result = newSeedCandidates(candidates, "self@x.nl");

    // Only the genuinely new address must survive
    expect(result).toEqual(["new@x.nl"]);
  });
});
