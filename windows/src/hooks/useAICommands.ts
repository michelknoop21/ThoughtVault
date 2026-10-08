import { useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { useAIConnection, loadAIConnection, commandAllowed, type AICommand } from "../services/aiConnections";
import { useLocalTranscriptsStore } from "../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useRecordingStore } from "../stores/recordingStore";
import { recordingAction } from "../services/recordingActions";
import { contentRevision, minutesDocument, validateDocumentStyle, type DocumentStyle } from "../services/documentStyle";
import { htmlToMarkdown } from "../utils/htmlToMarkdown";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export async function executeAICommand(command: AICommand, navigate: (path: string) => void): Promise<Record<string, unknown>> {
  const args = command.arguments;
  const local = useLocalTranscriptsStore.getState();
  await local.hydrate();
  const currentConnection = useAIConnection.getState().connection;
  if (!currentConnection || !commandAllowed(command, currentConnection)) throw Error("Opdracht is verlopen of niet meer toegestaan.");
  const items = useLocalTranscriptsStore.getState().items;
  const profiles = useProfilesStore.getState();
  const recording = useRecordingStore.getState();
  if (command.tool === "get_app_state") return { recording_phase: recording.phase, tasks: recording.backgroundTasks.map((task) => ({ id: task.task_id, status: task.status })) };
  if (command.tool === "list_transcripts") {
    const matches = items.filter((item) => `${item.title} ${item.tags.join(" ")}`.toLowerCase().includes(String(args.query ?? "").toLowerCase()));
    const offset = Number(args.offset ?? 0), limit = Number(args.limit ?? 20);
    if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(limit) || limit < 1 || limit > 100) throw Error("Ongeldige paginering.");
    return { total: matches.length, items: await Promise.all(matches.slice(offset, offset + limit).map(async (item) => ({ id: item.id, title: item.title, tags: item.tags, created_at: item.created_at, revision: await contentRevision(item) }))) };
  }
  if (command.tool === "list_profiles") return { profiles: profiles.profiles.map(({ id, name, is_default, isDefault }) => ({ id, name, is_default: is_default || isDefault })) };
  if (["get_profile", "save_profile"].includes(command.tool)) {
    const profile = profiles.getProfile(String(args.profile_id));
    if (!profile) throw Error("Profiel niet gevonden.");
    if (command.tool === "get_profile") return { ...profile, revision: await contentRevision(profile) };
    if (typeof args.name !== "string" || !args.name.trim() || args.name.length > 100 ||
      [args.system_prompt, args.notule_prompt, args.output_template].some((value) => typeof value !== "string" || value.length > 100000)) throw Error("Ongeldig profiel.");
    if (await contentRevision(profile) !== args.revision) throw Error("Profiel is gewijzigd. Lees het opnieuw.");
    const style = args.style ? validateDocumentStyle(args.style as DocumentStyle) : profile.document_style;
    const updated = { ...profile, id: profile.is_default || profile.isDefault ? crypto.randomUUID() : profile.id,
      name: String(args.name), system_prompt: String(args.system_prompt), notule_prompt: String(args.notule_prompt),
      output_template: String(args.output_template), notule_template: String(args.output_template), document_style: style, is_default: false, isDefault: false };
    // No await between the second revision check and the synchronous store write.
    if (profiles.getProfile(profile.id) !== profile) throw Error("Profiel is gewijzigd. Lees het opnieuw.");
    profiles.saveLocalProfile(updated);
    return { profile_id: updated.id, revision: await contentRevision(updated) };
  }
  if (command.tool === "open_view") {
    const routes: Record<string, string> = { recording: "/recording", transcripts: "/transcripts", transcript: "/transcripts", profiles: "/profiles", settings: "/settings" };
    const route = routes[String(args.view)];
    if (!route) throw Error("Onbekend scherm.");
    if (args.view === "transcript") {
      if (!items.some((item) => item.id === args.transcript_id)) throw Error("Transcript niet gevonden.");
      useTranscriptsStore.getState().setSelectedId(String(args.transcript_id));
    }
    navigate(route);
    const { getCurrentWindow } = await import("@tauri-apps/api/window");
    const window = getCurrentWindow();
    await window.show(); await window.unminimize(); await window.setFocus();
    return { ok: true };
  }
  if (command.tool.endsWith("_recording")) {
    if (command.tool === "start_recording") {
      if (!profiles.getProfile(String(args.profile_id))) throw Error("Profiel niet gevonden.");
      if (!["microphone", "combined"].includes(String(args.mode))) throw Error("Gebruik microfoon of gecombineerde audio op Windows.");
      if (recording.phase !== "idle") throw Error("Er is al een opname bezig.");
      recording.setSelectedProfileId(String(args.profile_id));
      recording.setMode(args.mode as "microphone" | "combined");
    }
    const actions = { start_recording: "start", pause_recording: "pause", resume_recording: "resume", stop_recording: "stop" } as const;
    const action = actions[command.tool as keyof typeof actions];
    if (!action) throw Error("Onbekende opnameactie.");
    await recordingAction(action);
    return { recording_phase: useRecordingStore.getState().phase };
  }
  const item = items.find((item) => item.id === args.transcript_id);
  if (!item) throw Error("Transcript niet gevonden.");
  if (command.tool === "get_transcript") {
    const offset = Number(args.offset ?? 0), limit = Number(args.limit ?? 16000);
    if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(limit) || limit < 1 || limit > 32000) throw Error("Ongeldig transcriptdeel.");
    const text = item.raw_transcription ?? "";
    return { id: item.id, title: item.title, tags: item.tags, text: text.slice(offset, offset + limit), total_length: text.length,
      next_offset: offset + limit < text.length ? offset + limit : null, revision: await contentRevision(item), minutes: item.notule_html, style: item.document_style };
  }
  if (["save_minutes", "update_transcript"].includes(command.tool)) {
    if (typeof args.revision !== "string" || !args.revision) throw Error("Lees eerst de revisie.");
    if (command.tool === "save_minutes" && (typeof args.html !== "string" || args.html.length > 1000000)) throw Error("Ongeldige notule.");
    if (command.tool === "update_transcript" && typeof args.title !== "string") throw Error("Ongeldige titel.");
    const style = args.style ? validateDocumentStyle(args.style as DocumentStyle) : item.document_style ?? validateDocumentStyle();
    const patch = command.tool === "save_minutes" ? {
      notule_html: minutesDocument(String(args.html), style), document_style: style, has_notes: true,
    } : { title: String(args.title), tags: args.tags as string[] };
    if (command.tool === "update_transcript" && (!patch.title?.trim() || patch.title.length > 300 || !Array.isArray(patch.tags) || patch.tags.length > 50 || patch.tags.some((tag) => typeof tag !== "string" || tag.length > 100))) throw Error("Ongeldige titel of tags.");
    await local.update(item.id, { ...patch, updated_at: new Date().toISOString() }, args.revision);
    const updated = useLocalTranscriptsStore.getState().items.find((record) => record.id === item.id)!;
    useTranscriptsStore.getState().updateTranscript(item.id, updated);
    return { id: item.id, revision: await contentRevision(updated) };
  }
  if (command.tool === "export_minutes") {
    const html = minutesDocument(item.notule_html ?? "", item.document_style);
    if (args.format === "pdf") return { html, style: item.document_style, title: item.title };
    if (args.format === "html") return { html, style: item.document_style, title: item.title };
    if (args.format === "markdown") return { content: htmlToMarkdown(html), mime_type: "text/markdown" };
    if (args.format === "txt") {
      const document = new DOMParser().parseFromString(html, "text/html");
      return { content: document.body.textContent ?? "", mime_type: "text/plain" };
    }
    throw Error("Onbekend exportformaat.");
  }
  throw Error("Onbekende opdracht.");
}

export function useAICommands() {
  const navigate = useNavigate();
  const navigateRef = useRef(navigate);
  navigateRef.current = navigate;
  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;
    // Listen before starting the endpoint, so the first request cannot be lost.
    void listen<AICommand>("local-mcp-command", async ({ payload: command }) => {
      const current = useAIConnection.getState().connection;
      let result: Record<string, unknown>;
      try {
        if (disposed || !current || !commandAllowed(command, current) ||
          !await invoke<boolean>("local_mcp_allowed", { token: current.credential, tool: command.tool, id: command.id })) throw Error("Lokale MCP-toegang ingetrokken.");
        result = await executeAICommand(command, path => navigateRef.current(path));
      } catch (error) { result = { error: error instanceof Error ? error.message : String(error) }; }
      await invoke("local_mcp_reply", { id: command.id, result });
    }).then(async fn => {
      if (disposed) { fn(); return; }
      unlisten = fn;
      await loadAIConnection().catch(() => useAIConnection.setState({ status: "Lokale MCP kon niet starten. Controleer of de poort vrij is." }));
    });
    return () => { disposed = true; unlisten?.(); };
  }, []);
}
