import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";

/** Only the path selected in the native save dialog is granted filesystem access. */
export async function saveTextExport(content: string, title: string, extension: "txt" | "md" | "html"): Promise<boolean> {
  const filename = title.replace(/[<>:"/\\|?*\u0000-\u001f]/gu, "_").replace(/[. ]+$/u, "").trim() || "notulen";
  const path = await save({ defaultPath: `${filename}.${extension}`, filters: [{ name: extension.toUpperCase(), extensions: [extension] }] });
  if (!path) return false;
  await writeTextFile(path, content);
  return true;
}
