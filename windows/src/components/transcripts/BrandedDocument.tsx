import { open } from "@tauri-apps/plugin-shell";
import { externalLinkUrl } from "../../services/externalLinks";
import { marked } from "marked";
import { useState, useEffect } from "react";
import {
  renderDocument,
  paginate,
  fitDocument,
} from "../../../../shared/document/dist/document.mjs";
import type { Transcript } from "../../types";
export function BrandedDocument({
  transcript,
  editable = false,
  content,
  onReady,
}: {
  transcript: Transcript;
  editable?: boolean;
  content?: string;
  onReady?: (frame: HTMLIFrameElement) => void;
}) {
  const [error, setError] = useState("");
  const [html, setHTML] = useState("");
  useEffect(() => {
    try {
      setHTML(
        renderDocument({
          html:
            content ??
            (transcript.notule_html?.startsWith("<")
              ? transcript.notule_html
              : (marked(transcript.notule_html ?? "") as string)),
          title: editable ? "" : transcript.title,
          editable,
          branding: transcript.document_branding_json,
        }),
      );
      setError("");
    } catch (e) {
      setError(String(e));
    }
  }, [
    transcript.notule_html,
    transcript.title,
    transcript.document_branding_json,
    editable,
    content,
  ]);
  return (
    <>
      {error && <p role="alert">{error}</p>}
      <iframe
        title="Notule in huisstijl"
        sandbox="allow-same-origin"
        srcDoc={html}
        style={{
          width: "100%",
          height: "80vh",
          border: 0,
          background: "white",
        }}
        onLoad={(e) => {
          const doc = e.currentTarget.contentDocument;
          onReady?.(e.currentTarget);
          if (doc) {
            if (!editable)
              void paginate(doc).catch((err) => setError(String(err)));
            const openLink = (event: MouseEvent) => {
              const anchor = (event.target as Element | null)?.closest?.(
                "a[href]",
              );
              if (!anchor) return;
              event.preventDefault();
              const url = externalLinkUrl(anchor.getAttribute("href") ?? "");
              if (url) void open(url).catch((err) => setError(String(err)));
            };
            doc.addEventListener("click", openLink);
            doc.addEventListener("auxclick", openLink);
          }
        }}
      />
    </>
  );
}
