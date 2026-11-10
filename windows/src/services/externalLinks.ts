import type { MouseEvent } from "react";
import { open } from "@tauri-apps/plugin-shell";
import { useToast } from "../components/ui/InfoBar";

export function externalLinkUrl(href: string): string | null {
  if (/[\u0000-\u001f\u007f]/.test(href)) return null;
  try {
    const url = new URL(href);
    if (url.protocol === "mailto:") return url.href;
    if ((url.protocol === "http:" || url.protocol === "https:") && url.hostname && !url.username && !url.password) return url.href;
  } catch { /* Relative and malformed URLs are not external links. */ }
  return null;
}

export function openNoteLink(event: MouseEvent<HTMLElement>): void {
  if (event.button !== 0 && event.button !== 1) return;
  const anchor = event.target instanceof Element ? event.target.closest("a[href]") : null;
  if (!anchor || !event.currentTarget.contains(anchor)) return;
  const href = anchor.getAttribute("href") ?? "";
  if (href.startsWith("#")) return;
  event.preventDefault();
  const url = externalLinkUrl(href);
  if (url) void open(url).catch(() => {
    useToast.getState().show("Link openen mislukt", "error");
  });
}
