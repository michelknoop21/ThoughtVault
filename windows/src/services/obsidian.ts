import { invoke } from "@tauri-apps/api/core";
import type { Transcript, AppSettings } from "../types";
import { htmlToMarkdown } from "../utils/htmlToMarkdown";
import { loadCredential } from "./tauriCommands";
import DOMPurify from "dompurify";
import { marked } from "marked";

type ObsidianResponse = { status: number; body: string; headers: Record<string, string> };

/** Lowercase, hyphen-separated slug: keeps letters/digits, everything else → "-". */
function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "");
}

/** yyyy-MM-dd derived from an ISO timestamp (local time); falls back to today. */
function dateOnly(iso: string): string {
  const parsed = new Date(iso);
  const d = isNaN(parsed.getTime()) ? new Date() : parsed;
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/** Escape embedded double-quotes for a YAML frontmatter quoted string. */
function escapeQuotes(value: string): string {
  return value.replace(/"/g, '\\"');
}

/**
 * Build the Obsidian note for a transcript: YAML frontmatter (participants block
 * omitted — Windows transcripts have no participants) followed by the markdown
 * body. Shared note format, must match the macOS side.
 */
export function buildObsidianNote(transcript: Transcript): { filename: string; markdown: string } {
  const date = dateOnly(transcript.created_at);
  const rawTitle = (transcript.title ?? "").trim();
  const noteId = transcript.task_id || transcript.id;
  const filename = `${date}-${slugify(noteId)}.md`;

  const lines: string[] = ["---"];
  lines.push("type: notulen");
  lines.push(`thoughtvault_id: "${escapeQuotes(noteId)}"`);
  lines.push(`title: "${escapeQuotes(rawTitle)}"`);
  lines.push(`date: ${date}`);
  const tags = ["notule", ...transcript.tags].map((t) => t.replace(/,/g, " "));
  lines.push(`tags: [${tags.join(", ")}]`);
  if (transcript.profile_name) {
    lines.push(`profile: "${escapeQuotes(transcript.profile_name)}"`);
  }
  lines.push("source: ThoughtVault");
  lines.push("---");

  const body = htmlToMarkdown(transcript.notule_html ?? "");
  const markdown = `${lines.join("\n")}\n\n${body}\n`;

  return { filename, markdown };
}

function checksum(value: string): string {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(value)) {
    hash = ((hash ^ BigInt(byte)) * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return hash.toString(16);
}

function snapshotKey(id: string): string { return `obsidian-sync-${id}`; }

function snapshot(id: string): { remote: string; app: string } | null {
  try { return JSON.parse(localStorage.getItem(snapshotKey(id)) ?? "null"); }
  catch { return null; }
}

function remember(id: string, markdown: string, html: string): void {
  localStorage.setItem(snapshotKey(id), JSON.stringify({ remote: checksum(markdown), app: checksum(html) }));
}

async function readNote(filename: string, settings: AppSettings, apiKey: string): Promise<ObsidianResponse> {
  return invoke<ObsidianResponse>("obsidian_get", {
    baseUrl: settings.obsidian_base_url, apiKey, vaultPath: settings.obsidian_vault_path, filename,
  });
}

/** Write a transcript's notule to the configured Obsidian vault. */
export async function exportToObsidian(transcript: Transcript, settings: AppSettings): Promise<void> {
  const apiKey = await loadCredential("obsidian_api_key");
  if (!apiKey || !settings.obsidian_vault_path) {
    throw new Error("Vul eerst de Obsidian instellingen in");
  }
  if (!transcript.notule_html) {
    throw new Error("Geen notule om te exporteren");
  }

  const { filename, markdown } = buildObsidianNote(transcript);

  const remote = await readNote(filename, settings, apiKey);
  const noteId = transcript.task_id || transcript.id;
  const previous = snapshot(noteId);
  if (remote.status === 200) {
    if (remote.body === markdown) {
      remember(noteId, markdown, transcript.notule_html);
      return;
    }
    if (!previous || previous.remote !== checksum(remote.body)) {
      throw new Error("Deze notule is gewijzigd in Obsidian. Haal die versie eerst op voordat je exporteert.");
    }
  } else if (remote.status !== 404) {
    throw new Error(`Obsidian lezen mislukt (status ${remote.status})`);
  }

  const res = await invoke<ObsidianResponse>("obsidian_put", {
    baseUrl: settings.obsidian_base_url,
    apiKey,
    vaultPath: settings.obsidian_vault_path,
    filename,
    markdown,
  });

  if (res.status >= 300) {
    throw new Error(`Obsidian gaf status ${res.status}`);
  }
  remember(noteId, markdown, transcript.notule_html);
}

/** Fetch an externally edited note; the caller saves it before acknowledging the import. */
export async function importFromObsidian(transcript: Transcript, settings: AppSettings): Promise<{ html: string; markdown: string }> {
  const apiKey = await loadCredential("obsidian_api_key");
  if (!apiKey) throw new Error("Vul eerst de Obsidian API-sleutel in");
  let remote = await readNote(buildObsidianNote(transcript).filename, settings, apiKey);
  if (remote.status === 404) {
    const titleSlug = slugify((transcript.title ?? "").trim());
    const legacy = `${dateOnly(transcript.created_at)}-${titleSlug || "notule"}.md`;
    remote = await readNote(legacy, settings, apiKey);
  }
  if (remote.status !== 200) throw new Error(`Obsidian-notule niet gevonden (status ${remote.status})`);
  const body = remote.body.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, "").trim();
  return { html: DOMPurify.sanitize(marked.parse(body, { async: false }) as string), markdown: remote.body };
}

export function acknowledgeObsidianImport(transcript: Transcript, markdown: string, html: string): void {
  remember(transcript.task_id || transcript.id, markdown, html);
}

/** Verify the Obsidian Local REST API is reachable and authenticated. */
export async function testObsidian(settings: AppSettings): Promise<void> {
  const apiKey = await loadCredential("obsidian_api_key");
  if (!apiKey) throw new Error("Vul eerst de Obsidian API-sleutel in");
  const res = await invoke<ObsidianResponse>("obsidian_test", {
    baseUrl: settings.obsidian_base_url,
    apiKey,
  });

  // The plugin returns pretty-printed JSON (`"authenticated": true`), so match
  // whitespace-tolerantly rather than on an exact substring.
  const authenticated = /"authenticated"\s*:\s*true/.test(res.body);
  if (res.status >= 300 || !authenticated) {
    throw new Error(
      res.status < 300 ? "API-sleutel niet geaccepteerd" : `Verbinding mislukt (status ${res.status})`,
    );
  }
}
