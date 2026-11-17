// Same lifecycle as Apple's QuickNoteStore: keep context with the audio file,
// including across offline processing/retries. Credentials never enter this store.
const noteKey = (path: string) => `quick-note:${path}`;
export function saveQuickNote(audioPath: string, note: string): void {
  if (note.trim()) localStorage.setItem(noteKey(audioPath), note.trim());
}
export function saveQuickNoteDraft(audioPath: string, note: string): void {
  if (!audioPath) return;
  if (note.trim()) saveQuickNote(audioPath, note);
  else localStorage.removeItem(noteKey(audioPath));
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

export interface RecordingIdentity {
  title?: string;
  calendar?: { id: string; title: string; start: string; end: string; join_url?: string };
}
export function saveRecordingIdentity(path: string, identity: RecordingIdentity): void {
  localStorage.setItem(`recording-identity:${path}`, JSON.stringify(identity));
}
export function getRecordingIdentity(path: string): RecordingIdentity | undefined {
  try { return JSON.parse(localStorage.getItem(`recording-identity:${path}`) ?? "null") ?? undefined; } catch { return undefined; }
}
export function linkRecordingIdentity(taskId: string, path: string): void {
  localStorage.setItem(`recording-identity-audio:${taskId}`, path);
}
export function getTranscriptIdentity(taskId: string): RecordingIdentity | undefined {
  return getRecordingIdentity(localStorage.getItem(`recording-identity-audio:${taskId}`) ?? "");
}

export interface NotebookDocument { notes: string; items: Array<{ text: string; done: boolean }> }
export function parseNotebook(text: string): NotebookDocument {
  const lines: string[] = [], items: NotebookDocument["items"] = [];
  for (const line of text.split("\n")) {
    if (line.startsWith("- [ ] ") || line.startsWith("- [x] ")) items.push({ text: line.slice(6), done: line.startsWith("- [x] ") });
    else lines.push(line);
  }
  return { notes: lines.join("\n").replace(/^\n+|\n+$/g, ""), items };
}
export function serializeNotebook(document: NotebookDocument): string {
  return [document.notes, ...document.items.map(item => `- [${item.done ? "x" : " "}] ${item.text.replace(/\n/g, " ")}`)].filter(Boolean).join("\n");
}
export function withoutOwnNotes(html: string): string {
  return html.replace(/<!--thoughtvault-own-notes-->[\s\S]*?<!--\/thoughtvault-own-notes-->/g, "").replace(/<section\b[^>]*data-thoughtvault-notes=["']true["'][^>]*>[\s\S]*?<\/section>/gi, "");
}
export function exportWithOwnNotes(html: string, note: string | undefined, includeNotes: boolean): string {
  const clean = withoutOwnNotes(html);
  if (!includeNotes) return clean;
  // Preserve edits made to the saved section in the notule editor.
  if (clean !== html) return html;
  if (!note?.trim()) return html;
  const escape = (text: string) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const document = parseNotebook(note);
  const body = document.notes ? `<p>${escape(document.notes).replace(/\n/g, "<br>")}</p>` : "";
  const actions = document.items.length ? `<h3>Actiepunten uit het kladblok</h3><ul>${document.items.map(item => `<li>${item.done ? "☑" : "☐"} ${escape(item.text)}</li>`).join("")}</ul>` : "";
  const section = `<!--thoughtvault-own-notes--><section data-thoughtvault-notes="true"><hr><h2>Eigen notities</h2>${body}${actions}</section><!--/thoughtvault-own-notes-->`;
  return /<\/body>/i.test(clean) ? clean.replace(/<\/body>/i, section + "</body>") : clean + section;
}
