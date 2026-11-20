import type { Transcript } from "../types";

export interface LibraryEntry {
  id: string;
  name: string;
  kind: "folder" | "smart" | "label";
  labelIDs: string[];
  description: string;
  automatic: boolean;
}
export interface NoteOrganization {
  folderID?: string;
  automaticLabelIDs: string[];
  suppressedLabelIDs: string[];
}
export function metadata(note: Transcript): NoteOrganization {
  return note.organization ?? { automaticLabelIDs: [], suppressedLabelIDs: [] };
}
export function matchesFolder(note: Transcript, selection: string, entries: LibraryEntry[]): boolean {
  if (selection === "all") return true;
  const folder = entries.find(e => e.kind === "folder" && e.id === metadata(note).folderID);
  if (selection === "unfiled") return !folder;
  const smart = entries.find(e => e.kind === "smart" && e.id === selection);
  return smart ? entries.some(e => e.kind === "label" && smart.labelIDs.includes(e.id) && note.tags.includes(e.name)) : folder?.id === selection;
}
export function manualTags(note: Transcript, tags: string[], labels: LibraryEntry[]): NoteOrganization {
  const old = metadata(note);
  const result = { ...old, automaticLabelIDs: [...old.automaticLabelIDs], suppressedLabelIDs: [...old.suppressedLabelIDs] };
  for (const label of labels) {
    if (note.tags.includes(label.name) && !tags.includes(label.name) && old.automaticLabelIDs.includes(label.id)) {
      if (!result.suppressedLabelIDs.includes(label.id)) result.suppressedLabelIDs.push(label.id);
    }
    if (tags.includes(label.name) && !note.tags.includes(label.name)) {
      result.automaticLabelIDs = result.automaticLabelIDs.filter(id => id !== label.id);
      result.suppressedLabelIDs = result.suppressedLabelIDs.filter(id => id !== label.id);
    }
  }
  return result;
}
export function parseLabels(output: string, allowed: LibraryEntry[]): string[] {
  const ids: unknown = JSON.parse(output);
  if (!Array.isArray(ids) || !ids.every(id => typeof id === "string" && allowed.some(e => e.id === id))) {
    throw new Error("De AI gaf ongeldige labels terug. Probeer opnieuw.");
  }
  return [...new Set(ids)] as string[];
}
export function applyLabels(note: Transcript, chosen: string[], eligible: LibraryEntry[], current: LibraryEntry[]): Transcript {
  const old = metadata(note);
  const active = current.filter(e => e.kind === "label" && e.automatic && eligible.some(old => JSON.stringify(old) === JSON.stringify(e)));
  const names = active.filter(e => old.automaticLabelIDs.includes(e.id)).map(e => e.name);
  const tags = note.tags.filter(t => !names.includes(t));
  const organization = { ...old, automaticLabelIDs: old.automaticLabelIDs.filter(id => !active.some(e => e.id === id)) };
  for (const label of active) {
    if (chosen.includes(label.id) && !old.suppressedLabelIDs.includes(label.id) && !tags.includes(label.name)) {
      tags.push(label.name); organization.automaticLabelIDs.push(label.id);
    }
  }
  return { ...note, tags, organization, auto_label_error: undefined };
}

export function validateLibrary(value: unknown): LibraryEntry[] {
  if (!Array.isArray(value) || !value.every(e => e && typeof e.id === "string" && e.id && typeof e.name === "string" && e.name.trim()
    && ["folder", "smart", "label"].includes(e.kind) && Array.isArray(e.labelIDs) && e.labelIDs.every((id: unknown) => typeof id === "string")
    && typeof e.description === "string" && typeof e.automatic === "boolean") || new Set(value.map(e => e.id)).size !== value.length) {
    throw new Error("De mapgegevens konden niet veilig worden gelezen. De bestaande opslag blijft bewaard.");
  }
  return value;
}
