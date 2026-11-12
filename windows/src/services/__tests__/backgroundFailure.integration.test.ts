import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { useRecordingStore } from "../../stores/recordingStore";
import { useSupportStore } from "../../stores/supportStore";
import { installClickPath, logRoute } from "../appLog";
import { fingerprint } from "../crashReporter";
import { processLocally } from "../localPipeline";
import { LLMService } from "../llm";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn() }));
const sent: any[] = [];
const logs: string[] = [];
const canary = "CANARY_NOTE CANARY_TITLE private@example.com C:\\Users\\Private\\meeting.wav";
const connection = (details: string) => `Kan de notule-generator niet bereiken op ${details} (model "${details}"). Draait Ollama/LM Studio en klopt de URL in Instellingen?`;

beforeEach(() => {
  localStorage.clear(); sent.length = 0; logs.length = 0;
  useRecordingStore.setState({ backgroundTasks: [] });
  useSupportStore.setState({ queue: [], auto_report: true, name: "Synthetic", email: "support@example.com" });
  vi.mocked(invoke).mockReset().mockImplementation(async (cmd, args: any) => {
    if (cmd === "log_write") { logs.push(`[${args.category}] ${args.message}`); return; }
    if (cmd === "log_tail") return logs.join("\n");
    if (cmd === "log_scrub") return args.text;
    if (cmd === "load_credential") return "A".repeat(43);
    if (cmd === "get_app_version") return "1.0.314";
    if (cmd === "get_system_specs") return { cpu: "Synthetic", memory_gb: 16, os_version: "Windows 11" };
    if (cmd === "proxy_request") {
      if (args.request.url.endsWith("/reports")) sent.push(JSON.parse(args.request.body));
      return { status: 200, body: JSON.stringify({ ticketId: "t", ref: "TV-1", repeated: false, count: 1, logAttached: true }) };
    }
  });
});
afterEach(() => vi.restoreAllMocks());

async function fail(message: string, status: "failed" | "error" = "failed") {
  const id = crypto.randomUUID();
  const state = useRecordingStore.getState();
  state.addBackgroundTask({ task_id: id, status: "generating", progress: 55, mode: "combined", created_at: new Date().toISOString() });
  state.updateBackgroundTask(id, { status, error_message: message });
  await vi.waitFor(() => expect(sent).toHaveLength(useRecordingStore.getState().backgroundTasks.length));
  return useRecordingStore.getState().backgroundTasks.find(task => task.task_id === id)!;
}

it("uploads the same safe explanation shown for known causes, separating causes and retaining repetition keys", async () => {
  const task = await fail(connection("http://127.0.0.1:9"));
  expect(task.error_message).toBe("Kan de notule-generator niet bereiken. Controleer of Ollama/LM Studio draait en controleer de URL bij Instellingen.");
  expect(sent[0]).toMatchObject({ stage: "notule", shownMessage: task.error_message, errorText: "notule_connection_failed" });
  await fail("Notule-generator op http://localhost:1234 gaf HTTP 503 voor model \"local\".", "error");
  await fail(connection("http://127.0.0.1:9"));
  expect(sent[1].errorText).toBe("notule_http_server_error");
  expect(sent[0].fingerprint).not.toBe(sent[1].fingerprint);
  expect(sent[0].fingerprint).toBe(sent[2].fingerprint);
  expect(sent[0].fingerprint).toBe(await fingerprint("notule", "notule_connection_failed"));
});

it("never sends private prose from arbitrary provider bodies or from known-template parameters, logs or content clicks", async () => {
  installClickPath();
  document.body.innerHTML = `<div class="prose"><button aria-label="${canary}" data-log-label="${canary}">${canary}</button></div>`;
  document.querySelector("button")!.click(); logRoute(`/transcripts/${canary}`);
  const unknown = await fail(canary);
  expect(unknown.error_message).toBe(canary);
  expect(sent[0]).toMatchObject({ shownMessage: "Verwerking mislukt", errorText: "background_task_failed" });
  const known = await fail(connection(canary));
  expect(known.error_message).not.toContain("CANARY");
  expect(sent[1].shownMessage).toBe(known.error_message);
  await fail(`OpenAI gaf HTTP 503. ${canary}`);
  expect(sent[2].errorText).toBe("background_task_failed");
  expect(JSON.stringify({ sent, logs, ipc: vi.mocked(invoke).mock.calls })).not.toMatch(/CANARY|private@example\.com|Private|meeting\.wav/);
});

it("normalizes known UI causes with consent off without uploading or scrubbing", async () => {
  useSupportStore.setState({ auto_report: false });
  const state = useRecordingStore.getState();
  state.addBackgroundTask({ task_id: "off", status: "generating", progress: 55, mode: "combined", created_at: "2026-11-11" });
  state.updateBackgroundTask("off", { status: "failed", error_message: connection(canary) });
  expect(useRecordingStore.getState().backgroundTasks[0].error_message).toContain("Controleer of Ollama/LM Studio draait");
  await Promise.resolve();
  expect(sent).toEqual([]);
  expect(useSupportStore.getState().queue).toEqual([]);
  expect(invoke).not.toHaveBeenCalledWith("log_scrub", expect.anything());
});

it.each([connection(canary), canary])("keeps local-pipeline console output and outbound diagnostics safe", async error => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  const partial = { id: "local", title: canary, raw_transcription: canary, notule_html: "", has_notes: false,
    has_transcription: true, duration_seconds: 12, tags: [], created_at: "2026-11-11", updated_at: "2026-11-11" };
  useLocalTranscriptsStore.setState({ items: [partial] });
  vi.spyOn(LLMService, "generateNotulen").mockRejectedValue(new Error(error));
  await processLocally("C:\\Users\\Private\\meeting.wav", "standaard", "combined", [], 12, "local");
  await vi.waitFor(() => expect(sent).toHaveLength(1));
  const task = useRecordingStore.getState().backgroundTasks[0];
  expect(task.status).toBe("failed");
  expect(sent[0].shownMessage).toBe(error === canary ? "Verwerking mislukt" : task.error_message);
  expect(useLocalTranscriptsStore.getState().items[0]).toEqual(partial);
  expect(JSON.stringify({ sent, logs, console: consoleError.mock.calls, ipc: vi.mocked(invoke).mock.calls })).not.toMatch(/CANARY|private@example\.com|Private|meeting\.wav/);
});
