import { useEffect, useState, useRef, useCallback } from "react";
import {
  Search24Regular,
  Delete24Regular,
  Edit24Regular,
  ArrowDownload24Regular,
  Tag24Regular,
  ArrowSync24Regular,
  MoreHorizontal24Regular,
  ArrowLeft24Regular,
  Timer24Regular,
  Share24Regular,
  Document24Regular,
  Clipboard24Regular,
  Checkmark24Regular,
  Dismiss24Regular,
  DocumentPdf24Regular,
  TextDescription24Regular,
  Code24Regular,
  Copy24Regular,
  Add24Regular,
  CheckboxChecked24Regular,
  CheckboxUnchecked24Regular,
} from "@fluentui/react-icons";
import DOMPurify from "dompurify";
import { marked } from "marked";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { api } from "../services/api";
import { createSSEClient } from "../services/sse";
import { useToast } from "../components/ui/InfoBar";
import { clampMenuPosition } from "../utils/menuPosition";
import type { Transcript } from "../types";

interface ContextMenu {
  x: number;
  y: number;
  transcript: Transcript;
}

type TimeFilter = "alles" | "vandaag" | "week" | "maand";
type MainTab = "notulen" | "transcripties";
type DetailTab = "notule" | "transcriptie";

const MAIN_TABS = [
  { id: "notulen" as const, label: "Notulen", icon: <Document24Regular /> },
  { id: "transcripties" as const, label: "Transcripties", icon: <Clipboard24Regular /> },
];

export function TranscriptsPage() {
  const {
    transcripts, selectedId, searchQuery, selectedTags,
    setTranscripts, updateTranscript, deleteTranscript,
    setSelectedId, setSearchQuery, setSelectedTags, setIsLoading,
  } = useTranscriptsStore();
  const [contextMenu, setContextMenu] = useState<ContextMenu | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState("");
  const [regeneratingId, setRegeneratingId] = useState<string | null>(null);
  const [timeFilter, setTimeFilter] = useState<TimeFilter>("alles");
  const [mainTab, setMainTab] = useState<MainTab>("notulen");
  const [detailTab, setDetailTab] = useState<DetailTab>("notule");
  const [isEditingNotule, setIsEditingNotule] = useState(false);
  const [editedHTML, setEditedHTML] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [exportMenuOpen, setExportMenuOpen] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [tagsDialogId, setTagsDialogId] = useState<string | null>(null);
  const [newTagInput, setNewTagInput] = useState("");
  const [availableTags, setAvailableTags] = useState<string[]>([]);
  const [bulkSelected, setBulkSelected] = useState<Set<string>>(new Set());
  const [bulkMode, setBulkMode] = useState(false);
  const toast = useToast();
  const isLoading = useTranscriptsStore((s) => s.isLoading);
  const editInputRef = useRef<HTMLInputElement>(null);
  const editorRef = useRef<HTMLDivElement>(null);
  const exportBtnRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    loadTranscripts();
    document.addEventListener("click", closeContextMenu);
    return () => document.removeEventListener("click", closeContextMenu);
  }, []);

  useEffect(() => {
    if (editingId && editInputRef.current) {
      editInputRef.current.focus();
    }
  }, [editingId]);

  // Close export menu on outside click
  useEffect(() => {
    if (!exportMenuOpen) return;
    function handleClick(e: MouseEvent) {
      if (exportBtnRef.current && !exportBtnRef.current.contains(e.target as Node)) {
        setExportMenuOpen(false);
      }
    }
    document.addEventListener("click", handleClick);
    return () => document.removeEventListener("click", handleClick);
  }, [exportMenuOpen]);

  async function loadTranscripts() {
    setIsLoading(true);
    setLoadError(null);
    try {
      const data = await api.getTranscripts();
      setTranscripts(data);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Laden mislukt";
      setLoadError(msg);
      toast.show("Notulen laden mislukt: " + msg, "error");
    } finally {
      setIsLoading(false);
    }
  }

  function closeContextMenu() {
    setContextMenu(null);
  }

  function handleContextMenu(e: React.MouseEvent, transcript: Transcript) {
    e.preventDefault();
    e.stopPropagation();
    const pos = clampMenuPosition(e.clientX, e.clientY);
    setContextMenu({ x: pos.x, y: pos.y, transcript });
  }

  function handleThreeDotMenu(e: React.MouseEvent, transcript: Transcript) {
    e.stopPropagation();
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const pos = clampMenuPosition(rect.right, rect.bottom);
    setContextMenu({ x: pos.x, y: pos.y, transcript });
  }

  async function handleDelete(transcript: Transcript) {
    try {
      await api.deleteTranscript(transcript.id);
      deleteTranscript(transcript.id);
      toast.show("Verwijderd", "success");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Verwijderen mislukt";
      toast.show(msg, "error");
    }
  }

  function startEdit(transcript: Transcript) {
    setEditingId(transcript.id);
    setEditTitle(transcript.title);
  }

  async function saveEdit(id: string) {
    try {
      const updated = await api.updateTranscript(id, { title: editTitle });
      updateTranscript(id, { title: updated.title || editTitle });
    } catch (err) {
      toast.show("Naam opslaan mislukt", "error");
    } finally {
      setEditingId(null);
    }
  }

  // --- Notule inline editing ---
  function startNotuleEdit(transcript: Transcript) {
    setEditedHTML(transcript.notule_html || "");
    setIsEditingNotule(true);
  }

  function cancelNotuleEdit() {
    setIsEditingNotule(false);
    setEditedHTML("");
  }

  async function saveNotuleEdit(transcript: Transcript) {
    if (!editedHTML.trim()) return;
    setIsSaving(true);
    try {
      await api.updateNotuleHTML(transcript.id, editedHTML);
      updateTranscript(transcript.id, { notule_html: editedHTML });
      setIsEditingNotule(false);
      toast.show("Notule opgeslagen", "success");
    } catch (err) {
      console.error("Save notule failed:", err);
      toast.show("Opslaan mislukt", "error");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleRegenerate(transcript: Transcript) {
    setRegeneratingId(transcript.id);
    try {
      const { task_id } = await api.regenerateNotule(
        transcript.id,
        transcript.profile_name || "zakelijk"
      );

      const sseClient = createSSEClient(api.getStreamUrl(task_id));
      sseClient.connect(
        (update) => {
          if (update.notule_html) {
            updateTranscript(transcript.id, { notule_html: update.notule_html });
          }
        },
        () => setRegeneratingId(null),
        async () => {
          setRegeneratingId(null);
          setTimeout(async () => {
            try {
              const updated = await api.getTranscript(transcript.id);
              updateTranscript(transcript.id, { notule_html: updated.notule_html });
            } catch {
              // ignore
            }
          }, 8000);
        }
      );
    } catch (err) {
      setRegeneratingId(null);
      toast.show("Hertranscriberen mislukt", "error");
    }
  }

  // --- Export functions ---
  function handleExportPDF(transcript: Transcript) {
    if (!transcript.notule_html) return;
    const printWindow = window.open("", "_blank");
    if (!printWindow) return;
    printWindow.document.write(`<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<title>${transcript.title || "Notulen"}</title>
<style>
  body { font-family: 'Segoe UI Variable', 'Segoe UI', -apple-system, system-ui, sans-serif; font-size: 12pt; line-height: 1.6; color: #1a1a1a; margin: 0; padding: 20pt; }
  h1 { font-size: 18pt; font-weight: 700; color: #E50074; margin-bottom: 12pt; }
  h2 { font-size: 14pt; font-weight: 600; margin-top: 16pt; }
  h3 { font-size: 12pt; font-weight: 600; margin-top: 12pt; }
  p { margin: 6pt 0; }
  ul, ol { margin: 6pt 0; padding-left: 20pt; }
  li { margin: 3pt 0; }
  table { border-collapse: collapse; width: 100%; margin: 12pt 0; }
  th, td { border: 1px solid #ddd; padding: 6pt 8pt; text-align: left; }
  th { background: #f5f5f5; font-weight: 600; }
</style>
</head><body>
<h1>${transcript.title || "Notulen"}</h1>
<p style="color: #666; font-size: 10pt;">
  ${formatDate(transcript.created_at)} · ${formatDuration(transcript.duration_seconds)}
</p>
${DOMPurify.sanitize(transcript.notule_html)}
</body></html>`);
    printWindow.document.close();
    setTimeout(() => printWindow.print(), 250);
  }

  function handleExportTXT(transcript: Transcript) {
    const content = transcript.notule_html
      ? stripHtml(transcript.notule_html)
      : transcript.raw_transcription;
    if (!content) return;
    downloadFile(content, `${transcript.title || "notulen"}.txt`, "text/plain");
  }

  function handleExportMarkdown(transcript: Transcript) {
    if (!transcript.notule_html) return;
    const md = htmlToMarkdown(transcript.notule_html);
    downloadFile(md, `${transcript.title || "notulen"}.md`, "text/markdown");
  }

  function handleExportHTML(transcript: Transcript) {
    if (!transcript.notule_html) return;
    downloadFile(transcript.notule_html, `${transcript.title || "notulen"}.html`, "text/html");
  }

  const handleCopy = useCallback((text: string) => {
    navigator.clipboard.writeText(text).then(() => {
      toast.show("Gekopieerd naar klembord", "success");
    }).catch(() => {
      toast.show("Kopiëren mislukt", "error");
    });
  }, [toast]);

  // --- Tags management ---
  async function openTagsDialog(transcriptId: string) {
    setTagsDialogId(transcriptId);
    setNewTagInput("");
    try {
      const tags = await api.getAllTags();
      setAvailableTags(tags);
    } catch {
      // Use tags from current transcripts as fallback
      setAvailableTags(Array.from(new Set(transcripts.flatMap((t) => t.tags))));
    }
  }

  async function handleAddTag(transcriptId: string, tag: string) {
    const trimmed = tag.trim();
    if (!trimmed) return;
    try {
      await api.updateTranscriptTags(transcriptId, [trimmed], []);
      const transcript = transcripts.find((t) => t.id === transcriptId);
      if (transcript && !transcript.tags.includes(trimmed)) {
        updateTranscript(transcriptId, { tags: [...transcript.tags, trimmed] });
      }
      setNewTagInput("");
    } catch {
      toast.show("Tag toevoegen mislukt", "error");
    }
  }

  async function handleRemoveTag(transcriptId: string, tag: string) {
    try {
      await api.updateTranscriptTags(transcriptId, [], [tag]);
      const transcript = transcripts.find((t) => t.id === transcriptId);
      if (transcript) {
        updateTranscript(transcriptId, { tags: transcript.tags.filter((t) => t !== tag) });
      }
    } catch {
      toast.show("Tag verwijderen mislukt", "error");
    }
  }

  // --- Bulk operations ---
  function toggleBulkSelect(id: string) {
    setBulkSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function selectAllFiltered() {
    if (bulkSelected.size === filteredTranscripts.length) {
      setBulkSelected(new Set());
    } else {
      setBulkSelected(new Set(filteredTranscripts.map((t) => t.id)));
    }
  }

  async function handleBulkDelete() {
    if (bulkSelected.size === 0) return;
    const ids = Array.from(bulkSelected);
    try {
      await api.bulkDeleteTranscripts(ids);
      ids.forEach((id) => deleteTranscript(id));
      setBulkSelected(new Set());
      setBulkMode(false);
      toast.show(`${ids.length} items verwijderd`, "success");
    } catch {
      toast.show("Bulk verwijderen mislukt", "error");
    }
  }

  function filterByTime(transcript: Transcript): boolean {
    if (timeFilter === "alles") return true;
    const created = new Date(transcript.created_at);
    const now = new Date();
    if (timeFilter === "vandaag") {
      return (
        created.getDate() === now.getDate() &&
        created.getMonth() === now.getMonth() &&
        created.getFullYear() === now.getFullYear()
      );
    }
    if (timeFilter === "week") {
      const weekAgo = new Date(now);
      weekAgo.setDate(weekAgo.getDate() - 7);
      return created >= weekAgo;
    }
    if (timeFilter === "maand") {
      const monthAgo = new Date(now);
      monthAgo.setMonth(monthAgo.getMonth() - 1);
      return created >= monthAgo;
    }
    return true;
  }

  const filteredTranscripts = transcripts.filter((t) => {
    const matchesSearch = !searchQuery || t.title.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesTags = selectedTags.length === 0 || selectedTags.some((tag) => t.tags.includes(tag));
    const matchesTime = filterByTime(t);
    const matchesTab =
      mainTab === "notulen"
        ? t.notule_html && t.notule_html.length > 0
        : t.raw_transcription && t.raw_transcription.length > 0;
    return matchesSearch && matchesTags && matchesTime && matchesTab;
  });

  const selected = transcripts.find((t) => t.id === selectedId);
  const allTags = Array.from(new Set(transcripts.flatMap((t) => t.tags)));

  const timeFilterOptions: { key: TimeFilter; label: string }[] = [
    { key: "alles", label: "Alles" },
    { key: "vandaag", label: "Vandaag" },
    { key: "week", label: "Deze week" },
    { key: "maand", label: "Deze maand" },
  ];

  return (
    <div style={{ flex: 1, display: "flex", overflow: "hidden" }}>
      {/* List panel */}
      <div className="transcripts-list-panel">
        <div className="transcripts-list-header">
          <div className="flex-row justify-between" style={{ alignItems: "center" }}>
            <h1 className="text-subtitle transcripts-list-title" style={{ margin: 0 }}>Notulen & Transcripties</h1>
            <button
              className={`icon-btn icon-btn-sm${bulkMode ? " active" : ""}`}
              onClick={() => { setBulkMode(!bulkMode); setBulkSelected(new Set()); }}
              aria-label="Selectiemodus"
              title="Selectiemodus"
              style={bulkMode ? { color: "var(--fill-accent)" } : undefined}
            >
              <CheckboxChecked24Regular style={{ fontSize: 16 }} />
            </button>
          </div>

          <div className="search-box transcripts-search-margin">
            <Search24Regular className="text-tertiary flex-shrink-0 transcripts-icon-sm" />
            <input
              type="text"
              placeholder="Zoeken..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          <div className="flex-row gap-6 transcripts-filter-wrap">
            {timeFilterOptions.map((opt) => (
              <button
                key={opt.key}
                onClick={() => setTimeFilter(opt.key)}
                className={`filter-pill${timeFilter === opt.key ? " active" : ""}`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        <div className="tab-bar transcripts-main-tab-bar">
          {MAIN_TABS.map((tab) => (
            <button
              key={tab.id}
              className={`tab-item${mainTab === tab.id ? " active" : ""}`}
              onClick={() => {
                setMainTab(tab.id);
                setSelectedId(null);
                setIsEditingNotule(false);
              }}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>

        {allTags.length > 0 && (
          <div className="flex-row gap-6 transcripts-tags-bar">
            {allTags.map((tag) => (
              <button
                key={tag}
                onClick={() =>
                  setSelectedTags(
                    selectedTags.includes(tag)
                      ? selectedTags.filter((t) => t !== tag)
                      : [...selectedTags, tag]
                  )
                }
                className={`filter-pill${selectedTags.includes(tag) ? " active" : ""}`}
              >
                {tag}
              </button>
            ))}
          </div>
        )}

        {bulkMode && (
          <div className="flex-row gap-8 bulk-action-bar">
            <button className="btn btn-sm" onClick={selectAllFiltered}>
              {bulkSelected.size === filteredTranscripts.length ? "Deselecteer alles" : "Selecteer alles"}
            </button>
            {bulkSelected.size > 0 && (
              <>
                <span className="text-caption">{bulkSelected.size} geselecteerd</span>
                <button
                  className="btn btn-sm"
                  style={{ color: "var(--text-error)" }}
                  onClick={handleBulkDelete}
                >
                  <Delete24Regular style={{ fontSize: 12 }} />
                  Verwijderen
                </button>
              </>
            )}
          </div>
        )}

        <div className="flex-1 transcripts-list-scroll">
          {isLoading ? (
            <div className="transcripts-empty-list">
              <p className="text-caption text-secondary">Laden...</p>
            </div>
          ) : loadError ? (
            <div className="transcripts-empty-list">
              <p className="text-caption" style={{ color: "var(--fill-system-critical)" }}>{loadError}</p>
              <button className="btn btn-sm" onClick={loadTranscripts} style={{ marginTop: 8 }}>
                Opnieuw proberen
              </button>
            </div>
          ) : filteredTranscripts.length === 0 ? (
            <div className="empty-state-text transcripts-empty-list">
              {mainTab === "notulen" ? "Geen notulen gevonden" : "Geen transcripties gevonden"}
            </div>
          ) : (
            filteredTranscripts.map((transcript) => (
              <div
                key={transcript.id}
                className={`session-card${selectedId === transcript.id ? " active" : ""}`}
                onClick={() => {
                  if (bulkMode) {
                    toggleBulkSelect(transcript.id);
                  } else {
                    setSelectedId(transcript.id);
                    setDetailTab(mainTab === "notulen" ? "notule" : "transcriptie");
                    setIsEditingNotule(false);
                  }
                }}
                onContextMenu={(e) => handleContextMenu(e, transcript)}
              >
                <div className="flex-row items-start justify-between gap-8">
                  {bulkMode && (
                    <span style={{ flexShrink: 0, marginTop: 2, color: bulkSelected.has(transcript.id) ? "var(--fill-accent)" : "var(--text-tertiary)" }}>
                      {bulkSelected.has(transcript.id)
                        ? <CheckboxChecked24Regular style={{ fontSize: 18 }} />
                        : <CheckboxUnchecked24Regular style={{ fontSize: 18 }} />
                      }
                    </span>
                  )}
                  <div className="flex-1">
                    {editingId === transcript.id ? (
                      <input
                        ref={editInputRef}
                        value={editTitle}
                        onChange={(e) => setEditTitle(e.target.value)}
                        onBlur={() => saveEdit(transcript.id)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") saveEdit(transcript.id);
                          if (e.key === "Escape") setEditingId(null);
                        }}
                        onClick={(e) => e.stopPropagation()}
                        className="transcripts-edit-input"
                      />
                    ) : (
                      <p className="text-body-strong truncate transcripts-item-title">
                        {transcript.title || "Naamloze opname"}
                      </p>
                    )}
                    <p className="text-caption transcripts-item-meta">
                      {timeAgo(transcript.created_at)}
                    </p>
                    {mainTab === "notulen" && transcript.notule_html && (
                      <p className="session-card-preview">
                        {stripHtml(transcript.notule_html)}
                      </p>
                    )}
                    {mainTab === "transcripties" && transcript.raw_transcription && (
                      <p className="session-card-preview">
                        {transcript.raw_transcription.slice(0, 150)}...
                      </p>
                    )}
                    <div className="flex-row gap-6 transcripts-badges-row">
                      {mainTab === "notulen" && transcript.notule_html && (
                        <span className="status-badge-success">Notule beschikbaar</span>
                      )}
                      {mainTab === "transcripties" && transcript.raw_transcription && (
                        <span className="status-badge-neutral">Transcriptie beschikbaar</span>
                      )}
                      {transcript.tags.slice(0, 2).map((tag) => (
                        <span key={tag} className="tag-chip">
                          {tag}
                        </span>
                      ))}
                    </div>
                  </div>
                  <button
                    className="icon-btn icon-btn-sm"
                    onClick={(e) => handleThreeDotMenu(e, transcript)}
                    aria-label="Meer opties"
                    title="Meer opties"
                  >
                    <MoreHorizontal24Regular className="transcripts-icon-md" />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Detail panel */}
      <div className="flex-1 transcripts-detail-panel bg-blobs">
        <div className="bg-blob bg-blob-blue" style={{ opacity: 0.5 }} />
        {selected ? (
          <>
            {/* Top bar */}
            <div className="flex-row justify-between flex-shrink-0 transcripts-detail-topbar">
              <div className="flex-row gap-8">
                <button className="icon-btn" onClick={() => { setSelectedId(null); setIsEditingNotule(false); }} aria-label="Terug naar lijst" title="Terug">
                  <ArrowLeft24Regular className="transcripts-icon-lg" />
                </button>
                <button
                  className="icon-btn"
                  onClick={() => handleRegenerate(selected)}
                  disabled={regeneratingId === selected.id}
                  aria-label="Hertranscribeer"
                  title="Hertranscribeer"
                >
                  <Timer24Regular
                    className={`transcripts-icon-lg${regeneratingId === selected.id ? " transcripts-spin" : ""}`}
                  />
                </button>
                <span
                  className="text-caption text-secondary transcripts-regenerate-label"
                  onClick={() => {
                    if (regeneratingId !== selected.id) handleRegenerate(selected);
                  }}
                >
                  Hertranscribeer
                </span>
              </div>
              <button
                className="icon-btn"
                onClick={(e) => handleThreeDotMenu(e as unknown as React.MouseEvent, selected)}
                aria-label="Meer opties"
                title="Meer opties"
              >
                <MoreHorizontal24Regular className="transcripts-icon-lg" />
              </button>
            </div>

            {/* Detail header */}
            <div className="flex-shrink-0 transcripts-detail-header">
              <h2 className="transcripts-detail-title">
                {selected.title || "Naamloze opname"}
              </h2>
              <p className="text-caption transcripts-detail-meta">
                {formatDate(selected.created_at)} · {formatDuration(selected.duration_seconds)}
                {selected.profile_name && ` · ${selected.profile_name}`}
              </p>
              <div className="flex-row gap-6 items-start transcripts-detail-tags">
                {selected.tags.map((tag) => (
                  <span key={tag} className="tag-chip-pill">{tag}</span>
                ))}
                <button className="tag-chip-add" title="Tag toevoegen" onClick={() => openTagsDialog(selected.id)}>+ Tag</button>
              </div>
            </div>

            {/* Tab switch */}
            {(selected.notule_html || selected.raw_transcription) && (
              <div className="tab-bar transcripts-tab-bar">
                {selected.notule_html && (
                  <button
                    className={`tab-item${detailTab === "notule" ? " active" : ""}`}
                    onClick={() => { setDetailTab("notule"); setIsEditingNotule(false); }}
                  >
                    Notule
                  </button>
                )}
                {selected.raw_transcription && (
                  <button
                    className={`tab-item${detailTab === "transcriptie" ? " active" : ""}`}
                    onClick={() => { setDetailTab("transcriptie"); setIsEditingNotule(false); }}
                  >
                    Transcriptie
                  </button>
                )}
              </div>
            )}

            {/* Action bar */}
            <div className="flex-row gap-8 flex-shrink-0 transcripts-action-bar">
              {detailTab === "notule" ? (
                <>
                  {/* Export dropdown */}
                  <div style={{ position: "relative" }}>
                    <button
                      ref={exportBtnRef}
                      className="btn btn-amber"
                      onClick={() => setExportMenuOpen(!exportMenuOpen)}
                      disabled={!selected.notule_html}
                    >
                      <Share24Regular className="transcripts-icon-md" />
                      Exporteren
                    </button>
                    {exportMenuOpen && selected.notule_html && (
                      <div className="context-menu" style={{ right: 0, top: "100%", marginTop: 4, minWidth: 180 }}>
                        <button className="context-menu-item" onClick={() => { handleExportPDF(selected); setExportMenuOpen(false); }}>
                          <DocumentPdf24Regular className="transcripts-icon-md" />
                          Exporteer PDF
                        </button>
                        <button className="context-menu-item" onClick={() => { handleExportMarkdown(selected); setExportMenuOpen(false); }}>
                          <Code24Regular className="transcripts-icon-md" />
                          Exporteer Markdown
                        </button>
                        <button className="context-menu-item" onClick={() => { handleExportTXT(selected); setExportMenuOpen(false); }}>
                          <TextDescription24Regular className="transcripts-icon-md" />
                          Exporteer TXT
                        </button>
                        <button className="context-menu-item" onClick={() => { handleExportHTML(selected); setExportMenuOpen(false); }}>
                          <ArrowDownload24Regular className="transcripts-icon-md" />
                          Exporteer HTML
                        </button>
                        <div className="context-menu-divider" />
                        <button className="context-menu-item" onClick={() => { handleCopy(stripHtml(selected.notule_html!)); setExportMenuOpen(false); }}>
                          <Copy24Regular className="transcripts-icon-md" />
                          Kopieer tekst
                        </button>
                      </div>
                    )}
                  </div>

                  {/* Edit / Save / Cancel buttons */}
                  {isEditingNotule ? (
                    <>
                      <button
                        className="btn btn-accent"
                        onClick={() => saveNotuleEdit(selected)}
                        disabled={isSaving}
                      >
                        <Checkmark24Regular className="transcripts-icon-md" />
                        {isSaving ? "Opslaan..." : "Opslaan"}
                      </button>
                      <button
                        className="btn"
                        onClick={cancelNotuleEdit}
                        disabled={isSaving}
                      >
                        <Dismiss24Regular className="transcripts-icon-md" />
                        Annuleren
                      </button>
                    </>
                  ) : (
                    <button
                      className="btn btn-secondary"
                      onClick={() => startNotuleEdit(selected)}
                      disabled={!selected.notule_html}
                    >
                      <Edit24Regular className="transcripts-icon-md" />
                      Bewerken
                    </button>
                  )}
                </>
              ) : (
                <>
                  <button
                    className="btn btn-amber"
                    onClick={() => {
                      if (selected.raw_transcription) handleCopy(selected.raw_transcription);
                    }}
                    disabled={!selected.raw_transcription}
                  >
                    <Copy24Regular className="transcripts-icon-md" />
                    Kopieer transcriptie
                  </button>
                  <button
                    className="btn btn-secondary"
                    onClick={() => handleExportTXT(selected)}
                    disabled={!selected.raw_transcription}
                  >
                    <ArrowDownload24Regular className="transcripts-icon-md" />
                    Exporteer TXT
                  </button>
                </>
              )}
            </div>

            {/* Content area */}
            <div className="flex-1 transcripts-content-scroll">
              {detailTab === "notule" ? (
                <>
                  {selected.notule_html ? (
                    isEditingNotule ? (
                      <div
                        ref={editorRef}
                        className="prose notule-editor"
                        contentEditable
                        suppressContentEditableWarning
                        dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(editedHTML) }}
                        onInput={(e) => setEditedHTML((e.target as HTMLDivElement).innerHTML)}
                      />
                    ) : (
                      <div
                        className="prose"
                        dangerouslySetInnerHTML={{
                          __html: DOMPurify.sanitize(
                            selected.notule_html.startsWith("<")
                              ? selected.notule_html
                              : (marked(selected.notule_html) as string)
                          ),
                        }}
                      />
                    )
                  ) : (
                    <div className="text-center transcripts-empty-content">
                      <Document24Regular className="transcripts-empty-icon-large" />
                      <p className="text-tertiary transcripts-empty-content-text">
                        Geen notulen beschikbaar
                      </p>
                      <button
                        onClick={() => handleRegenerate(selected)}
                        className="btn btn-accent transcripts-generate-btn"
                      >
                        Notulen genereren
                      </button>
                    </div>
                  )}
                </>
              ) : (
                <div>
                  {selected.raw_transcription ? (
                    <div className="card transcripts-transcription-card">
                      <p className="text-body-strong text-accent transcripts-transcription-title">
                        {selected.title || "Naamloze opname"}
                      </p>
                      <p className="section-label">RUWE TRANSCRIPTIE</p>
                      <div className="transcripts-transcription-body">
                        {typeof selected.raw_transcription === "string" ? selected.raw_transcription : ""}
                      </div>
                    </div>
                  ) : (
                    <div className="text-center transcripts-empty-content">
                      <Clipboard24Regular className="transcripts-empty-icon-large" />
                      <p className="text-tertiary transcripts-empty-content-text">
                        Geen transcriptie beschikbaar
                      </p>
                    </div>
                  )}
                </div>
              )}
            </div>
          </>
        ) : (
          <div className="transcripts-empty-detail" style={{ flex: 1, display: "flex", flexDirection: "column" }}>
            <div className="text-center">
              <Tag24Regular className="transcripts-empty-icon" />
              <p className="empty-state-text">
                Selecteer een {mainTab === "notulen" ? "notitie" : "transcriptie"} om te bekijken
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Context menu */}
      {contextMenu && (
        <div
          className="context-menu"
          style={{ left: contextMenu.x, top: contextMenu.y }}
          onClick={(e) => e.stopPropagation()}
        >
          <button
            className="context-menu-item"
            onClick={() => {
              startEdit(contextMenu.transcript);
              setContextMenu(null);
            }}
          >
            <Edit24Regular className="transcripts-icon-md" />
            Naam bewerken
          </button>
          {contextMenu.transcript.notule_html && (
            <button
              className="context-menu-item"
              onClick={() => {
                setSelectedId(contextMenu.transcript.id);
                setDetailTab("notule");
                startNotuleEdit(contextMenu.transcript);
                setContextMenu(null);
              }}
            >
              <Document24Regular className="transcripts-icon-md" />
              Notule bewerken
            </button>
          )}
          <button
            className="context-menu-item"
            onClick={() => {
              if (contextMenu.transcript.notule_html) {
                handleExportPDF(contextMenu.transcript);
              } else if (contextMenu.transcript.raw_transcription) {
                handleExportTXT(contextMenu.transcript);
              }
              setContextMenu(null);
            }}
          >
            <ArrowDownload24Regular className="transcripts-icon-md" />
            Exporteren
          </button>
          <button
            className="context-menu-item"
            onClick={() => {
              openTagsDialog(contextMenu.transcript.id);
              setContextMenu(null);
            }}
          >
            <Tag24Regular className="transcripts-icon-md" />
            Tags beheren
          </button>
          <button
            className="context-menu-item"
            onClick={() => {
              handleRegenerate(contextMenu.transcript);
              setContextMenu(null);
            }}
          >
            <ArrowSync24Regular className="transcripts-icon-md" />
            Hertranscribeer
          </button>
          <div className="context-menu-divider" />
          <button
            className="context-menu-item context-menu-item-danger"
            onClick={() => {
              handleDelete(contextMenu.transcript);
              setContextMenu(null);
            }}
          >
            <Delete24Regular className="transcripts-icon-md" />
            Verwijderen
          </button>
        </div>
      )}

      {/* Tags dialog */}
      {tagsDialogId && (
        <div
          style={{
            position: "fixed", inset: 0, zIndex: 1000,
            display: "flex", alignItems: "center", justifyContent: "center",
            background: "rgba(0,0,0,0.3)", backdropFilter: "blur(4px)",
          }}
          onClick={() => setTagsDialogId(null)}
        >
          <div
            className="card"
            style={{ width: "100%", maxWidth: "min(360px, calc(100vw - 32px))", padding: 20, background: "var(--surface-primary)", margin: "0 16px" }}
            onClick={(e) => e.stopPropagation()}
          >
            <h3 style={{ fontSize: 16, fontWeight: 600, marginBottom: 12 }}>Tags beheren</h3>

            {/* Current tags */}
            <div className="flex-row gap-6" style={{ flexWrap: "wrap", marginBottom: 12 }}>
              {transcripts.find((t) => t.id === tagsDialogId)?.tags.map((tag) => (
                <span key={tag} className="tag-chip-pill flex-row gap-4" style={{ alignItems: "center" }}>
                  {tag}
                  <button
                    onClick={() => handleRemoveTag(tagsDialogId, tag)}
                    style={{ background: "none", border: "none", cursor: "default", padding: 0, color: "var(--text-tertiary)", fontSize: 12, minWidth: 24, minHeight: 24, display: "inline-flex", alignItems: "center", justifyContent: "center" }}
                  >
                    <Dismiss24Regular style={{ fontSize: 12 }} />
                  </button>
                </span>
              ))}
              {(transcripts.find((t) => t.id === tagsDialogId)?.tags.length ?? 0) === 0 && (
                <span className="text-caption text-secondary">Geen tags</span>
              )}
            </div>

            {/* Add new tag */}
            <div className="flex-row gap-8" style={{ marginBottom: 12 }}>
              <input
                type="text"
                value={newTagInput}
                onChange={(e) => setNewTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && newTagInput.trim()) {
                    handleAddTag(tagsDialogId, newTagInput);
                  }
                }}
                placeholder="Nieuwe tag..."
                className="input"
                style={{ flex: 1 }}
                autoFocus
              />
              <button
                className="btn btn-accent"
                onClick={() => handleAddTag(tagsDialogId, newTagInput)}
                disabled={!newTagInput.trim()}
                style={{ padding: "7px 12px", fontSize: 12 }}
              >
                <Add24Regular style={{ fontSize: 14 }} />
                Toevoegen
              </button>
            </div>

            {/* Suggested tags from other transcripts */}
            {availableTags.filter((t) => !transcripts.find((tr) => tr.id === tagsDialogId)?.tags.includes(t)).length > 0 && (
              <>
                <p className="text-caption text-secondary" style={{ marginBottom: 6 }}>Beschikbare tags</p>
                <div className="flex-row gap-6" style={{ flexWrap: "wrap" }}>
                  {availableTags
                    .filter((t) => !transcripts.find((tr) => tr.id === tagsDialogId)?.tags.includes(t))
                    .map((tag) => (
                      <button
                        key={tag}
                        className="filter-pill"
                        onClick={() => handleAddTag(tagsDialogId, tag)}
                        style={{ fontSize: 11 }}
                      >
                        + {tag}
                      </button>
                    ))}
                </div>
              </>
            )}

            <div style={{ marginTop: 16, textAlign: "right" }}>
              <button className="btn btn-secondary" onClick={() => setTagsDialogId(null)} style={{ fontSize: 12 }}>
                Sluiten
              </button>
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
  a.href = url;
  a.download = filename;
  a.click();
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
  md = md.replace(/&amp;/g, "&");
  md = md.replace(/&lt;/g, "<");
  md = md.replace(/&gt;/g, ">");
  md = md.replace(/&nbsp;/g, " ");
  md = md.replace(/&quot;/g, '"');
  md = md.replace(/\n{3,}/g, "\n\n");
  return md.trim();
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("nl-NL", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

function timeAgo(dateStr: string): string {
  const now = new Date();
  const date = new Date(dateStr);
  const diffMs = now.getTime() - date.getTime();
  const diffMinutes = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMinutes < 1) return "Zojuist";
  if (diffMinutes < 60) return `${diffMinutes} min geleden`;
  if (diffHours < 24) return `${diffHours} uur geleden`;
  if (diffDays === 1) return "Gisteren";
  if (diffDays < 7) return `${diffDays} dagen geleden`;
  if (diffDays < 30) return `${Math.floor(diffDays / 7)} weken geleden`;
  return formatDate(dateStr);
}

function stripHtml(html: string): string {
  const tmp = document.createElement("div");
  tmp.innerHTML = html;
  return tmp.textContent || tmp.innerText || "";
}
