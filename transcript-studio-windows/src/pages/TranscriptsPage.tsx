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
    <div style={{ display: "flex", height: "100%" }}>
      {/* List panel */}
      <div
        style={{
          width: 320,
          flexShrink: 0,
          display: "flex",
          flexDirection: "column",
          borderRight: "1px solid var(--stroke-divider)",
          background: "var(--surface-card)",
        }}
      >
        {/* Page header */}
        <div style={{ padding: "16px 14px 0 14px" }}>
          <h1
            style={{
              fontSize: "var(--font-subtitle)",
              fontWeight: 700,
              color: "var(--text-primary)",
              marginBottom: 12,
            }}
          >
            Notulen
          </h1>

          {/* Search */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              padding: "6px 10px",
              background: "var(--fill-control-default)",
              borderRadius: "var(--radius-sm)",
              border: "1px solid var(--stroke-control-secondary)",
              marginBottom: 10,
            }}
          >
            <Search24Regular style={{ fontSize: 15, color: "var(--text-tertiary)", flexShrink: 0 }} />
            <input
              type="text"
              placeholder="Zoeken..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              style={{
                flex: 1,
                background: "transparent",
                border: "none",
                outline: "none",
                fontSize: 13,
                color: "var(--text-primary)",
              }}
            />
          </div>

          {/* Time filter pills */}
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 10 }}>
            {timeFilterOptions.map((opt) => (
              <button
                key={opt.key}
                onClick={() => setTimeFilter(opt.key)}
                style={{
                  padding: "4px 12px",
                  fontSize: 12,
                  fontWeight: timeFilter === opt.key ? 600 : 400,
                  borderRadius: "var(--radius-pill)",
                  border: "1px solid",
                  cursor: "pointer",
                  transition: "background 67ms ease",
                  ...(timeFilter === opt.key
                    ? {
                        background: "var(--fill-accent-default)",
                        color: "var(--text-on-accent)",
                        borderColor: "var(--fill-accent-default)",
                      }
                    : {
                        background: "transparent",
                        color: "var(--text-secondary)",
                        borderColor: "var(--stroke-control-secondary)",
                      }),
                }}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        {/* Tags */}
        {allTags.length > 0 && (
          <div
            style={{
              padding: "6px 14px 8px",
              borderBottom: "1px solid var(--stroke-divider)",
              display: "flex",
              flexWrap: "wrap",
              gap: 6,
            }}
          >
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
                style={{
                  padding: "2px 8px",
                  fontSize: 12,
                  borderRadius: 9999,
                  border: "1px solid",
                  cursor: "pointer",
                  transition: "background 67ms ease",
                  ...(selectedTags.includes(tag)
                    ? { background: "var(--fill-accent-default)", color: "#fff", borderColor: "var(--fill-accent-default)" }
                    : { background: "transparent", color: "var(--text-secondary)", borderColor: "var(--stroke-control-secondary)" }),
                }}
              >
                {tag}
              </button>
            ))}
          </div>
        )}

        {/* List */}
        <div style={{ flex: 1, overflowY: "auto" }}>
          {filtered.length === 0 ? (
            <div style={{ padding: 24, textAlign: "center", fontSize: 13, color: "var(--text-tertiary)" }}>
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
                <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 8 }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
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
                        style={{
                          width: "100%",
                          fontSize: 13,
                          fontWeight: 600,
                          background: "transparent",
                          border: "none",
                          borderBottom: "1px solid var(--fill-accent-default)",
                          outline: "none",
                          color: "var(--text-primary)",
                        }}
                      />
                    ) : (
                      <p
                        style={{
                          fontSize: 13,
                          fontWeight: 600,
                          color: "var(--text-primary)",
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                          whiteSpace: "nowrap",
                        }}
                      >
                        {transcript.title || "Naamloze opname"}
                      </p>
                    )}
                    <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 2 }}>
                      {timeAgo(transcript.created_at)}
                    </p>
                    {/* Preview text */}
                    {transcript.notule_html && (
                      <p
                        style={{
                          fontSize: 12,
                          color: "var(--text-secondary)",
                          marginTop: 4,
                          lineHeight: 1.4,
                          display: "-webkit-box",
                          WebkitLineClamp: 2,
                          WebkitBoxOrient: "vertical",
                          overflow: "hidden",
                        }}
                      >
                        {stripHtml(transcript.notule_html)}
                      </p>
                    )}
                    {/* Status badges */}
                    <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 6, flexWrap: "wrap" }}>
                      {transcript.notule_html && (
                        <span className="status-badge-success">Notule beschikbaar</span>
                      )}
                      {transcript.tags.slice(0, 2).map((tag) => (
                        <span
                          key={tag}
                          style={{
                            padding: "1px 6px",
                            fontSize: 11,
                            background: "var(--fill-control-secondary)",
                            color: "var(--text-secondary)",
                            borderRadius: "var(--radius-sm)",
                          }}
                        >
                          {tag}
                        </span>
                      ))}
                    </div>
                  </div>
                  {/* Three-dot menu */}
                  <button
                    onClick={(e) => handleThreeDotMenu(e, transcript)}
                    style={{
                      width: 28,
                      height: 28,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      background: "transparent",
                      border: "none",
                      color: "var(--text-tertiary)",
                      cursor: "pointer",
                      borderRadius: "var(--radius-sm)",
                      flexShrink: 0,
                      marginTop: 2,
                    }}
                    onMouseEnter={(e) => {
                      (e.currentTarget as HTMLButtonElement).style.background = "var(--fill-control-secondary)";
                    }}
                    onMouseLeave={(e) => {
                      (e.currentTarget as HTMLButtonElement).style.background = "transparent";
                    }}
                  >
                    <MoreHorizontal24Regular style={{ fontSize: 16 }} />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Detail panel */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        {selected ? (
          <>
            {/* Top bar */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "8px 16px",
                borderBottom: "1px solid var(--stroke-divider)",
                background: "var(--surface-card)",
                flexShrink: 0,
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <IconButton onClick={() => setSelectedId(null)} title="Terug">
                  <ArrowLeft24Regular style={{ fontSize: 18 }} />
                </IconButton>
                <IconButton
                  onClick={() => handleRegenerate(selected)}
                  disabled={regeneratingId === selected.id}
                  title="Hertranscribeer"
                >
                  <Timer24Regular
                    style={{
                      fontSize: 18,
                      ...(regeneratingId === selected.id && { animation: "spin 1s linear infinite" }),
                    }}
                  />
                </IconButton>
                <span
                  style={{
                    fontSize: 12,
                    color: "var(--text-secondary)",
                    cursor: regeneratingId === selected.id ? "not-allowed" : "pointer",
                  }}
                  onClick={() => {
                    if (regeneratingId !== selected.id) handleRegenerate(selected);
                  }}
                >
                  Hertranscribeer
                </span>
              </div>
              <IconButton
                onClick={(e) => handleThreeDotMenu(e as unknown as React.MouseEvent, selected)}
                title="Meer opties"
              >
                <MoreHorizontal24Regular style={{ fontSize: 18 }} />
              </IconButton>
            </div>

            {/* Detail header info */}
            <div
              style={{
                padding: "12px 16px 0",
                flexShrink: 0,
              }}
            >
              <h2 style={{ fontSize: 16, fontWeight: 600, color: "var(--text-primary)", margin: 0 }}>
                {selected.title || "Naamloze opname"}
              </h2>
              <p style={{ fontSize: 12, color: "var(--text-tertiary)", marginTop: 2 }}>
                {formatDate(selected.created_at)} · {formatDuration(selected.duration_seconds)}
                {selected.profile_name && ` · ${selected.profile_name}`}
              </p>

              {/* Tags with + Tag chip */}
              <div style={{ display: "flex", gap: 6, marginTop: 8, flexWrap: "wrap", alignItems: "center" }}>
                {selected.tags.map((tag) => (
                  <span
                    key={tag}
                    style={{
                      padding: "2px 8px",
                      fontSize: 12,
                      background: "var(--fill-control-secondary)",
                      color: "var(--text-secondary)",
                      borderRadius: "var(--radius-pill)",
                    }}
                  >
                    {tag}
                  </span>
                ))}
                <button
                  style={{
                    padding: "2px 8px",
                    fontSize: 12,
                    background: "transparent",
                    color: "var(--text-tertiary)",
                    border: "1px dashed var(--stroke-control-secondary)",
                    borderRadius: "var(--radius-pill)",
                    cursor: "pointer",
                  }}
                  title="Tag toevoegen"
                >
                  + Tag
                </button>
              </div>
            </div>

            {/* Tab switch */}
            <div className="tab-bar" style={{ margin: "12px 16px 0" }}>
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
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
                padding: "8px 16px",
                flexShrink: 0,
              }}
            >
              <button
                className="btn btn-amber"
                onClick={() => handleExport(selected, "html")}
                disabled={!selected.notule_html}
                style={{ fontSize: 13 }}
              >
                <Share24Regular style={{ fontSize: 16 }} />
                Deel & Exporteer
              </button>
              <IconButton onClick={() => startEdit(selected)} title="Bewerken">
                <Edit24Regular style={{ fontSize: 18 }} />
              </IconButton>
            </div>

            {/* Content area */}
            <div style={{ flex: 1, overflowY: "auto", padding: "0 16px 24px" }}>
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
                    <div style={{ textAlign: "center", paddingTop: 48 }}>
                      <p style={{ color: "var(--text-tertiary)", marginBottom: 16, fontSize: 14 }}>
                        Geen notulen beschikbaar
                      </p>
                      <button
                        onClick={() => handleRegenerate(selected)}
                        className="btn btn-accent"
                        style={{ padding: "8px 20px" }}
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
                  <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
                    <button
                      className="btn btn-secondary"
                      onClick={() => {
                        setActiveTab("notule");
                      }}
                      style={{ fontSize: 13 }}
                    >
                      <Dismiss24Regular style={{ fontSize: 16 }} />
                      Sluiten
                    </button>
                    {selected.raw_transcription && (
                      <button
                        className="btn btn-secondary"
                        onClick={() => handleCopyTranscription(selected.raw_transcription!)}
                        style={{ fontSize: 13 }}
                      >
                        <Copy24Regular style={{ fontSize: 16 }} />
                        Kopieer
                      </button>
                    )}
                  </div>

                  {selected.raw_transcription ? (
                    <div className="card" style={{ padding: 16 }}>
                      <p
                        style={{
                          fontSize: 14,
                          fontWeight: 600,
                          color: "var(--text-accent)",
                          marginBottom: 8,
                        }}
                      >
                        {selected.title || "Naamloze opname"}
                      </p>
                      <p
                        style={{
                          fontSize: 11,
                          fontWeight: 600,
                          color: "var(--text-tertiary)",
                          letterSpacing: "0.05em",
                          marginBottom: 8,
                          textTransform: "uppercase",
                        }}
                      >
                        RUWE TRANSCRIPTIE
                      </p>
                      <div
                        style={{
                          fontSize: 13,
                          color: "var(--text-secondary)",
                          whiteSpace: "pre-wrap",
                          lineHeight: 1.6,
                        }}
                      >
                        {selected.raw_transcription}
                      </div>
                    </div>
                  ) : (
                    <div style={{ textAlign: "center", paddingTop: 48 }}>
                      <p style={{ color: "var(--text-tertiary)", fontSize: 14 }}>
                        Geen transcriptie beschikbaar
                      </p>
                    </div>
                  )}
                </div>
              )}
            </div>
          </>
        ) : (
          <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>
            <div style={{ textAlign: "center" }}>
              <Tag24Regular style={{ fontSize: 48, color: "var(--stroke-divider)", display: "block", margin: "0 auto 12px" }} />
              <p style={{ color: "var(--text-tertiary)", fontSize: 13 }}>
                Selecteer een notule om te bekijken
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Context menu */}
      {contextMenu && (
        <div
          style={{
            position: "fixed",
            left: contextMenu.x,
            top: contextMenu.y,
            zIndex: 1000,
            background: "var(--surface-flyout)",
            border: "1px solid var(--stroke-card)",
            borderRadius: "var(--radius-md)",
            boxShadow: "var(--shadow-flyout)",
            padding: "4px 0",
            minWidth: 160,
          }}
          onClick={(e) => e.stopPropagation()}
        >
          <ContextMenuItem
            icon={<Edit24Regular style={{ fontSize: 16 }} />}
            label="Bewerken"
            onClick={() => { startEdit(contextMenu.transcript); setContextMenu(null); }}
          />
          <ContextMenuItem
            icon={<ArrowDownload24Regular style={{ fontSize: 16 }} />}
            label="Exporteren"
            onClick={() => { handleExport(contextMenu.transcript, "html"); setContextMenu(null); }}
          />
          <ContextMenuItem
            icon={<Tag24Regular style={{ fontSize: 16 }} />}
            label="Tags beheren"
            onClick={() => setContextMenu(null)}
          />
          <ContextMenuItem
            icon={<ArrowSync24Regular style={{ fontSize: 16 }} />}
            label="Hertranscribeer"
            onClick={() => { handleRegenerate(contextMenu.transcript); setContextMenu(null); }}
          />
          <div style={{ height: 1, background: "var(--stroke-divider)", margin: "4px 0" }} />
          <ContextMenuItem
            icon={<Delete24Regular style={{ fontSize: 16 }} />}
            label="Verwijderen"
            danger
            onClick={() => { handleDelete(contextMenu.transcript); setContextMenu(null); }}
          />
        </div>
      )}
    </div>
  );
}

function IconButton({
  children, onClick, title, disabled, danger,
}: {
  children: React.ReactNode;
  onClick: (e: React.MouseEvent) => void;
  title?: string;
  disabled?: boolean;
  danger?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      title={title}
      style={{
        width: 32,
        height: 32,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "transparent",
        border: "none",
        color: danger ? "var(--text-tertiary)" : "var(--text-tertiary)",
        cursor: disabled ? "not-allowed" : "pointer",
        borderRadius: "var(--radius-sm)",
        opacity: disabled ? 0.4 : 1,
        transition: "background 67ms ease, color 67ms ease",
      }}
      onMouseEnter={(e) => {
        if (!disabled) {
          (e.currentTarget as HTMLButtonElement).style.background = danger
            ? "rgba(188, 0, 22, 0.08)"
            : "var(--fill-control-secondary)";
          (e.currentTarget as HTMLButtonElement).style.color = danger
            ? "var(--text-error)"
            : "var(--text-primary)";
        }
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLButtonElement).style.background = "transparent";
        (e.currentTarget as HTMLButtonElement).style.color = "var(--text-tertiary)";
      }}
    >
      {children}
    </button>
  );
}

function ContextMenuItem({
  icon, label, danger, onClick,
}: {
  icon: React.ReactNode;
  label: string;
  danger?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      style={{
        width: "100%",
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "7px 14px",
        fontSize: 13,
        background: "transparent",
        border: "none",
        color: danger ? "var(--text-error)" : "var(--text-primary)",
        cursor: "pointer",
        textAlign: "left",
        transition: "background 67ms ease",
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLButtonElement).style.background = "var(--fill-control-secondary)";
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLButtonElement).style.background = "transparent";
      }}
    >
      {icon}
      {label}
    </button>
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
