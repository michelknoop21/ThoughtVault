import { beforeEach, expect, it } from "vitest";
import { saveQuickNote, getQuickNote } from "../quickNotes";

beforeEach(() => localStorage.clear());

it("keeps a recording's note available for retries without mixing recordings", () => {
  saveQuickNote("C:\\Recordings\\one.wav", "  Bespreek de planning  ");
  saveQuickNote("C:\\Recordings\\two.wav", "Budget");
  expect(getQuickNote("C:\\Recordings\\one.wav")).toBe("Bespreek de planning");
  expect(getQuickNote("C:\\Recordings\\two.wav")).toBe("Budget");
  expect(getQuickNote("C:\\Recordings\\other.wav")).toBe("");
});

it("does not replace a saved note with an empty retry draft", () => {
  saveQuickNote("one.wav", "Planning");
  saveQuickNote("one.wav", " ");
  expect(getQuickNote("one.wav")).toBe("Planning");
});
