import { beforeEach, expect, it, vi } from "vitest";
import { saveQuickNote, getQuickNote, ensureNotesSection, quickNotePrompt } from "../quickNotes";
import { useRecordingStore } from "../../stores/recordingStore";

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

it("saves active and paused edits immediately without losing notes on reset or clearing another recording", () => {
  const store = useRecordingStore.getState();
  store.reset();
  saveQuickNote("other.wav", "Andere opname");
  store.setFilePath("current.wav");
  store.setPhase("recording");
  store.setQuickNote("Eerste punt");
  expect(getQuickNote("current.wav")).toBe("Eerste punt");
  store.setPhase("paused");
  store.setQuickNote("Eerste punt\nTweede punt");
  expect(getQuickNote("current.wav")).toBe("Eerste punt\nTweede punt");
  store.setQuickNote(" \n");
  expect(getQuickNote("current.wav")).toBe("");
  expect(getQuickNote("other.wav")).toBe("Andere opname");
  store.setQuickNote("Bewaren");
  store.reset();
  expect(getQuickNote("current.wav")).toBe("Bewaren");
});

it("keeps the edited text in memory when local storage fails so the user can retry", () => {
  const store = useRecordingStore.getState();
  store.reset();
  store.setFilePath("current.wav");
  store.setPhase("recording");
  const write = vi.spyOn(localStorage, "setItem").mockImplementationOnce(() => { throw new Error("Storage full"); });
  try {
    expect(() => store.setQuickNote("Bewaar mijn punt")).toThrow("Storage full");
    expect(useRecordingStore.getState().quickNote).toBe("Bewaar mijn punt");
    store.setQuickNote(useRecordingStore.getState().quickNote);
    expect(getQuickNote("current.wav")).toBe("Bewaar mijn punt");
  } finally {
    write.mockRestore();
    store.reset();
  }
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

it("keeps checklist edits and completion status across serialization", async () => {
  const { parseNotebook, serializeNotebook } = await import("../quickNotes");
  const text = "Notitie\n\nContext\n- [ ] Alex belt de klant\n- [x] Toegang geregeld";
  const document = parseNotebook(text);
  expect(serializeNotebook(document)).toBe(text);
  document.items[0] = { text: "Alex mailt de klant", done: true };
  expect(parseNotebook(serializeNotebook(document)).items).toEqual([
    { text: "Alex mailt de klant", done: true }, { text: "Toegang geregeld", done: true },
  ]);
});

it("exports with or without own notes and retains ordinary meeting sections", async () => {
  const { exportWithOwnNotes, withoutOwnNotes } = await import("../quickNotes");
  const html = "<body><h2>Notities</h2><p>Vergaderinhoud</p></body>";
  const note = "A & <script>\n- [ ] Open\n- [x] Afgerond";
  const included = exportWithOwnNotes(html, note, true);
  expect(included).toContain("Eigen notities");
  expect(included).toContain("&lt;script&gt;");
  expect(included).toContain("☑ Afgerond");
  expect(exportWithOwnNotes(included, note, false)).toBe(html);
  expect(exportWithOwnNotes(included, note, true)).toBe(included);
  expect(exportWithOwnNotes(included, undefined, true)).toBe(included);
  const edited = included.replace("Open", "Bewerkt");
  expect(exportWithOwnNotes(edited, note, true)).toBe(edited);
  expect(exportWithOwnNotes(included, undefined, false)).toBe(html);
  expect(withoutOwnNotes(included.replaceAll(/<!--[\s\S]*?-->/g, ""))).toBe(html);
});

it("persists meeting identity independently per recording and links it to a result", async () => {
  const { saveRecordingIdentity, getRecordingIdentity, linkRecordingIdentity, getTranscriptIdentity } = await import("../quickNotes");
  const identity = { title: "Eigen titel", calendar: { id: "event-42", title: "Agenda-afspraak", start: "2026-11-17T10:30:00Z", end: "2026-11-17T11:00:00Z" } };
  saveRecordingIdentity("current.wav", identity);
  linkRecordingIdentity("task-42", "current.wav");
  expect(getRecordingIdentity("current.wav")).toEqual(identity);
  expect(getTranscriptIdentity("task-42")).toEqual(identity);
  expect(getRecordingIdentity("other.wav")).toBeUndefined();
});
