// @vitest-environment jsdom
import { beforeEach, expect, it, vi } from "vitest";
import { prepareMerge, MAX_MERGE_CHARACTERS } from "../notuleMergeSource";
import { mergeNotulen } from "../mergeNotulen";
import { LLMService } from "../llm";
import { api } from "../api";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import { useRecordingStore } from "../../stores/recordingStore";
import type { Transcript } from "../../types";

vi.mock("../llm", () => ({ LLMService: { generateNotulen: vi.fn() } }));
vi.mock("../api", () => ({ api: { getTranscript: vi.fn(), getTranscriptNotes: vi.fn() } }));
const html = "<h1>Planning en besluiten</h1><p>Sam controleert vrijdag de definitieve planning.</p>";
const note = (id: string, day = "01", content = html): Transcript => ({ id, title: id, notule_html: content,
  raw_transcription: "Oude transcriptie niet gebruiken", tags: [], duration_seconds: 0,
  created_at: `2026-11-${day}T10:00:00Z`, updated_at: "" });
const a = note("local-a"), b = note("local-b", "02");
let add = vi.fn();
beforeEach(() => {
  vi.clearAllMocks();
  add = vi.fn().mockResolvedValue(undefined);
  useLocalTranscriptsStore.setState({ items: [a, b], hydrate: vi.fn().mockResolvedValue(undefined), add });
  useTranscriptsStore.setState({ transcripts: [a, b] });
  useRecordingStore.setState({ backgroundTasks: [] });
  vi.mocked(LLMService.generateNotulen).mockResolvedValue(html);
});
it("uses edited HTML, not old transcripts, and sorts multiple sources stably", () => {
  const edited = note("local-a", "01", "<style>secret</style><p>Gewijzigd besluit &amp; unieke actie voor Sam.</p>");
  const c = note("local-c", "02");
  const snapshot = prepareMerge([c, b, edited, edited]);
  expect(snapshot).toEqual(prepareMerge([b, edited, c]));
  expect(snapshot.sources.map(s => s.id)).toEqual([a.id, b.id, c.id]);
  expect(snapshot.text).toContain("Gewijzigd besluit & unieke actie");
  expect(snapshot.text).not.toMatch(/Oude transcriptie|<p>|secret/);
});
it("requires distinct usable sources and never silently truncates", () => {
  expect(() => prepareMerge([a, a])).toThrow(/twee/);
  expect(() => prepareMerge([a, note("b", "02", "<p></p>")])).toThrow(/bruikbare/);
  expect(() => prepareMerge([a, note("b", "02", "x".repeat(MAX_MERGE_CHARACTERS))])).toThrow(/groot/);
});
it("fetches current server details and saves a new record with immutable provenance", async () => {
  const server = note("server", "03", "<p>Nieuw handmatig besluit: Sam sluit het project.</p>");
  vi.mocked(api.getTranscript).mockResolvedValue(server);
  const merged = await mergeNotulen([a.id, "server"], "standaard");
  expect(api.getTranscript).toHaveBeenCalledWith("server");
  expect(merged.raw_transcription).toContain("Nieuw handmatig besluit");
  expect(merged.merge_sources?.map(s => s.id)).toEqual([a.id, "server"]);
  expect(merged.duration_seconds).toBe(0);
  expect(add).toHaveBeenCalledWith(merged);
  expect(LLMService.generateNotulen).toHaveBeenCalledWith(merged.raw_transcription, expect.objectContaining({ id: "standaard" }), undefined, [], "", expect.any(Function), expect.anything(), true, expect.any(AbortSignal));
  expect(useTranscriptsStore.getState().transcripts).toEqual([merged, a, b]);
});
it("does not generate when a server source cannot load", async () => {
  vi.mocked(api.getTranscript).mockRejectedValue(new Error("Geen verbinding"));
  await expect(mergeNotulen([a.id, "server"], "standaard")).rejects.toThrow("Geen verbinding");
  expect(LLMService.generateNotulen).not.toHaveBeenCalled();
  expect(add).not.toHaveBeenCalled();
});
for (const stage of ["generation", "storage"]) it(`leaves originals intact on ${stage} failure`, async () => {
  if (stage === "generation") vi.mocked(LLMService.generateNotulen).mockRejectedValue(new Error("Model mislukt"));
  else add.mockRejectedValue(new Error("Opslag mislukt"));
  await expect(mergeNotulen([a.id, b.id], "standaard")).rejects.toThrow(/mislukt/);
  expect(useTranscriptsStore.getState().transcripts).toEqual([a, b]);
  expect(useRecordingStore.getState().backgroundTasks[0].status).toBe("failed");
});
it("prevents duplicate starts and discards a cancelled generation", async () => {
  let finish!: (html: string) => void;
  vi.mocked(LLMService.generateNotulen).mockImplementation(() => new Promise(resolve => { finish = resolve; }));
  const pending = mergeNotulen([a.id, b.id], "standaard");
  await vi.waitFor(() => expect(finish).toBeTypeOf("function"));
  await expect(mergeNotulen([a.id, b.id], "standaard")).rejects.toThrow(/al bezig/);
  const id = useRecordingStore.getState().backgroundTasks[0].task_id;
  useRecordingStore.getState().cancelBackgroundTask(id);
  finish(html);
  await expect(pending).rejects.toThrow(/geannuleerd/);
  expect(add).not.toHaveBeenCalled();
  expect(useTranscriptsStore.getState().transcripts).toEqual([a, b]);
});

it("loads missing linked notes before generating and fails closed on linked-note errors", async () => {
  vi.mocked(api.getTranscript).mockResolvedValue(note("server", "03", ""));
  vi.mocked(api.getTranscriptNotes).mockResolvedValue(html);
  const result = await mergeNotulen([a.id, "server"], "standaard");
  expect(api.getTranscriptNotes).toHaveBeenCalledWith("server");
  expect(result.raw_transcription).toContain("Sam controleert vrijdag");
  vi.mocked(LLMService.generateNotulen).mockClear();
  vi.mocked(api.getTranscriptNotes).mockRejectedValue(new Error("Bron ophalen mislukt"));
  await expect(mergeNotulen([a.id, "server"], "standaard")).rejects.toThrow("Bron ophalen mislukt");
  expect(LLMService.generateNotulen).not.toHaveBeenCalled();
});
