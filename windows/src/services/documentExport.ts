import { save } from "@tauri-apps/plugin-dialog";
import { writeFile } from "@tauri-apps/plugin-fs";
import {
  wordDocument,
  type DocumentOptions,
} from "../../../shared/document/dist/document.mjs";
import type { Transcript } from "../types";
export function transcriptDocumentOptions(
  transcript: Transcript,
): DocumentOptions {
  const seconds = Math.floor(transcript.duration_seconds || 0);
  const duration =
    seconds >= 60
      ? `${Math.floor(seconds / 60)}m ${seconds % 60}s`
      : `${seconds}s`;
  const date = new Date(transcript.created_at).toLocaleDateString("nl-NL", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
  return {
    html: transcript.notule_html ?? "",
    title: transcript.title,
    branding: transcript.document_branding_json,
    subtitle: `${date} · ${duration}`,
  };
}
export async function saveWordExport(transcript: Transcript) {
  const name =
    (transcript.title || "Notulen")
      .replace(/[<>:"/\\|?*\u0000-\u001f]/gu, "_")
      .replace(/[. ]+$/u, "")
      .trim() || "Notulen";
  const path = await save({
    defaultPath: name + ".docx",
    filters: [{ name: "Word-document", extensions: ["docx"] }],
  });
  if (!path) return;
  const bytes = await wordDocument(transcriptDocumentOptions(transcript));
  await writeFile(path, bytes);
}
