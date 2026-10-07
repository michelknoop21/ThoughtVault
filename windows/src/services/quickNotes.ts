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
