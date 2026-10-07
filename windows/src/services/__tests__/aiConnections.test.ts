import { beforeEach, expect, it, vi } from "vitest";
import { webcrypto } from "node:crypto";
import { commandAllowed, disconnectAIConnection, useAIConnection, type AICommand, type DeviceConnection } from "../aiConnections";
import { executeAICommand } from "../../hooks/useAICommands";
import { htmlToMarkdown } from "../../utils/htmlToMarkdown";
import { contentRevision, minutesDocument, validateDocumentStyle } from "../documentStyle";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useProfilesStore } from "../../stores/profilesStore";
import { useRecordingStore } from "../../stores/recordingStore";
import { recordingAction } from "../recordingActions";
import type { Transcript } from "../../types";

const mocks = vi.hoisted(() => ({
  set: vi.fn().mockResolvedValue(undefined), save: vi.fn().mockResolvedValue(undefined),
  invoke: vi.fn().mockResolvedValue("C:\\recording.wav"), emit: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@tauri-apps/plugin-store", () => ({ Store: { load: vi.fn().mockResolvedValue({ get: vi.fn().mockResolvedValue([]), set: mocks.set, save: mocks.save }) } }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke }));
vi.mock("@tauri-apps/api/event", () => ({ emit: mocks.emit }));
vi.mock("../../hooks/useWidgetWindow", () => ({ openWidgetWindow: vi.fn().mockResolvedValue(undefined), closeWidgetWindow: vi.fn().mockResolvedValue(undefined) }));

const item: Transcript = { id: "local-meeting", title: "Meeting", raw_transcription: "Een besluit.", notule_html: "<p>Begin</p>", tags: [], duration_seconds: 20, created_at: "2026-10-07", updated_at: "2026-10-07" };
const connection: DeviceConnection = { device_id: "desktop", credential: "secret", scopes: ["read"], user_id: "alice" };
const command: AICommand = { id: "cmd", device_id: "desktop", scope: "read", expires_at: Date.now() / 1000 + 45, tool: "get_transcript", arguments: {} };

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("crypto", webcrypto);
  mocks.save.mockResolvedValue(undefined);
  useLocalTranscriptsStore.setState({ items: [item] });
  useRecordingStore.getState().reset();
});

it("checks device, deadline and actual tool permission independently of the supplied scope", () => {
  expect(commandAllowed(command, connection)).toBe(true);
  expect(commandAllowed({ ...command, device_id: "other" }, connection)).toBe(false);
  expect(commandAllowed({ ...command, expires_at: Date.now() / 1000 - 1 }, connection)).toBe(false);
  expect(commandAllowed({ ...command, tool: "start_recording" }, connection)).toBe(false);
  expect(commandAllowed({ ...command, tool: "save_minutes" }, connection)).toBe(false);
  expect(commandAllowed(command, { ...connection, scopes: [] })).toBe(false);
});

it("disconnects locally without contacting the removed account backend", async () => {
  mocks.invoke.mockResolvedValue(undefined);
  useAIConnection.setState({ connection: { ...connection, scopes: ["read", "write", "record"] } });
  await disconnectAIConnection();
  expect(useAIConnection.getState().connection).toBeNull();
  expect(mocks.invoke).toHaveBeenCalledWith("local_mcp_stop");
  expect(mocks.invoke.mock.calls.some(([name]) => name === "proxy_request")).toBe(false);
});

it("validates styling and removes scripts, CSS and remote resources while preserving tables", () => {
  expect(() => validateDocumentStyle({ font: "url(https://evil)" as "Arial" })).toThrow();
  expect(() => validateDocumentStyle({ text_color: "red; background:url(https://evil)" })).toThrow();
  expect(() => validateDocumentStyle({ size: NaN })).toThrow();
  const html = minutesDocument('<style>@import "https://evil";</style><script>steal()</script><img src="file:///secret"><table><tr><td onclick="steal()">Besluit</td></tr></table>', { font: "Georgia", orientation: "landscape" });
  expect(html).toContain("Georgia"); expect(html).toContain("A4 landscape"); expect(html).toContain("<table>");
  expect(html).not.toMatch(/<script|<img|onclick|@import/);
});

it("serializes conflicting writes and only publishes successfully persisted edits", async () => {
  await useLocalTranscriptsStore.getState().hydrate();
  useLocalTranscriptsStore.setState({ items: [item] });
  const revision = await contentRevision(item);
  const first = useLocalTranscriptsStore.getState().update(item.id, { title: "First" }, revision);
  const second = useLocalTranscriptsStore.getState().update(item.id, { title: "Second" }, revision);
  await first;
  await expect(second).rejects.toThrow("gewijzigd");
  expect(useLocalTranscriptsStore.getState().items[0].title).toBe("First");
  mocks.save.mockRejectedValueOnce(Error("disk full"));
  await expect(useLocalTranscriptsStore.getState().update(item.id, { title: "Lost" })).rejects.toThrow("disk full");
  expect(useLocalTranscriptsStore.getState().items[0].title).toBe("First");
});

it("persists profile styling and rejects storage errors before publishing the profile", () => {
  const profile = { id: "own", name: "Eigen", document_style: validateDocumentStyle({ font: "Georgia" }), is_default: false };
  useProfilesStore.getState().saveLocalProfile(profile);
  expect(JSON.parse(localStorage.getItem("profiles-store")!).state.localProfiles.find((p: { id: string }) => p.id === "own").document_style.font).toBe("Georgia");
  const setItem = vi.spyOn(localStorage, "setItem").mockImplementationOnce(() => { throw Error("quota"); });
  expect(() => useProfilesStore.getState().saveLocalProfile({ ...profile, name: "Lost" })).toThrow("quota");
  expect(useProfilesStore.getState().getProfile("own")?.name).toBe("Eigen");
  setItem.mockRestore();
});

it("reserves a recording transition once and restores the previous phase on a failed pause", async () => {
  let finish: (value: unknown) => void = () => {};
  mocks.invoke.mockImplementationOnce(() => new Promise((resolve) => { finish = resolve; }));
  const start = recordingAction("start");
  await expect(recordingAction("start")).rejects.toThrow("bezig");
  finish("C:\\Recordings");
  await start;
  expect(useRecordingStore.getState().phase).toBe("recording");
  mocks.invoke.mockRejectedValueOnce(Error("device error"));
  await expect(recordingAction("pause")).rejects.toThrow("device error");
  expect(useRecordingStore.getState().phase).toBe("recording");
  await recordingAction("pause");
  expect(useRecordingStore.getState().phase).toBe("paused");
  await recordingAction("resume");
  await recordingAction("stop");
  await expect(recordingAction("stop")).rejects.toThrow("opnamefase");
  expect(mocks.invoke.mock.calls.filter(([name]) => name === "stop_recording")).toHaveLength(1);
});

it("reads a transcript, saves styled minutes and exports all formats without repeating a stale write", async () => {
  await useLocalTranscriptsStore.getState().hydrate();
  useLocalTranscriptsStore.setState({ items: [item] });
  useAIConnection.setState({ connection: { ...connection, scopes: ["read", "write"] } });
  const navigate = vi.fn();
  const get = await executeAICommand({ ...command, arguments: { transcript_id: item.id } }, navigate);
  const saved = await executeAICommand({ ...command, tool: "save_minutes", scope: "write", arguments: {
    transcript_id: item.id, revision: get.revision, html: '<h2>Besluit</h2><p>Maandag starten.</p><script>steal()</script>', style: { font: "Georgia" },
  } }, navigate);
  expect(saved.revision).not.toBe(get.revision);
  expect(useLocalTranscriptsStore.getState().items[0].document_style?.font).toBe("Georgia");
  for (const format of ["html", "markdown", "txt", "pdf"]) {
    const exported = await executeAICommand({ ...command, tool: "export_minutes", arguments: { transcript_id: item.id, format } }, navigate);
    expect(JSON.stringify(exported)).toContain("Maandag starten.");
    expect(JSON.stringify(exported)).not.toContain("<script");
    if (format === "pdf") expect(exported.style).toMatchObject({ font: "Georgia" });
  }
  await expect(executeAICommand({ ...command, tool: "update_transcript", scope: "write", arguments: { transcript_id: item.id, revision: get.revision, title: "Stale", tags: [] } }, navigate)).rejects.toThrow("gewijzigd");
});

it("keeps table columns and escaped pipes in Markdown exports", () => {
  const result = htmlToMarkdown('<table><tr><th>Actie</th><th>Eigenaar</th></tr><tr><td>Start | stop</td><td>José</td></tr></table>');
  expect(result).toContain("| Actie | Eigenaar |");
  expect(result).toContain("| --- | --- |");
  expect(result).toContain("| Start \\| stop | José |");
});
