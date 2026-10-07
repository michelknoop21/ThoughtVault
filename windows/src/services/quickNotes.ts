// Same lifecycle as Apple's QuickNoteStore: keep context with the audio file,
// including across offline processing/retries. Credentials never enter this store.
const noteKey = (path: string) => `quick-note:${path}`;
export function saveQuickNote(audioPath: string, note: string): void {
  if (note.trim()) localStorage.setItem(noteKey(audioPath), note.trim());
}
export function getQuickNote(audioPath: string): string {
  return localStorage.getItem(noteKey(audioPath)) ?? "";
}
export function linkQuickNote(taskId: string, audioPath: string): void {
  if (getQuickNote(audioPath)) localStorage.setItem(`quick-note-audio:${taskId}`, audioPath);
}
export function getTranscriptQuickNote(taskId: string): string {
  return getQuickNote(localStorage.getItem(`quick-note-audio:${taskId}`) ?? "");
}

/** Prompt block for local generation: the note is context and ends up rewritten as the last section. */
export function quickNotePrompt(note: string): string {
  const trimmed = note.trim();
  if (!trimmed) return "";
  return `NOTITIE VAN DE GEBRUIKER TIJDENS DE OPNAME (context, geen onderdeel van de transcriptie):\n${trimmed}\n\n`
    + "Sluit de notule af met een sectie <h2>Notities</h2>. Herschrijf de notitie daarin grammaticaal en stilistisch beter dan het origineel. Gebruik de rest van de notule als context (namen, termen, verwijzingen). Behoud elk punt uit de notitie en voeg niets nieuws toe.\n\n";
}

/** Guarantees a "Notities" section: a section the model wrote stays, otherwise the raw note is appended. */
export function ensureNotesSection(html: string, note: string): string {
  const trimmed = note.trim();
  if (!trimmed || /<h2[^>]*>\s*Notities\s*<\/h2>/i.test(html)) return html;
  const escaped = trimmed.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
  const section = `<h2>Notities</h2><p>${escaped}</p>`;
  const body = html.search(/<\/body>(?![\s\S]*<\/body>)/i);
  return body >= 0 ? html.slice(0, body) + section + html.slice(body) : html + section;
}
