import { useEffect, useState, useRef, useCallback } from "react";
import {
  ArrowDownload24Regular,
  Tag24Regular,
  ArrowSync24Regular,
  Delete24Regular,
  Document24Regular,
  Dismiss24Regular,
  Add24Regular,
} from "@fluentui/react-icons";
import DOMPurify from "dompurify";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { api } from "../services/api";
import { createSSEClient } from "../services/sse";
import { useToast } from "../components/ui/InfoBar";
import { clampMenuPosition } from "../utils/menuPosition";
import { TranscriptsList } from "../components/transcripts/TranscriptsList";
import { TranscriptDetail } from "../components/transcripts/TranscriptDetail";
import type { Transcript } from "../types";

interface ContextMenu {
  x: number;
  y: number;
  transcript: Transcript;
}

export function TranscriptsPage() {
  const {
    transcripts, selectedId, searchQuery, selectedTags,
    setTranscripts, updateTranscript, deleteTranscript,
    setSelectedId, setSearchQuery, setSelectedTags, setIsLoading,
  } = useTranscriptsStore();
  const [contextMenu, setContextMenu] = useState<ContextMenu | null>(null);
  const [regeneratingId, setRegeneratingId] = useState<string | null>(null);
  const [tagsDialogId, setTagsDialogId] = useState<string | null>(null);
  const [newTagInput, setNewTagInput] = useState("");
  const [availableTags, setAvailableTags] = useState<string[]>([]);
  const toast = useToast();
  const isLoading = useTranscriptsStore((s) => s.isLoading);
  const lastLoadRef = useRef<number>(0);

  const refreshTranscripts = useCallback(async () => {
    lastLoadRef.current = Date.now();
    setIsLoading(true);
    try {
      const data = await api.getTranscripts();
      setTranscripts(data);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Laden mislukt";
      toast.show("Documenten laden mislukt: " + msg, "error");
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    refreshTranscripts();
    document.addEventListener("click", () => setContextMenu(null));
    return () => document.removeEventListener("click", () => setContextMenu(null));
  }, []);

  // Auto-refresh on focus (debounced)
  useEffect(() => {
    function handleFocus() {
      if (Date.now() - lastLoadRef.current > 10_000) refreshTranscripts();
    }
    window.addEventListener("focus", handleFocus);
    return () => window.removeEventListener("focus", handleFocus);
  }, [refreshTranscripts]);

  // --- Select & load detail ---
  async function selectAndLoadDetail(id: string) {
    setSelectedId(id);
    try {
      const detail = await api.getTranscript(id);
      updateTranscript(id, {
        notule_html: detail.notule_html,
        raw_transcription: detail.raw_transcription,
        duration_seconds: detail.duration_seconds,
        profile_name: detail.profile_name,
      });
    } catch { /* listing data still shown */ }
  }

  // --- Context menu ---
  function handleContextMenu(e: React.MouseEvent, transcript: Transcript) {
    e.preventDefault();
    e.stopPropagation();
    const pos = clampMenuPosition(e.clientX, e.clientY);
    setContextMenu({ x: pos.x, y: pos.y, transcript });
  }

  // --- Delete ---
  async function handleDelete(transcript: Transcript) {
    try {
      await api.deleteTranscript(transcript.id);
      deleteTranscript(transcript.id);
      toast.show("Verwijderd", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Verwijderen mislukt", "error");
    }
  }

  // --- Bulk delete ---
  async function handleBulkDelete(ids: string[]) {
    try {
      await api.bulkDeleteTranscripts(ids);
      ids.forEach((id) => deleteTranscript(id));
      toast.show(`${ids.length} items verwijderd`, "success");
    } catch {
      toast.show("Bulk verwijderen mislukt", "error");
    }
  }

  // --- Title update ---
  async function handleUpdateTitle(id: string, title: string) {
    try {
      const updated = await api.updateTranscript(id, { title });
      updateTranscript(id, { title: updated.title || title });
    } catch {
      toast.show("Titel opslaan mislukt", "error");
    }
  }

  // --- Notule save ---
  async function handleSaveNotule(id: string, html: string) {
    try {
      await api.updateNotuleHTML(id, html);
      updateTranscript(id, { notule_html: html });
      toast.show("Notule opgeslagen", "success");
    } catch {
      toast.show("Opslaan mislukt", "error");
    }
  }

  // --- Regenerate ---
  async function handleRegenerate(transcript: Transcript) {
    const profileId = transcript.profile_name || "zakelijk";
    setRegeneratingId(transcript.id);
    try {
      const { task_id } = await api.regenerateNotule(transcript.id, profileId);
      const sseClient = createSSEClient(api.getStreamUrl(task_id));
      sseClient.connect(
        (update) => {
          if (update.notule_html) updateTranscript(transcript.id, { notule_html: update.notule_html });
          if (update.extracted_title) updateTranscript(transcript.id, { title: update.extracted_title });
        },
        () => { setRegeneratingId(null); toast.show("Regenereren mislukt", "error"); },
        async () => {
          setRegeneratingId(null);
          setTimeout(async () => {
            try {
              const updated = await api.getTranscript(transcript.id);
              updateTranscript(transcript.id, { title: updated.title, notule_html: updated.notule_html });
            } catch { /* ignore */ }
          }, 8000);
        }
      );
    } catch {
      setRegeneratingId(null);
      toast.show("Regenereren mislukt", "error");
    }
  }

  // --- Generate title from notule content ---
  async function handleGenerateTitle(transcript: Transcript) {
    if (!transcript.notule_html) return;
    const tmp = document.createElement("div");
    tmp.innerHTML = transcript.notule_html;

    // Collect candidate titles in priority order
    const candidates: string[] = [];

    // 1. All headings (h1, h2, h3)
    tmp.querySelectorAll("h1, h2, h3").forEach((el) => {
      const text = el.textContent?.trim();
      if (text && text.length > 3) candidates.push(text);
    });

    // 2. First bold/strong text (often a meeting title)
    tmp.querySelectorAll("strong, b").forEach((el) => {
      const text = el.textContent?.trim();
      if (text && text.length > 5 && text.length < 120) candidates.push(text);
    });

    // 3. First non-trivial paragraph
    tmp.querySelectorAll("p").forEach((el) => {
      const text = el.textContent?.trim();
      if (text && text.length > 10 && text.length < 120) {
        candidates.push(text.length > 80 ? text.slice(0, 77) + "..." : text);
      }
    });

    // Pick the first candidate that differs from the current title
    const currentLower = (transcript.title || "").toLowerCase();
    const newTitle = candidates.find(
      (c) => c.toLowerCase() !== currentLower && c.toLowerCase() !== "notulen" && c.toLowerCase() !== "samenvatting"
    );

    if (newTitle) {
      await handleUpdateTitle(transcript.id, newTitle);
      toast.show("Titel bijgewerkt", "success");
    } else {
      toast.show("Kon geen betere titel vinden in de notule", "warning");
    }
  }

  // --- Export utilities ---
  function handleExportPDF(transcript: Transcript) {
    if (!transcript.notule_html) return;
    const printWindow = window.open("", "_blank");
    if (!printWindow) return;
    printWindow.document.write(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>${transcript.title || "Notulen"}</title><style>body{font-family:'Segoe UI Variable','Segoe UI',system-ui,sans-serif;font-size:12pt;line-height:1.6;color:#1a1a1a;padding:20pt}h1{font-size:18pt;font-weight:700;color:#E50074;margin-bottom:12pt}h2{font-size:14pt;font-weight:600;margin-top:16pt}h3{font-size:12pt;font-weight:600;margin-top:12pt}p{margin:6pt 0}ul,ol{margin:6pt 0;padding-left:20pt}li{margin:3pt 0}table{border-collapse:collapse;width:100%;margin:12pt 0}th,td{border:1px solid #ddd;padding:6pt 8pt;text-align:left}th{background:#f5f5f5;font-weight:600}</style></head><body><h1>${transcript.title || "Notulen"}</h1><p style="color:#666;font-size:10pt">${formatDate(transcript.created_at)} &middot; ${formatDuration(transcript.duration_seconds)}</p>${DOMPurify.sanitize(transcript.notule_html)}</body></html>`);
    printWindow.document.close();
    setTimeout(() => printWindow.print(), 250);
  }

  function handleExportTXT(transcript: Transcript) {
    const content = transcript.notule_html ? stripHtml(transcript.notule_html) : transcript.raw_transcription;
    if (content) downloadFile(content, `${transcript.title || "notulen"}.txt`, "text/plain");
  }

  function handleExportMarkdown(transcript: Transcript) {
    if (!transcript.notule_html) return;
    downloadFile(htmlToMarkdown(transcript.notule_html), `${transcript.title || "notulen"}.md`, "text/markdown");
  }

  function handleExportHTML(transcript: Transcript) {
    if (!transcript.notule_html) return;
    downloadFile(transcript.notule_html, `${transcript.title || "notulen"}.html`, "text/html");
  }

  const handleCopy = useCallback((text: string) => {
    navigator.clipboard.writeText(text)
      .then(() => toast.show("Gekopieerd", "success"))
      .catch(() => toast.show("Kopiëren mislukt", "error"));
  }, [toast]);

  // --- Tags ---
  async function openTagsDialog(transcriptId: string) {
    setTagsDialogId(transcriptId);
    setNewTagInput("");
    try {
      setAvailableTags(await api.getAllTags());
    } catch {
      setAvailableTags(Array.from(new Set(transcripts.flatMap((t) => t.tags))));
    }
  }

  async function handleAddTag(transcriptId: string, tag: string) {
    const trimmed = tag.trim();
    if (!trimmed) return;
    try {
      await api.updateTranscriptTags(transcriptId, [trimmed], []);
      const t = transcripts.find((t) => t.id === transcriptId);
      if (t && !t.tags.includes(trimmed)) {
        updateTranscript(transcriptId, { tags: [...t.tags, trimmed] });
      }
      setNewTagInput("");
    } catch {
      toast.show("Tag toevoegen mislukt", "error");
    }
  }

  async function handleRemoveTag(transcriptId: string, tag: string) {
    try {
      await api.updateTranscriptTags(transcriptId, [], [tag]);
      const t = transcripts.find((t) => t.id === transcriptId);
      if (t) updateTranscript(transcriptId, { tags: t.tags.filter((x) => x !== tag) });
    } catch {
      toast.show("Tag verwijderen mislukt", "error");
    }
  }

  function handleTagToggle(tag: string) {
    setSelectedTags(
      selectedTags.includes(tag)
        ? selectedTags.filter((t) => t !== tag)
        : [...selectedTags, tag]
    );
  }

  const selected = transcripts.find((t) => t.id === selectedId);

  return (
    <div className="tp-root">
      <TranscriptsList
        transcripts={transcripts}
        selectedId={selectedId}
        searchQuery={searchQuery}
        selectedTags={selectedTags}
        isLoading={isLoading}
        onSelect={selectAndLoadDetail}
        onSearchChange={setSearchQuery}
        onTagToggle={handleTagToggle}
        onRefresh={refreshTranscripts}
        onContextMenu={handleContextMenu}
        onBulkDelete={handleBulkDelete}
      />

      {selectedId && selected ? (
        <TranscriptDetail
          transcript={selected}
          regeneratingId={regeneratingId}
          onBack={() => { setSelectedId(null); }}
          onRegenerate={handleRegenerate}
          onDelete={handleDelete}
          onUpdateTitle={handleUpdateTitle}
          onSaveNotule={handleSaveNotule}
          onCopy={handleCopy}
          onExportPDF={handleExportPDF}
          onExportTXT={handleExportTXT}
          onExportMarkdown={handleExportMarkdown}
          onExportHTML={handleExportHTML}
          onOpenTags={openTagsDialog}
          onGenerateTitle={handleGenerateTitle}
        />
      ) : !selectedId ? (
        <div className="td-empty-panel">
          <Document24Regular style={{ fontSize: 48, color: "var(--text-tertiary)", opacity: 0.3 }} />
          <p className="text-caption text-secondary">Selecteer een document</p>
        </div>
      ) : null}

      {/* Context menu */}
      {contextMenu && (
        <div className="context-menu" style={{ left: contextMenu.x, top: contextMenu.y }} onClick={(e) => e.stopPropagation()}>
          <button className="context-menu-item" onClick={() => { selectAndLoadDetail(contextMenu.transcript.id); setContextMenu(null); }}>
            <Document24Regular style={{ fontSize: 16 }} /> Openen
          </button>
          <button className="context-menu-item" onClick={() => {
            if (contextMenu.transcript.notule_html) handleExportPDF(contextMenu.transcript);
            else handleExportTXT(contextMenu.transcript);
            setContextMenu(null);
          }}>
            <ArrowDownload24Regular style={{ fontSize: 16 }} /> Exporteren
          </button>
          <button className="context-menu-item" onClick={() => { openTagsDialog(contextMenu.transcript.id); setContextMenu(null); }}>
            <Tag24Regular style={{ fontSize: 16 }} /> Tags
          </button>
          <button className="context-menu-item" onClick={() => { handleRegenerate(contextMenu.transcript); setContextMenu(null); }}>
            <ArrowSync24Regular style={{ fontSize: 16 }} /> Regenereer notulen
          </button>
          <div className="context-menu-divider" />
          <button className="context-menu-item context-menu-item-danger" onClick={() => { handleDelete(contextMenu.transcript); setContextMenu(null); }}>
            <Delete24Regular style={{ fontSize: 16 }} /> Verwijderen
          </button>
        </div>
      )}

      {/* Tags dialog */}
      {tagsDialogId && (
        <div className="td-overlay" onClick={() => setTagsDialogId(null)}>
          <div className="td-tags-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 className="td-tags-title">Tags beheren</h3>
            <div className="td-tags-current">
              {transcripts.find((t) => t.id === tagsDialogId)?.tags.map((tag) => (
                <span key={tag} className="td-tag-removable">
                  {tag}
                  <button className="td-tag-remove" onClick={() => handleRemoveTag(tagsDialogId, tag)}>
                    <Dismiss24Regular style={{ fontSize: 10 }} />
                  </button>
                </span>
              ))}
              {(transcripts.find((t) => t.id === tagsDialogId)?.tags.length ?? 0) === 0 && (
                <span className="text-caption text-secondary">Geen tags</span>
              )}
            </div>
            <div className="td-tags-add">
              <input
                type="text"
                value={newTagInput}
                onChange={(e) => setNewTagInput(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter" && newTagInput.trim()) handleAddTag(tagsDialogId, newTagInput); }}
                placeholder="Nieuwe tag..."
                className="input"
                style={{ flex: 1 }}
                autoFocus
              />
              <button className="btn btn-accent btn-sm" onClick={() => handleAddTag(tagsDialogId, newTagInput)} disabled={!newTagInput.trim()}>
                <Add24Regular style={{ fontSize: 14 }} /> Toevoegen
              </button>
            </div>
            {availableTags.filter((t) => !transcripts.find((tr) => tr.id === tagsDialogId)?.tags.includes(t)).length > 0 && (
              <div className="td-tags-suggestions">
                <p className="text-caption text-secondary" style={{ marginBottom: 6 }}>Beschikbaar</p>
                <div className="td-tags-suggestion-list">
                  {availableTags.filter((t) => !transcripts.find((tr) => tr.id === tagsDialogId)?.tags.includes(t)).map((tag) => (
                    <button key={tag} className="tl-tag-pill" onClick={() => handleAddTag(tagsDialogId, tag)}>+ {tag}</button>
                  ))}
                </div>
              </div>
            )}
            <div style={{ marginTop: 16, textAlign: "right" }}>
              <button className="btn btn-secondary btn-sm" onClick={() => setTagsDialogId(null)}>Sluiten</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// --- Utilities ---

function downloadFile(content: string, filename: string, mimeType: string) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}

function htmlToMarkdown(html: string): string {
  let md = html;
  md = md.replace(/<h1[^>]*>(.*?)<\/h1>/gi, "\n# $1\n");
  md = md.replace(/<h2[^>]*>(.*?)<\/h2>/gi, "\n## $1\n");
  md = md.replace(/<h3[^>]*>(.*?)<\/h3>/gi, "\n### $1\n");
  md = md.replace(/<h4[^>]*>(.*?)<\/h4>/gi, "\n#### $1\n");
  md = md.replace(/<(strong|b)[^>]*>(.*?)<\/\1>/gi, "**$2**");
  md = md.replace(/<(em|i)[^>]*>(.*?)<\/\1>/gi, "*$2*");
  md = md.replace(/<li[^>]*>(.*?)<\/li>/gi, "- $1\n");
  md = md.replace(/<br\s*\/?>/gi, "\n");
  md = md.replace(/<\/p>/gi, "\n\n");
  md = md.replace(/<blockquote[^>]*>(.*?)<\/blockquote>/gi, "> $1\n");
  md = md.replace(/<[^>]+>/g, "");
  md = md.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&nbsp;/g, " ").replace(/&quot;/g, '"');
  md = md.replace(/\n{3,}/g, "\n\n");
  return md.trim();
}

function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString("nl-NL", { day: "numeric", month: "short", year: "numeric" })
    + " om " + d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" });
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

function stripHtml(html: string): string {
  const tmp = document.createElement("div");
  tmp.innerHTML = html;
  return tmp.textContent || tmp.innerText || "";
}
