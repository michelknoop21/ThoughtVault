import { beforeAll, describe, expect, it, vi } from "vitest";
import { Store } from "@tauri-apps/plugin-store";
import type { Transcript } from "../../../types";
import { useRecordingStore } from "../../../stores/recordingStore";
import { useSettingsStore } from "../../../stores/settingsStore";
import { useTaskHistory } from "../../taskHistory";
import { handleMessage, TOOLS } from "../router";
import { handlers, revisionOf, transcriptChunk } from "../tools";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async (command: string) => {
    if (command === "get_recordings_dir") return "C:\\rec";
    if (command === "list_recordings") return ["a.wav", "live.wav"].map(filename => ({ filename, path: `C:\\rec\\${filename}`, size_bytes: 1, created_at: 0, duration_seconds: 5 }));
    return null;
  }),
}));

const note = (id: string, created_at: string, extra: Partial<Transcript> = {}): Transcript =>
  ({ id, title: id, created_at, updated_at: created_at, duration_seconds: 60, tags: [], notule_html: "", raw_transcription: "", ...extra });

const notes = [
  note("local-a", "2026-11-01T09:00:00.000Z", { title: "Overleg Alfa", profile_id: "standaard", organization: { folderID: "f", automaticLabelIDs: [], suppressedLabelIDs: [] } }),
  note("local-b", "2026-11-10T09:00:00.000Z", { raw_transcription: "We bespraken het betaplan.", profile_id: "x", duration_seconds: 0, profile_name: "" }),
  note("local-c", "2026-11-20T09:00:00.000Z", { tags: ["Gamma"], notule_html: "<h2>Kop</h2><p>Tekst</p>", raw_transcription: "t".repeat(2500) }),
];

beforeAll(() => {
  const cache: Record<string, unknown> = { items: structuredClone(notes), library: [{ id: "f", name: "Werk", kind: "folder", labelIDs: [], description: "", automatic: false }] };
  vi.spyOn(Store, "load").mockImplementation(async () => ({
    get: vi.fn(async (key: string) => cache[key]),
    set: vi.fn(async (key: string, value: unknown) => { cache[key] = value; }),
    save: vi.fn(async () => {}),
  }) as unknown as Store);
});

async function call(name: string, args: Record<string, unknown>) {
  const line = await handleMessage(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }), { allowWrite: true, version: "1", handlers });
  return JSON.parse(line!).result as { isError?: boolean; content: { text: string }[]; structuredContent: any };
}
const ids = async (args: Record<string, unknown>) => (await call("list_notes", args)).structuredContent.notes.map((n: { id: string }) => n.id);

it("has exactly one handler per tool in tools.json", () => {
  expect(Object.keys(handlers).sort()).toEqual(TOOLS.map(t => t.name).sort());
});

describe("list_notes", () => {
  it("sorts newest first and pages", async () => {
    expect(await ids({})).toEqual(["local-c", "local-b", "local-a"]);
    const page = (await call("list_notes", { limit: 1, offset: 1 })).structuredContent;
    expect(page.total).toBe(3);
    expect(page.offset).toBe(1);
    expect(page.notes.map((n: { id: string }) => n.id)).toEqual(["local-b"]);
  });
  it("filters on text, tags, dates, folder and profile", async () => {
    expect(await ids({ query: "BETAPLAN" })).toEqual(["local-b"]);
    expect(await ids({ query: "gamma" })).toEqual(["local-c"]);
    expect(await ids({ from: "2026-11-05", to: "2026-11-10" })).toEqual(["local-b"]);
    expect(await ids({ to: "2026-11-01T08:00:00Z" })).toEqual([]);
    expect(await ids({ folder_id: "f" })).toEqual(["local-a"]);
    expect(await ids({ profile_id: "x" })).toEqual(["local-b"]);
  });
  it("returns metadata only", async () => {
    const first = (await call("list_notes", { limit: 1 })).structuredContent.notes[0];
    expect(first).toEqual({ id: "local-c", title: "local-c", created_at: "2026-11-20T09:00:00.000Z", duration_seconds: 60, profile_id: null, profile_name: null,
      tags: ["Gamma"], folder_id: null, has_notule: true, has_transcript: true });
  });
  it("reports unknown or empty values as null", async () => {
    const b = (await call("list_notes", { query: "betaplan" })).structuredContent.notes[0];
    expect(b).toMatchObject({ duration_seconds: null, profile_id: "x", profile_name: null, folder_id: null });
  });
  it("rejects an invalid date", async () => {
    expect((await call("list_notes", { from: "gisteren" })).isError).toBe(true);
  });
});

describe("get_note", () => {
  it("returns markdown minutes, a revision and transcript chunks", async () => {
    const first = (await call("get_note", { id: "local-c", max_chars: 1000 })).structuredContent;
    expect(first.notule).toContain("## Kop");
    expect(first.revision).toMatch(/^[0-9a-f]{16}$/);
    expect(first.revision).toBe(await revisionOf(notes[2]));
    expect(first.transcript).toMatchObject({ offset: 0, total_chars: 2500, next_offset: 1000 });
    expect(first.transcript.text).toHaveLength(1000);
    const last = (await call("get_note", { id: "local-c", max_chars: 1000, transcript_offset: 2000 })).structuredContent;
    expect(last.transcript).toMatchObject({ offset: 2000, next_offset: null });
    expect(last.transcript.text).toHaveLength(500);
    const html = (await call("get_note", { id: "local-c", format: "html", include_transcript: false })).structuredContent;
    expect(html.notule).toBe("<h2>Kop</h2><p>Tekst</p>");
    expect(html.transcript).toBeUndefined();
  });
  it("returns the note summary plus revision, participants and notule only", async () => {
    const note = (await call("get_note", { id: "local-b" })).structuredContent;
    expect(Object.keys(note)).toEqual(["id", "title", "created_at", "duration_seconds", "profile_id", "profile_name", "tags", "folder_id",
      "has_notule", "has_transcript", "revision", "participants", "notule", "transcript"]);
    expect(note.participants).toEqual([]);
    expect(note.transcript).toEqual({ text: "We bespraken het betaplan.", offset: 0, total_chars: 26, next_offset: null });
  });
  it("reports a missing note", async () => {
    expect((await call("get_note", { id: "local-zz" })).content[0].text).toBe("Notitie niet gevonden.");
  });
});

describe("update_note", () => {
  it("rejects a stale revision and applies only the given fields", async () => {
    const { revision } = (await call("get_note", { id: "local-a" })).structuredContent;
    const stale = await call("update_note", { id: "local-a", revision: "0000000000000000", title: "Nieuw" });
    expect(stale.isError).toBe(true);
    expect(stale.content[0].text).toBe("Notitie is intussen gewijzigd. Lees hem opnieuw met get_note.");

    const updated = (await call("update_note", { id: "local-a", revision, title: "Nieuw", folder_id: null, notule_markdown: "# Kop\n\n- punt" })).structuredContent;
    expect(updated.revision).not.toBe(revision);
    const after = (await call("get_note", { id: "local-a", format: "html" })).structuredContent;
    expect(after).toMatchObject({ title: "Nieuw", folder_id: null, profile_id: "standaard", revision: updated.revision });
    expect(after.notule).toContain("<li>punt</li>");
    expect((await call("update_note", { id: "local-a", revision, title: "Weer" })).isError).toBe(true);
  });
});

describe("transcriptChunk", () => {
  it("counts UTF-16 code units and never splits a surrogate pair", () => {
    const text = "ab\u{1F600}cd"; // the emoji is two code units at 2 and 3
    expect(transcriptChunk(text, 0, 3)).toEqual({ text: "ab", offset: 0, total_chars: 6, next_offset: 2 });
    expect(transcriptChunk(text, 2, 2)).toEqual({ text: "\u{1F600}", offset: 2, total_chars: 6, next_offset: 4 });
    expect(transcriptChunk(text, 4, 10)).toEqual({ text: "cd", offset: 4, total_chars: 6, next_offset: null });
  });
});

describe("write results", () => {
  it("save_library_entry returns only the id", async () => {
    const saved = (await call("save_library_entry", { name: "Klanten", kind: "folder" })).structuredContent;
    expect(Object.keys(saved)).toEqual(["id"]);
  });
});

describe("processing status", () => {
  it("lists active tasks and recent history with nulls for missing values", async () => {
    useRecordingStore.setState({ backgroundTasks: [{ task_id: "t1", status: "transcribing", progress: 40, mode: "combined", created_at: "2026-11-25T09:00:00Z" }] });
    useTaskHistory.setState({ entries: [{ id: "h1", title: "Overleg", created_at: "2026-11-24T09:00:00Z", status: "completed", transcript_id: "local-a", steps: [] }] });
    const status = (await call("get_processing_status", {})).structuredContent;
    expect(status).toEqual({
      active: [{ id: "t1", title: null, status: "transcribing", progress: 40, error: null }],
      recent: [{ id: "h1", title: "Overleg", status: "completed", note_id: "local-a", created_at: "2026-11-24T09:00:00Z", finished_at: null, error: null }],
    });
    useRecordingStore.setState({ backgroundTasks: [] });
  });
});

describe("live recording", () => {
  it("hides the file being recorded and refuses to transcribe meanwhile", async () => {
    useSettingsStore.setState({ processing_mode: "local" });
    useRecordingStore.setState({ phase: "recording", filePath: "C:\\rec\\live.wav" });
    const files = (await call("list_recordings", {})).structuredContent.recordings.map((r: { filename: string }) => r.filename);
    expect(files).toEqual(["a.wav"]);
    const refused = await call("transcribe_recording", { filename: "a.wav" });
    expect(refused.isError).toBe(true);
    expect(refused.content[0].text).toBe("Er loopt een opname. Probeer het na het stoppen opnieuw.");
    useRecordingStore.setState({ phase: "paused" });
    expect((await call("transcribe_recording", { filename: "a.wav" })).isError).toBe(true);
    useRecordingStore.setState({ phase: "idle", filePath: null });
    expect((await call("list_recordings", {})).structuredContent.recordings).toHaveLength(2);
  });
});
