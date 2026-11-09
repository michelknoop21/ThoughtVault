// Texts and merge rules of the suggestion bar above the notule.
import { expect, it } from "vitest";
import { ambiguousQuestion, applyRemainder, changeSummary, counter } from "../contextSuggestionBarLogic";
import type { PersonSuggestion } from "../../../services/contextSuggestions";
import type { PersonSnapshot } from "../../../services/contextHistory";

const remainder = (extra: Partial<PersonSuggestion> = {}): PersonSuggestion =>
  ({ name: "Jan de Vries", role: "", organization: "", responsibilities: [], topics: [], heardAs: [], matchedPersonId: "p1", candidateIds: [], ...extra });
const snapshot = (extra: Partial<PersonSnapshot> = {}): PersonSnapshot =>
  ({ name: "Jan de Vries", role: "", organization: "", aliases: [], meetingTypes: [], expertiseTags: [], emails: [], responsibilities: [], ...extra });

it("counterUsesDutchSingularAndPlural", () => {
  expect(counter(2, 1)).toBe("2 termen, 1 persoon");
  expect(counter(1, 2)).toBe("1 term, 2 personen");
  expect(counter(0, 3)).toBe("3 personen");
  expect(counter(1, 0)).toBe("1 term");
});

it("ambiguousQuestionListsCandidates", () => {
  expect(ambiguousQuestion(["Jan de Vries", "Jan Smit"])).toBe("Is dit Jan de Vries of Jan Smit?");
  expect(ambiguousQuestion(["A", "B", "C"])).toBe("Is dit A, B of C?");
  expect(ambiguousQuestion([])).toBe("");
});

it("applyRemainderKeepsFieldsWhenProposalIsEmpty", () => {
  const result = applyRemainder(remainder(), snapshot({ role: "CTO", organization: "Acme" }));
  expect(result.role).toBe("CTO");
  expect(result.organization).toBe("Acme");
});

it("applyRemainderSetsRoleAndOrganization", () => {
  const result = applyRemainder(remainder({ role: " Teamleider ", organization: "Gemeente" }), snapshot({ role: "CTO" }));
  expect(result.role).toBe("Teamleider");
  expect(result.organization).toBe("Gemeente");
});

it("applyRemainderMergesAliasesCaseInsensitively", () => {
  const result = applyRemainder(remainder({ heardAs: ["JAN DE FRIES", "jan de vries", "Jan V.", "jan v.", " "] }), snapshot({ aliases: ["Jan de Fries"] }));
  expect(result.aliases).toEqual(["Jan de Fries", "Jan V."]);
});

it("changeSummaryDescribesEachChange", () => {
  expect(changeSummary(remainder({ role: "Teamleider", organization: "Gemeente", heardAs: ["Jan V.", "jan de vries"] }), snapshot({ role: "CTO" })))
    .toEqual(["Rol: CTO → Teamleider", "Organisatie: Gemeente", "Ook bekend als: Jan V."]);
  expect(changeSummary(remainder({ role: "CTO" }), snapshot({ role: "CTO" }))).toEqual([]);
});
