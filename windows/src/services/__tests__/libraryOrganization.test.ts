import { describe, expect, it } from "vitest";
import { applyLabels, manualTags, matchesFolder, parseLabels, validateLibrary, type LibraryEntry } from "../libraryOrganization";
import type { Transcript } from "../../types";
const label: LibraryEntry = { id: "a", name: "Project", kind: "label", description: "Projectwerk", automatic: true, labelIDs: [] };
const note = { id: "local-a", tags: ["Handmatig"], notule_html: "<p>Besluit</p>" } as Transcript;

describe("organization", () => {
  it("keeps manual corrections through reruns and makes re-added labels manual", () => {
    const first = applyLabels(note, ["a"], [label], [label]);
    expect(first.tags).toEqual(["Handmatig", "Project"]);
    const removed = { ...first, tags: ["Handmatig"], organization: manualTags(first, ["Handmatig"], [label]) };
    expect(applyLabels(removed, ["a"], [label], [label]).tags).toEqual(["Handmatig"]);
    const readded = { ...removed, tags: ["Handmatig", "Project"], organization: manualTags(removed, ["Handmatig", "Project"], [label]) };
    expect(applyLabels(readded, [], [label], [label]).tags).toEqual(["Handmatig", "Project"]);
    expect(readded.organization.suppressedLabelIDs).toEqual([]);
  });
  it("never removes a manual match or applies a disabled/changed label", () => {
    expect(applyLabels({ ...note, tags: ["Project"] }, [], [label], [label]).tags).toEqual(["Project"]);
    expect(applyLabels(note, ["a"], [label], [{ ...label, automatic: false }]).tags).toEqual(note.tags);
    expect(applyLabels(note, ["a"], [label], [{ ...label, description: "Changed" }]).tags).toEqual(note.tags);
  });
  it("accepts empty and duplicate choices but rejects invented and malformed IDs", () => {
    expect(parseLabels('[]', [label])).toEqual([]);
    expect(parseLabels('["a","a"]', [label])).toEqual(["a"]);
    for (const output of ['["invented"]', '{}', '[1]', '```json\n[]\n```', 'bad']) expect(() => parseLabels(output, [label])).toThrow();
  });
  it("matches several smart folders and unfiles deleted folders without changing notes", () => {
    const smart = { ...label, id: "smart", kind: "smart", labelIDs: ["a"] } as LibraryEntry;
    const folder = { ...label, id: "folder", kind: "folder" } as LibraryEntry;
    const placed = { ...note, tags: ["Project"], organization: { folderID: "folder", automaticLabelIDs: [], suppressedLabelIDs: [] } };
    expect(matchesFolder(placed, "folder", [folder])).toBe(true);
    expect(matchesFolder(placed, "unfiled", [folder])).toBe(false);
    expect(matchesFolder(placed, "unfiled", [])).toBe(true);
    expect(matchesFolder(placed, "smart", [label, smart])).toBe(true);
    expect(matchesFolder(placed, "smart2", [label, { ...smart, id: "smart2" }])).toBe(true);
    expect(matchesFolder({ ...placed, tags: [] }, "smart", [label, smart])).toBe(false);
  });
});

it("rejects corrupt catalogs before they can overwrite stored references", () => {
  expect(validateLibrary([])).toEqual([]);
  expect(validateLibrary([label])).toEqual([label]);
  for (const value of [null, {}, [label, label], [{ ...label, kind: "nested" }], [{ ...label, labelIDs: null }]]) {
    expect(() => validateLibrary(value)).toThrow();
  }
});
