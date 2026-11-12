import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { useSupportStore } from "../../stores/supportStore";
import { mask } from "../appLog";
import { failureFromTransition, fingerprint, initCrashReporter, markStage, processingDiagnostic, reportFailure, stageForStatus } from "../crashReporter";
import type { TaskStatus } from "../../types";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const enqueue = useSupportStore.getState().enqueue;
const flushQueue = vi.fn(async () => {});
const writes = () => vi.mocked(invoke).mock.calls.filter(([cmd]) => cmd === "log_write").map(([, args]) => args as { message: string; category: string });
beforeEach(() => {
  localStorage.clear();
  flushQueue.mockReset().mockResolvedValue(undefined);
  vi.mocked(invoke).mockReset().mockImplementation(async (cmd, args: any) => {
    if (cmd === "log_scrub") return `scrubbed(${args.text})`;
    if (cmd === "log_tail") return "x INFO [Klikpad] knop: Opnemen";
  });
  useSupportStore.setState({ queue: [], auto_report: true, enqueue, flushQueue });
});
afterEach(() => vi.restoreAllMocks());

it("uses canonical raw input with ASCII digits removed and the first 16 SHA256 hex characters", async () => {
  expect(await fingerprint("transcriberen", "Model niet geladen na 30 s (code 12)")).toBe("390655eba19539fc");
  expect(await fingerprint("transcriberen", "Model niet geladen na 45 s (code 7)")).toBe("390655eba19539fc");
  expect(await fingerprint("notule", "Model niet geladen na 30 s (code 12)")).toBe("f2990848e3a1a105");
});

it.each([
  ["OpenAI API-sleutel geweigerd.", "openai_unauthorized"],
  ["Anthropic API-limiet bereikt. Probeer later opnieuw.", "anthropic_rate_limited"],
  ["Ollama Cloud gaf een leeg antwoord.", "ollama_empty_response"],
  ["De notule-generator gaf een leeg concept.", "notule_empty_response"],
  ["De notule bevat geen bruikbare inhoud. Controleer de transcriptie en probeer opnieuw.", "notule_unusable_content"],
  ["OpenAI gaf HTTP 401.", "notule_http_unauthorized"],
  ["Anthropic gaf HTTP 429.", "notule_http_rate_limited"],
  ["Ollama Cloud gaf HTTP 404 voor model \"private\".", "notule_http_client_error"],
  ["Notule-generator op http://localhost:9 gaf HTTP 500 voor model \"private\".", "notule_http_server_error"],
])("classifies the complete known message without dynamic parameters: %s", (message, code) => {
  expect(processingDiagnostic(message)).toMatchObject({ code });
  expect(processingDiagnostic(message)?.shown).not.toContain("private");
  expect(processingDiagnostic(`Provider: ${message}`)).toBeNull();
  expect(processingDiagnostic(`${message} PRIVATE_BODY`)).toBeNull();
});

it.each(["__proto__", "constructor", "toString", "PRIVATE_BODY", "", "OpenAI gaf HTTP 999."])("rejects unknown bodies and inherited property names: %s", message => {
  expect(processingDiagnostic(message)).toBeNull();
});

it("maps every status and only reports a new failed or error transition", () => {
  const stages: Record<TaskStatus, string | null> = { pending: "transcriberen", queued: "transcriberen", uploading: "transcriberen", downloading: "transcriberen", converting: "transcriberen", transcribing: "transcriberen", paused: "transcriberen", generating: "notule", completed: null, failed: null, cancelled: null, error: null };
  for (const [status, stage] of Object.entries(stages)) expect(stageForStatus(status as TaskStatus)).toBe(stage);
  expect(failureFromTransition("transcribing", "failed", "x")).toEqual({ stage: "transcriberen", message: "x" });
  expect(failureFromTransition("generating", "error", "y")).toEqual({ stage: "notule", message: "y" });
  expect(failureFromTransition("uploading", "error")).toEqual({ stage: "transcriberen", message: "Onbekende fout" });
  expect(failureFromTransition("completed", "failed", "")).toEqual({ stage: "transcriberen", message: "Onbekende fout" });
  for (const prev of ["failed", "error"] as const) for (const next of ["failed", "error"] as const) expect(failureFromTransition(prev, next, "x")).toBeNull();
  expect(failureFromTransition("generating", "completed")).toBeNull();
  expect(failureFromTransition("transcribing", "failed", "Geannuleerd door gebruiker.")).toBeNull();
});

it("queues scrubbed metadata with raw fingerprint and opaque local logging", async () => {
  const error = "C:\\Users\\Jan\\Overleg.wav niet gevonden";
  await reportFailure("notule", "Notule maken mislukt", error);
  expect(useSupportStore.getState().queue[0]).toMatchObject({ kind: "auto", category: "BUG", stage: "notule", shownMessage: "scrubbed(Notule maken mislukt)", errorText: `scrubbed(${error})`, clickPath: ["scrubbed(knop: Opnemen)"], fingerprint: await fingerprint("notule", error) });
  expect(writes()).toContainEqual({ level: "error", category: "Fout", message: `notule: ${mask(error)}` });
  expect(writes().map(w => w.message).join(" ")).not.toContain("Jan");
  expect(flushQueue).toHaveBeenCalledTimes(1);
});

it("keeps arbitrary error contents out of the log even with auto reporting off", async () => {
  useSupportStore.setState({ auto_report: false });
  await reportFailure("opnemen", "Opname mislukt", "provider transcript body private meeting words");
  expect(useSupportStore.getState().queue).toEqual([]);
  expect(writes()[0].message).toMatch(/^opnemen: k-[a-f0-9]{6}$/);
  expect(invoke).not.toHaveBeenCalledWith("log_scrub", expect.anything());
  expect(flushQueue).not.toHaveBeenCalled();
});

it("scrubs full paths and e-mails before any payload cap, including Unicode limits", async () => {
  const path = `C:\\Users\\${"a".repeat(6100)}\\Overleg.wav`;
  const email = `${"b".repeat(6100)}@example.nl`;
  // Native scrubbing is separately covered by Rust tests; assert the IPC sees the complete secrets.
  vi.mocked(invoke).mockImplementation(async (cmd, args: any) => {
    if (cmd === "log_scrub") return args.text === path ? "k-path" : args.text === email ? "k-email" : args.text;
    if (cmd === "log_tail") return "";
  });
  await reportFailure("notule", path, email);
  expect(invoke).toHaveBeenCalledWith("log_scrub", { text: path });
  expect(invoke).toHaveBeenCalledWith("log_scrub", { text: email });
  expect(useSupportStore.getState().queue[0]).toMatchObject({ shownMessage: "k-path", errorText: "k-email" });
  await reportFailure("notule", "😀".repeat(6000), "😀".repeat(3000));
  const item = useSupportStore.getState().queue[1];
  expect(Array.from(item.shownMessage)).toHaveLength(5000);
  expect(Array.from(item.errorText)).toHaveLength(2000);
});

it.each(["log_scrub", "log_tail"])("handles %s IPC rejection without raw fallback", async command => {
  vi.mocked(invoke).mockImplementation(async (cmd, args: any) => {
    if (cmd === command) throw new Error("private raw IPC diagnostic");
    if (cmd === "log_scrub") return `scrubbed(${args.text})`;
    if (cmd === "log_tail") return "";
  });
  await expect(reportFailure("notule", "shown", "raw")).resolves.toBeUndefined();
  // Missing click-path logs are safe; failed scrubbing must suppress the entire report.
  expect(useSupportStore.getState().queue).toHaveLength(command === "log_scrub" ? 0 : 1);
});

it.each(["scrub", "hash", "clickpath"])("rechecks consent after waiting for %s", async pending => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  if (pending === "hash") {
    const digest = crypto.subtle.digest.bind(crypto.subtle);
    vi.spyOn(crypto.subtle, "digest").mockImplementation(async (...args) => { await gate; return digest(...args); });
  }
  vi.mocked(invoke).mockImplementation(async (cmd, args: any) => {
    if (cmd === "log_scrub") { if (pending === "scrub") await gate; return args.text; }
    if (cmd === "log_tail") { if (pending === "clickpath") await gate; return "x [Klikpad] knop: Opnemen"; }
  });
  const reporting = reportFailure("notule", "shown", "error");
  useSupportStore.getState().setAutoReport(false);
  release();
  await reporting;
  expect(useSupportStore.getState().queue).toEqual([]);
  expect(flushQueue).not.toHaveBeenCalled();
});

it("never throws on hash, enqueue or synchronous and asynchronous flush failures", async () => {
  vi.spyOn(crypto.subtle, "digest").mockRejectedValueOnce(new Error("hash unavailable"));
  await expect(reportFailure("crash", "shown", "raw")).resolves.toBeUndefined();
  expect(useSupportStore.getState().queue).toEqual([]);
  useSupportStore.setState({ enqueue: () => { throw new Error("storage unavailable"); } });
  await expect(reportFailure("crash", "shown", "raw")).resolves.toBeUndefined();
  useSupportStore.setState({ enqueue });
  flushQueue.mockImplementationOnce(() => { throw new Error("sync flush"); });
  await expect(reportFailure("crash", "shown", "raw")).resolves.toBeUndefined();
  flushQueue.mockRejectedValueOnce(new Error("async flush"));
  await expect(reportFailure("crash", "shown", "raw")).resolves.toBeUndefined();
  await Promise.resolve();
});

it("installs global hooks only once, logs opaque diagnostics and never queues or posts", async () => {
  const listen = vi.spyOn(window, "addEventListener");
  initCrashReporter(); initCrashReporter();
  expect(listen.mock.calls.filter(([type]) => type === "error")).toHaveLength(1);
  expect(listen.mock.calls.filter(([type]) => type === "unhandledrejection")).toHaveLength(1);
  window.dispatchEvent(new ErrorEvent("error", { message: "private meeting", filename: "secret file", error: new Error("private stack") }));
  const rejection = new Event("unhandledrejection");
  Object.defineProperty(rejection, "reason", { value: { toString: () => { throw new Error("do not inspect"); }, transcript: "private" } });
  window.dispatchEvent(rejection);
  expect(writes()).toHaveLength(2);
  expect(writes().every(w => w.category === "Onverwacht")).toBe(true);
  expect(writes().map(w => w.message).join(" ")).not.toMatch(/private|secret/);
  expect(useSupportStore.getState().queue).toEqual([]);
  expect(invoke).not.toHaveBeenCalledWith("proxy_request", expect.anything());
  expect(flushQueue).not.toHaveBeenCalled();
});

it("marks or clears the session stage and swallows IPC failures", async () => {
  await markStage("notule");
  expect(invoke).toHaveBeenLastCalledWith("session_stage", { stage: "notule" });
  await markStage(null);
  expect(invoke).toHaveBeenLastCalledWith("session_stage", { stage: null });
  vi.mocked(invoke).mockRejectedValueOnce(new Error("IPC"));
  await expect(markStage("opnemen")).resolves.toBeUndefined();
  vi.mocked(invoke).mockImplementationOnce(() => { throw new Error("sync IPC"); });
  await expect(markStage(null)).resolves.toBeUndefined();
});
