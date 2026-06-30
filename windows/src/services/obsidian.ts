import { invoke } from "@tauri-apps/api/core";
import type { Transcript, AppSettings } from "../types";
import { htmlToMarkdown } from "../utils/htmlToMarkdown";

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
  const slug = slugify(rawTitle);
  const filename = slug ? `${date}-${slug}.md` : `${date}-notule.md`;

  const lines: string[] = ["---"];
  lines.push("type: notulen");
  lines.push(`title: "${escapeQuotes(rawTitle)}"`);
  lines.push(`date: ${date}`);
  const tags = ["notule", ...transcript.tags].map((t) => t.replace(/,/g, " "));
  lines.push(`tags: [${tags.join(", ")}]`);
  if (transcript.profile_name) {
    lines.push(`profile: "${escapeQuotes(transcript.profile_name)}"`);
  }
  lines.push("source: TranscriptStudio");
  lines.push("---");

  const body = htmlToMarkdown(transcript.notule_html ?? "");
  const markdown = `${lines.join("\n")}\n\n${body}\n`;

  return { filename, markdown };
}

/** Write a transcript's notule to the configured Obsidian vault. */
export async function exportToObsidian(transcript: Transcript, settings: AppSettings): Promise<void> {
  if (!settings.obsidian_api_key || !settings.obsidian_vault_path) {
    throw new Error("Vul eerst de Obsidian instellingen in");
  }
  if (!transcript.notule_html) {
    throw new Error("Geen notule om te exporteren");
  }

  const { filename, markdown } = buildObsidianNote(transcript);

  const res = await invoke<ObsidianResponse>("obsidian_put", {
    baseUrl: settings.obsidian_base_url,
    apiKey: settings.obsidian_api_key,
    vaultPath: settings.obsidian_vault_path,
    filename,
    markdown,
  });

  if (res.status >= 300) {
    throw new Error(`Obsidian gaf status ${res.status}`);
  }
}

/** Verify the Obsidian Local REST API is reachable and authenticated. */
export async function testObsidian(settings: AppSettings): Promise<void> {
  const res = await invoke<ObsidianResponse>("obsidian_test", {
    baseUrl: settings.obsidian_base_url,
    apiKey: settings.obsidian_api_key,
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
