import { useEffect, useState, useRef } from "react";
import {
  Search24Regular,
  Delete24Regular,
  Edit24Regular,
  ArrowDownload24Regular,
  Tag24Regular,
  ArrowSync24Regular,
  MoreHorizontal24Regular,
  ArrowLeft24Regular,
  Copy24Regular,
  Dismiss24Regular,
  Timer24Regular,
  Share24Regular,
} from "@fluentui/react-icons";
import { marked } from "marked";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { api } from "../services/api";
import { createSSEClient } from "../services/sse";
import type { Transcript } from "../types";

interface ContextMenu {
  x: number;
  y: number;
  transcript: Transcript;
}

type TimeFilter = "alles" | "vandaag" | "week" | "maand";
type DetailTab = "notule" | "transcriptie";

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
  const [activeTab, setActiveTab] = useState<DetailTab>("notule");
  const editInputRef = useRef<HTMLInputElement>(null);

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

  async function loadTranscripts() {
    setIsLoading(true);
    const data = await api.getTranscripts({ search: searchQuery });
    setTranscripts(data);
    setIsLoading(false);
  }

  function closeContextMenu() {
    setContextMenu(null);
  }

  function handleContextMenu(e: React.MouseEvent, transcript: Transcript) {
    e.preventDefault();
    e.stopPropagation();
    setContextMenu({ x: e.clientX, y: e.clientY, transcript });
  }

  function handleThreeDotMenu(e: React.MouseEvent, transcript: Transcript) {
    e.stopPropagation();
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    setContextMenu({ x: rect.right, y: rect.bottom, transcript });
  }

  async function handleDelete(transcript: Transcript) {
    try {
      await api.deleteTranscript(transcript.id);
      deleteTranscript(transcript.id);
    } catch (err) {
      console.error("Delete failed:", err);
    }
  }

  function startEdit(transcript: Transcript) {
    setEditingId(transcript.id);
    setEditTitle(transcript.title);
  }

  async function saveEdit(id: string) {
    try {
      const updated = await api.updateTranscript(id, { title: editTitle });
      updateTranscript(id, { title: updated.title });
    } catch (err) {
      console.error("Update failed:", err);
    } finally {
      setEditingId(null);
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
    } catch {
      setRegeneratingId(null);
    }
  }

  function handleExport(transcript: Transcript, format: "html" | "md") {
    if (!transcript.notule_html) return;
    const content = transcript.notule_html;
    const blob = new Blob([content], { type: format === "html" ? "text/html" : "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${transcript.title || "notulen"}.${format}`;
    a.click();
    URL.revokeObjectURL(url);
  }

  function handleCopyTranscription(text: string) {
    navigator.clipboard.writeText(text).catch(() => {
      // fallback: ignore
    });
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

  const selected = transcripts.find((t) => t.id === selectedId);
  const filtered = transcripts.filter((t) => {
    const matchesSearch = !searchQuery || t.title.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesTags = selectedTags.length === 0 || selectedTags.some((tag) => t.tags.includes(tag));
    const matchesTime = filterByTime(t);
    return matchesSearch && matchesTags && matchesTime;
  });

  const allTags = Array.from(new Set(transcripts.flatMap((t) => t.tags)));

  const timeFilterOptions: { key: TimeFilter; label: string }[] = [
    { key: "alles", label: "Alles" },
    { key: "vandaag", label: "Vandaag" },
    { key: "week", label: "Deze week" },
    { key: "maand", label: "Deze maand" },
  ];

  return (
    <div className="flex-row" style={{ height: "100%" }}>
      {/* List panel */}
      <div className="flex-col flex-shrink-0 transcripts-list-panel" style={{ width: 320 }}>
        {/* Page header */}
        <div className="transcripts-list-header">
          <h1 className="text-subtitle transcripts-list-title">Notulen</h1>

          {/* Search */}
          <div className="search-box transcripts-search-margin">
            <Search24Regular className="text-tertiary flex-shrink-0 transcripts-icon-sm" />
            <input
              type="text"
              placeholder="Zoeken..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          {/* Time filter pills */}
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

        {/* Tags */}
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

        {/* List */}
        <div className="flex-1 transcripts-list-scroll">
          {filtered.length === 0 ? (
            <div className="empty-state-text transcripts-empty-list">
              Geen notulen gevonden
            </div>
          ) : (
            filtered.map((transcript) => (
              <div
                key={transcript.id}
                className={`session-card${selectedId === transcript.id ? " active" : ""}`}
                onClick={() => {
                  setSelectedId(transcript.id);
                  setActiveTab("notule");
                }}
                onContextMenu={(e) => handleContextMenu(e, transcript)}
              >
                <div className="flex-row items-start justify-between gap-8">
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
                    {/* Preview text */}
                    {transcript.notule_html && (
                      <p className="session-card-preview">
                        {stripHtml(transcript.notule_html)}
                      </p>
                    )}
                    {/* Status badges */}
                    <div className="flex-row gap-6 transcripts-badges-row">
                      {transcript.notule_html && (
                        <span className="status-badge-success">Notule beschikbaar</span>
                      )}
                      {transcript.tags.slice(0, 2).map((tag) => (
                        <span key={tag} className="tag-chip">
                          {tag}
                        </span>
                      ))}
                    </div>
                  </div>
                  {/* Three-dot menu */}
                  <button
                    className="icon-btn icon-btn-sm"
                    onClick={(e) => handleThreeDotMenu(e, transcript)}
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
      <div className="flex-1 flex-col transcripts-detail-panel">
        {selected ? (
          <>
            {/* Top bar */}
            <div className="flex-row justify-between flex-shrink-0 transcripts-detail-topbar">
              <div className="flex-row gap-8">
                <button className="icon-btn" onClick={() => setSelectedId(null)} title="Terug">
                  <ArrowLeft24Regular className="transcripts-icon-lg" />
                </button>
                <button
                  className="icon-btn"
                  onClick={() => handleRegenerate(selected)}
                  disabled={regeneratingId === selected.id}
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
                title="Meer opties"
              >
                <MoreHorizontal24Regular className="transcripts-icon-lg" />
              </button>
            </div>

            {/* Detail header info */}
            <div className="flex-shrink-0 transcripts-detail-header">
              <h2 className="transcripts-detail-title">
                {selected.title || "Naamloze opname"}
              </h2>
              <p className="text-caption transcripts-detail-meta">
                {formatDate(selected.created_at)} · {formatDuration(selected.duration_seconds)}
                {selected.profile_name && ` · ${selected.profile_name}`}
              </p>

              {/* Tags with + Tag chip */}
              <div className="flex-row gap-6 items-start transcripts-detail-tags">
                {selected.tags.map((tag) => (
                  <span key={tag} className="tag-chip-pill">
                    {tag}
                  </span>
                ))}
                <button className="tag-chip-add" title="Tag toevoegen">
                  + Tag
                </button>
              </div>
            </div>

            {/* Tab switch */}
            <div className="tab-bar transcripts-tab-bar">
              <button
                className={`tab-item${activeTab === "notule" ? " active" : ""}`}
                onClick={() => setActiveTab("notule")}
              >
                Notule
              </button>
              <button
                className={`tab-item${activeTab === "transcriptie" ? " active" : ""}`}
                onClick={() => setActiveTab("transcriptie")}
              >
                Transcriptie
              </button>
            </div>

            {/* Action bar below tabs */}
            <div className="flex-row gap-8 flex-shrink-0 transcripts-action-bar">
              <button
                className="btn btn-amber"
                onClick={() => handleExport(selected, "html")}
                disabled={!selected.notule_html}
              >
                <Share24Regular className="transcripts-icon-md" />
                Deel & Exporteer
              </button>
              <button className="icon-btn" onClick={() => startEdit(selected)} title="Bewerken">
                <Edit24Regular className="transcripts-icon-lg" />
              </button>
            </div>

            {/* Content area */}
            <div className="flex-1 transcripts-content-scroll">
              {activeTab === "notule" ? (
                <>
                  {selected.notule_html ? (
                    <div
                      className="prose"
                      dangerouslySetInnerHTML={{
                        __html: selected.notule_html.startsWith("<")
                          ? selected.notule_html
                          : (marked(selected.notule_html) as string),
                      }}
                    />
                  ) : (
                    <div className="text-center transcripts-empty-content">
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
                /* Transcriptie tab */
                <div>
                  {/* Top actions */}
                  <div className="flex-row gap-8 transcripts-transcription-actions">
                    <button
                      className="btn btn-secondary"
                      onClick={() => {
                        setActiveTab("notule");
                      }}
                    >
                      <Dismiss24Regular className="transcripts-icon-md" />
                      Sluiten
                    </button>
                    {selected.raw_transcription && (
                      <button
                        className="btn btn-secondary"
                        onClick={() => handleCopyTranscription(selected.raw_transcription!)}
                      >
                        <Copy24Regular className="transcripts-icon-md" />
                        Kopieer
                      </button>
                    )}
                  </div>

                  {selected.raw_transcription ? (
                    <div className="card transcripts-transcription-card">
                      <p className="text-body-strong text-accent transcripts-transcription-title">
                        {selected.title || "Naamloze opname"}
                      </p>
                      <p className="section-label">
                        RUWE TRANSCRIPTIE
                      </p>
                      <div className="transcripts-transcription-body">
                        {selected.raw_transcription}
                      </div>
                    </div>
                  ) : (
                    <div className="text-center transcripts-empty-content">
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
          <div className="flex-1 flex-col transcripts-empty-detail">
            <div className="text-center">
              <Tag24Regular className="transcripts-empty-icon" />
              <p className="empty-state-text">
                Selecteer een notule om te bekijken
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
            onClick={() => { startEdit(contextMenu.transcript); setContextMenu(null); }}
          >
            <Edit24Regular className="transcripts-icon-md" />
            Bewerken
          </button>
          <button
            className="context-menu-item"
            onClick={() => { handleExport(contextMenu.transcript, "html"); setContextMenu(null); }}
          >
            <ArrowDownload24Regular className="transcripts-icon-md" />
            Exporteren
          </button>
          <button
            className="context-menu-item"
            onClick={() => setContextMenu(null)}
          >
            <Tag24Regular className="transcripts-icon-md" />
            Tags beheren
          </button>
          <button
            className="context-menu-item"
            onClick={() => { handleRegenerate(contextMenu.transcript); setContextMenu(null); }}
          >
            <ArrowSync24Regular className="transcripts-icon-md" />
            Hertranscribeer
          </button>
          <div className="context-menu-divider" />
          <button
            className="context-menu-item context-menu-item-danger"
            onClick={() => { handleDelete(contextMenu.transcript); setContextMenu(null); }}
          >
            <Delete24Regular className="transcripts-icon-md" />
            Verwijderen
          </button>
        </div>
      )}
    </div>
  );
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
