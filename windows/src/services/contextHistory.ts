// Version history for the context sent to the minutes AI: directory people and
// glossary entries. Every change stores the state from before that change, so any
// earlier version can be restored. Kept in context-history.json next to the glossary,
// in the same format as macOS.
import { invoke } from "@tauri-apps/api/core";
import type { PersonProfile } from "../types";

export type HistoryKind = "person" | "term";
export interface HistoryEntry {
  /** Uppercase UUID, like Swift's UUID encoding. */
  id: string;
  kind: HistoryKind;
  itemId: string;
  /** Seconds since 2001-01-01 UTC (Swift's default Date encoding). */
  date: number;
  /** "handmatig", "gesprek:<taskId>", "voorstel:<taskId>" or "herstel". */
  source: string;
  snapshotJSON: string;
}
/** The editable fields of a directory person, as stored in the history. */
export interface PersonSnapshot {
  name: string;
  role: string;
  organization: string;
  aliases: string[];
  meetingTypes: string[];
  expertiseTags: string[];
  emails: string[];
  isInternal?: boolean;
  responsibilities: string[];
}

export const MAX_PER_ITEM = 50;
const FILE = "context-history.json";
const REFERENCE_DATE_MS = Date.UTC(2001, 0, 1);

export const historyDate = (entry: HistoryEntry) => new Date(REFERENCE_DATE_MS + entry.date * 1000);

const isEntry = (value: unknown): value is HistoryEntry => {
  const e = value as HistoryEntry;
  return !!e && typeof e.id === "string" && (e.kind === "person" || e.kind === "term") && typeof e.itemId === "string"
    && typeof e.date === "number" && typeof e.source === "string" && typeof e.snapshotJSON === "string";
};

/**
 * Reads the history file; empty only when it does not exist. A read error throws, so the
 * file is never overwritten. A file that does not decode is moved aside under a unique
 * name (kept for recovery), so a damaged history never blocks edits.
 */
async function load(): Promise<HistoryEntry[]> {
  const raw = await invoke<string | null>("read_context_file", { name: FILE });
  if (raw == null) return [];
  try {
    const entries: unknown = JSON.parse(raw);
    if (Array.isArray(entries) && entries.every(isEntry)) return entries;
  } catch { /* moved aside below */ }
  await invoke("set_aside_context_file", { name: FILE, suffix: crypto.randomUUID().toUpperCase() });
  return [];
}

// Every read-modify-write runs serially, like the main-actor isolation on macOS.
let queue: Promise<unknown> = Promise.resolve();

export function record(kind: HistoryKind, itemId: string, source: string, snapshot: unknown): Promise<void> {
  return recordChange(kind, itemId, source, () => ({ before: snapshot, apply: () => {} }));
}

/**
 * Runs `change` inside the history queue, so overlapping edits never record the same
 * pre-state: it reads the current state and returns the snapshot to keep (undefined when
 * nothing changed) plus the update, applied only after the history was written.
 */
export function recordChange(kind: HistoryKind, itemId: string, source: string,
  change: () => { before?: unknown; apply: () => void } | undefined): Promise<void> {
  const operation = queue.then(async () => {
    const next = change();
    if (!next) return;
    if (next.before !== undefined) await append(kind, itemId, source, next.before);
    next.apply();
  });
  queue = operation.catch(() => {});
  return operation;
}

async function append(kind: HistoryKind, itemId: string, source: string, snapshot: unknown) {
  const entries = await load();
  entries.push({ id: crypto.randomUUID().toUpperCase(), kind, itemId, date: (Date.now() - REFERENCE_DATE_MS) / 1000, source, snapshotJSON: JSON.stringify(snapshot) });
  // Entries are appended in order, so the first matches are the oldest.
  let excess = entries.filter(e => e.kind === kind && e.itemId === itemId).length - MAX_PER_ITEM;
  const kept = entries.filter(e => {
    if (excess <= 0 || e.kind !== kind || e.itemId !== itemId) return true;
    excess -= 1;
    return false;
  });
  await invoke("write_context_file", { name: FILE, contents: JSON.stringify(kept) });
}

/** Versions of one item, newest first. An unreadable history counts as empty. */
export async function versions(kind: HistoryKind, itemId: string): Promise<HistoryEntry[]> {
  const operation = queue.then(load);
  queue = operation.catch(() => {});
  try {
    return (await operation).filter(e => e.kind === kind && e.itemId === itemId).reverse();
  } catch {
    return [];
  }
}

export function personSnapshot(p: PersonProfile): PersonSnapshot {
  return {
    name: p.name, role: p.role, organization: p.organization, aliases: p.aliases, meetingTypes: p.meetingTypes,
    expertiseTags: p.expertiseTags, emails: p.emails,
    // Swift omits a nil optional; keep the same shape.
    ...(p.isInternal === null ? {} : { isInternal: p.isInternal }),
    responsibilities: p.responsibilities ?? [],
  };
}

export function applySnapshot(s: PersonSnapshot, p: PersonProfile): PersonProfile {
  return {
    ...p, name: s.name, role: s.role, organization: s.organization, aliases: s.aliases, meetingTypes: s.meetingTypes,
    expertiseTags: s.expertiseTags, emails: s.emails, isInternal: s.isInternal ?? null, responsibilities: s.responsibilities ?? [],
  };
}
