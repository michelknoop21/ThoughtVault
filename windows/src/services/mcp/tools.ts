// Tool handlers of the local MCP server. Arguments arrive validated against data/mcp/tools.json,
// with schema defaults filled in. Only local notes are served.
import DOMPurify from "dompurify";
import { marked } from "marked";
import type { Profile, Transcript } from "../../types";
import { DEFAULT_PROFILES } from "../../types";
import type { Handler } from "./router";
import { useLocalTranscriptsStore, newLocalId } from "../../stores/localTranscriptsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import { usePeopleDirectoryStore } from "../../stores/peopleDirectoryStore";
import { usePersonalCorrectionsStore } from "../../stores/personalCorrectionsStore";
import { useSettingsStore } from "../../stores/settingsStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { matchesFolder, matchesSearch, metadata } from "../libraryOrganization";
import { enrichProfile } from "../profileTemplates";
import { htmlToMarkdown } from "../../utils/htmlToMarkdown";
import { getRecordingsDir, listRecordings } from "../tauriCommands";
import { isFinished, useTaskHistory } from "../taskHistory";
import { processLocally } from "../localPipeline";
import { hasUsableTranscription } from "../notuleValidation";
import { regenerateLocalNotule, regenerateTaskId } from "../regenerateNotule";

const SOURCE = "ai-koppeling";
const STALE = "Notitie is intussen gewijzigd. Lees hem opnieuw met get_note.";

type Args = Record<string, any>;

async function notes() {
  await useLocalTranscriptsStore.getState().hydrate();
  return useLocalTranscriptsStore.getState();
}

async function findNote(id: string): Promise<Transcript> {
  const note = (await notes()).items.find(t => t.id === id);
  if (!note) throw new Error("Notitie niet gevonden.");
  return note;
}

/** First 16 hex chars of SHA-256 over the fields update_note may change. */
export async function revisionOf(note: Transcript): Promise<string> {
  const json = JSON.stringify({ title: note.title, tags: note.tags, folder_id: metadata(note).folderID ?? null, notule_html: note.notule_html ?? "" });
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(json));
  return [...new Uint8Array(hash)].slice(0, 8).map(b => b.toString(16).padStart(2, "0")).join("");
}

function markdownToHtml(markdown: string): string {
  return DOMPurify.sanitize(marked.parse(markdown, { async: false }) as string);
}

/** Date-only bounds cover the whole local day. */
function bound(value: string, end: boolean): number {
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(value);
  const time = new Date(dateOnly ? `${value}T00:00:00` : value).getTime();
  if (Number.isNaN(time)) throw new Error(`Ongeldige datum: ${value}`);
  return dateOnly && end ? time + 86_400_000 - 1 : time;
}

function folderExists(id: string): boolean {
  return useLocalTranscriptsStore.getState().library.some(e => e.kind === "folder" && e.id === id);
}

function findProfile(id: string) {
  const profile = useProfilesStore.getState().profiles.find(p => p.id === id);
  if (!profile) throw new Error("Profiel niet gevonden. Gebruik list_profiles.");
  return profile;
}

const builtin = (id: string) => DEFAULT_PROFILES.some(p => p.id === id);

function profileSummary(profile: Profile) {
  return {
    id: profile.id,
    name: profile.name,
    description: profile.description ?? "",
    detail_level: enrichProfile(profile).detail_level ?? null,
    is_default: profile.id === useSettingsStore.getState().default_profile_id,
    builtin: builtin(profile.id),
  };
}

/** Summary shared by list_notes and get_note; empty or unknown values are null. */
function noteSummary(t: Transcript) {
  return {
    id: t.id,
    title: t.title,
    created_at: t.created_at,
    duration_seconds: t.duration_seconds || null,
    profile_id: t.profile_id || null,
    profile_name: t.profile_name || null,
    tags: t.tags,
    folder_id: metadata(t).folderID ?? null,
    has_notule: !!t.notule_html?.trim(),
    has_transcript: !!t.raw_transcription?.trim(),
  };
}

/** Transcript chunk in UTF-16 code units (JS string length); never ends inside a surrogate pair. */
export function transcriptChunk(text: string, offset: number, maxChars: number) {
  let end = Math.min(offset + maxChars, text.length);
  const high = (i: number) => { const c = text.charCodeAt(i); return c >= 0xd800 && c <= 0xdbff; };
  if (end < text.length && end - 1 > offset && high(end - 1)) end -= 1;
  return { text: text.slice(offset, end), offset, total_chars: text.length, next_offset: end < text.length ? end : null };
}

/** File of the recording in progress (preparing up to stopping), or null. */
function liveRecordingFile(): string | null {
  const { phase, filePath } = useRecordingStore.getState();
  if (phase === "idle" || phase === "uploading") return null;
  return filePath?.split(/[\\/]/).pop() ?? "";
}

async function recordingFiles() {
  const live = liveRecordingFile();
  return (await listRecordings(await getRecordingsDir())).filter(f => f.filename !== live);
}

export const handlers: Record<string, Handler> = {
  async list_notes({ query, from, to, folder_id, profile_id, limit, offset }: Args) {
    const { items, library } = await notes();
    const start = from ? bound(from, false) : -Infinity;
    const end = to ? bound(to, true) : Infinity;
    const matching = items
      .filter(t => matchesSearch(t, query ?? ""))
      .filter(t => { const time = new Date(t.created_at).getTime(); return time >= start && time <= end; })
      .filter(t => !folder_id || matchesFolder(t, folder_id, library))
      .filter(t => !profile_id || t.profile_id === profile_id)
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
    return {
      total: matching.length,
      offset,
      notes: matching.slice(offset, offset + limit).map(noteSummary),
    };
  },

  async get_note({ id, format, include_transcript, transcript_offset, max_chars }: Args) {
    const note = await findNote(id);
    const html = note.notule_html ?? "";
    return {
      ...noteSummary(note),
      revision: await revisionOf(note),
      participants: [],
      notule: format === "html" ? html : htmlToMarkdown(html),
      ...(include_transcript ? { transcript: transcriptChunk(note.raw_transcription ?? "", transcript_offset, max_chars) } : {}),
    };
  },

  async list_library() {
    const { library } = await notes();
    return { entries: library.map(e => ({ id: e.id, name: e.name, kind: e.kind, description: e.description, label_ids: e.labelIDs, automatic: e.automatic })) };
  },

  async list_profiles() {
    return { profiles: useProfilesStore.getState().profiles.map(profileSummary) };
  },

  async get_profile({ id }: Args) {
    const profile = findProfile(id);
    const full = enrichProfile(profile);
    return {
      ...profileSummary(profile),
      system_prompt: full.system_prompt ?? null,
      notule_prompt: full.notule_prompt ?? null,
      output_template: full.output_template ?? full.notule_template ?? null,
    };
  },

  async list_people({ query }: Args) {
    const needle = (query ?? "").trim().toLocaleLowerCase("nl-NL");
    const people = usePeopleDirectoryStore.getState().people.filter(p => !needle
      || [p.name, p.organization, ...p.aliases, ...p.emails].some(v => v.toLocaleLowerCase("nl-NL").includes(needle)));
    return { people: people.map(p => ({ id: p.id, name: p.name, role: p.role, organization: p.organization, aliases: p.aliases, emails: p.emails,
      responsibilities: p.responsibilities ?? [], is_internal: p.isInternal ?? null })) };
  },

  async list_recordings() {
    const files = await recordingFiles();
    const known = new Set((await notes()).items.map(t => t.id));
    const filename = (path: string) => path.split(/[\\/]/).pop();
    // Task history is newest first, so the first match is the latest note made from the file.
    const history = useTaskHistory.getState().entries.filter(e => e.audio_path && known.has(e.transcript_id));
    return {
      recordings: files.map(f => ({
        filename: f.filename,
        size_bytes: f.size_bytes,
        created_at: new Date(f.created_at * 1000).toISOString(),
        duration_seconds: f.duration_seconds,
        note_id: history.find(e => filename(e.audio_path!) === f.filename)?.transcript_id ?? null,
      })),
    };
  },

  async get_glossary() {
    const store = usePersonalCorrectionsStore.getState();
    await store.hydrate();
    return { entries: usePersonalCorrectionsStore.getState().entries.map(e => ({ id: e.id, canonical: e.canonical, variants: e.variants, note: e.note ?? null, enabled: e.enabled })) };
  },

  async get_processing_status() {
    const active = useRecordingStore.getState().backgroundTasks.filter(t => !isFinished(t.status));
    const recent = useTaskHistory.getState().entries.slice(0, 20);
    return {
      active: active.map(t => ({ id: t.task_id, title: t.extracted_title || t.filename || null, status: t.status, progress: t.progress ?? null, error: t.error_message || null })),
      recent: recent.map(e => ({ id: e.id, title: e.title || null, status: e.status, note_id: e.transcript_id || null,
        created_at: e.created_at, finished_at: e.finished_at ?? null, error: e.error_message || null })),
    };
  },

  async create_note({ title, transcript, notule_markdown, tags, folder_id }: Args) {
    await notes();
    if (folder_id && !folderExists(folder_id)) throw new Error("Map niet gevonden. Gebruik list_library.");
    const now = new Date().toISOString();
    const html = notule_markdown ? markdownToHtml(notule_markdown) : "";
    const saved = await useLocalTranscriptsStore.getState().add({
      id: newLocalId(),
      title: title.trim(),
      raw_transcription: transcript ?? "",
      notule_html: html,
      has_notes: !!html.trim(),
      has_transcription: !!transcript?.trim(),
      duration_seconds: 0,
      tags: tags ?? [],
      created_at: now,
      updated_at: now,
      ...(folder_id ? { organization: { folderID: folder_id, automaticLabelIDs: [], suppressedLabelIDs: [] } } : {}),
    });
    return { id: saved.id, revision: await revisionOf(saved) };
  },

  async update_note({ id, revision, title, tags, folder_id, notule_markdown }: Args) {
    const note = await findNote(id);
    // ponytail: check and write are two queued steps; an app edit landing in between is overwritten.
    if (await revisionOf(note) !== revision) throw new Error(STALE);
    if (typeof folder_id === "string" && !folderExists(folder_id)) throw new Error("Map niet gevonden. Gebruik list_library.");
    const store = useLocalTranscriptsStore.getState();
    const patch: Partial<Transcript> = {};
    if (title !== undefined) patch.title = title.trim();
    if (tags !== undefined) patch.tags = tags;
    if (notule_markdown !== undefined) {
      patch.notule_html = markdownToHtml(notule_markdown);
      patch.has_notes = !!patch.notule_html.trim();
    }
    if (Object.keys(patch).length) await store.update(id, { ...patch, updated_at: new Date().toISOString() });
    if (folder_id !== undefined) await store.move([id], folder_id ?? undefined);
    return { id, revision: await revisionOf(await findNote(id)) };
  },

  async save_library_entry({ id, name, kind, description }: Args) {
    const { library, saveEntry } = await notes();
    const existing = id ? library.find(e => e.id === id) : undefined;
    if (id && !existing) throw new Error("Map of label niet gevonden. Gebruik list_library.");
    if (existing && existing.kind !== kind) throw new Error(`Dit item is een ${existing.kind === "smart" ? "slimme map" : existing.kind === "folder" ? "map" : "label"}.`);
    const entry = existing
      ? { ...existing, name, description: description ?? existing.description }
      : { id: crypto.randomUUID(), name, kind, description: description ?? "", automatic: false, labelIDs: [] };
    await saveEntry(entry);
    return { id: entry.id };
  },

  async save_person({ id, ...fields }: Args) {
    const store = usePeopleDirectoryStore.getState();
    if (id) {
      if (!store.people.some(p => p.id === id)) throw new Error("Persoon niet gevonden. Gebruik list_people.");
      await store.recordUpdate(id, SOURCE, fields);
      return { id };
    }
    const person = store.createDefaultPerson(fields);
    store.addPerson(person);
    return { id: person.id };
  },

  async add_glossary_term({ canonical, variants, note }: Args) {
    const entries = await usePersonalCorrectionsStore.getState().save(
      { id: crypto.randomUUID(), canonical: canonical.trim(), variants, scope: null, enabled: true, ...(note ? { note } : {}) }, SOURCE);
    const saved = entries[entries.length - 1];
    return { id: saved.id };
  },

  async regenerate_notule({ id, profile_id }: Args) {
    const note = await findNote(id);
    const profiles = useProfilesStore.getState().profiles;
    const profileId = profile_id ?? note.profile_id
      ?? profiles.find(p => p.name === note.profile_name || p.id === note.profile_name)?.id ?? profiles[0]?.id;
    const profile = findProfile(profileId);
    const taskId = regenerateTaskId(id);
    const busy = useRecordingStore.getState().backgroundTasks.find(t => t.task_id === taskId && !isFinished(t.status));
    if (busy) throw new Error("De notule wordt al opnieuw gemaakt. Volg het met get_processing_status.");
    if (!hasUsableTranscription(note.raw_transcription ?? "")) throw new Error("Geen bruikbare transcriptie beschikbaar.");
    void regenerateLocalNotule(note, profile);
    return { started: true, id, profile_id: profile.id };
  },

  async transcribe_recording({ filename, profile_id }: Args) {
    const settings = useSettingsStore.getState();
    if (settings.processing_mode !== "local") throw new Error("Transcriberen via de AI-koppeling werkt alleen met lokale verwerking.");
    if (liveRecordingFile() !== null) throw new Error("Er loopt een opname. Probeer het na het stoppen opnieuw.");
    const file = (await recordingFiles()).find(f => f.filename === filename);
    if (!file) throw new Error("Opname niet gevonden. Gebruik list_recordings.");
    const profile = findProfile(profile_id ?? settings.default_profile_id);
    // Same entry point as "Opnieuw verwerken" under Opgeslagen opnames.
    void processLocally(file.path, profile.id, settings.default_recording_mode, [], file.duration_seconds ?? 0);
    return { started: true, filename, profile_id: profile.id };
  },
};
