import { beforeEach, expect, it } from "vitest";
import { saveQuickNote, getQuickNote, ensureNotesSection, quickNotePrompt } from "../quickNotes";

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

it("adds an escaped Notities section only when missing and a note exists", () => {
  expect(ensureNotesSection("<p>x</p>", "A & B <i>\nregel 2")).toBe("<p>x</p><h2>Notities</h2><p>A &amp; B &lt;i&gt;<br>regel 2</p>");
  const own = '<p>x</p><H2 class="a"> Notities </H2><p>herschreven</p>';
  expect(ensureNotesSection(own, "ruw")).toBe(own);
  expect(ensureNotesSection("<p>x</p>", "  ")).toBe("<p>x</p>");
  expect(ensureNotesSection("<body><p>x</p></body>", "n")).toBe("<body><p>x</p><h2>Notities</h2><p>n</p></body>");
});

it("asks for a rewritten Notities section in the prompt", () => {
  expect(quickNotePrompt("")).toBe("");
  expect(quickNotePrompt("Budget")).toContain("Herschrijf");
});
