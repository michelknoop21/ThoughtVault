import { useState, useRef, useCallback, useEffect } from "react";
import {
  Search24Regular,
  ArrowSync24Regular,
  MoreHorizontal24Regular,
  CheckboxChecked24Regular,
  CheckboxUnchecked24Regular,
  Delete24Regular,
} from "../ui/StudioIcons";
import type { Transcript } from "../../types";

type TimeFilter = "alles" | "vandaag" | "week" | "maand";

interface TranscriptsListProps {
  transcripts: Transcript[];
  selectedId: string | null;
  searchQuery: string;
  selectedTags: string[];
  isLoading: boolean;
  onSelect: (id: string) => void;
  onSearchChange: (query: string) => void;
  onTagToggle: (tag: string) => void;
  onRefresh: () => void;
  onContextMenu: (e: React.MouseEvent, transcript: Transcript) => void;
  onBulkDelete: (ids: string[]) => void;
}

const TIME_FILTERS: { key: TimeFilter; label: string }[] = [
  { key: "alles", label: "Alles" },
  { key: "vandaag", label: "Vandaag" },
  { key: "week", label: "Week" },
  { key: "maand", label: "Maand" },
];

function filterByTime(transcript: Transcript, filter: TimeFilter): boolean {
  if (filter === "alles") return true;
  const created = new Date(transcript.created_at);
  const now = new Date();
  if (filter === "vandaag") {
    return created.getDate() === now.getDate() &&
      created.getMonth() === now.getMonth() &&
      created.getFullYear() === now.getFullYear();
  }
  if (filter === "week") {
    const weekAgo = new Date(now);
    weekAgo.setDate(weekAgo.getDate() - 7);
    return created >= weekAgo;
  }
  const monthAgo = new Date(now);
  monthAgo.setMonth(monthAgo.getMonth() - 1);
  return created >= monthAgo;
}

function groupByDate(transcripts: Transcript[]): { label: string; items: Transcript[] }[] {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  const weekAgo = new Date(today);
  weekAgo.setDate(weekAgo.getDate() - 7);

  const groups: { label: string; items: Transcript[] }[] = [
    { label: "Vandaag", items: [] },
    { label: "Gisteren", items: [] },
    { label: "Deze week", items: [] },
    { label: "Eerder", items: [] },
  ];

  for (const t of transcripts) {
    const created = new Date(t.created_at);
    if (created >= today) groups[0].items.push(t);
    else if (created >= yesterday) groups[1].items.push(t);
    else if (created >= weekAgo) groups[2].items.push(t);
    else groups[3].items.push(t);
  }

  return groups.filter((g) => g.items.length > 0);
}

function timeAgo(dateStr: string): string {
  const now = new Date();
  const date = new Date(dateStr);
  const diffMs = now.getTime() - date.getTime();
  const diffMinutes = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMinutes < 1) return "Zojuist";
  if (diffMinutes < 60) return `${diffMinutes} min`;
  if (diffHours < 24) return `${diffHours} uur`;
  if (diffDays === 1) return "Gisteren";
  if (diffDays < 7) return `${diffDays}d`;
  return new Date(dateStr).toLocaleDateString("nl-NL", { day: "numeric", month: "short" });
}

function stripHtml(html: string): string {
  const tmp = document.createElement("div");
  tmp.innerHTML = html;
  return tmp.textContent || tmp.innerText || "";
}

export function TranscriptsList({
  transcripts,
  selectedId,
  searchQuery,
  selectedTags,
  isLoading,
  onSelect,
  onSearchChange,
  onTagToggle,
  onRefresh,
  onContextMenu,
  onBulkDelete,
}: TranscriptsListProps) {
  const [timeFilter, setTimeFilter] = useState<TimeFilter>("alles");
  const [bulkMode, setBulkMode] = useState(false);
  const [bulkSelected, setBulkSelected] = useState<Set<string>>(new Set());
  const searchRef = useRef<HTMLInputElement>(null);

  // Keyboard shortcut: Ctrl+F to focus search
  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if ((e.ctrlKey || e.metaKey) && e.key === "f") {
        e.preventDefault();
        searchRef.current?.focus();
      }
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, []);

  const filtered = transcripts.filter((t) => {
    const matchesSearch = !searchQuery || t.title.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesTags = selectedTags.length === 0 || selectedTags.some((tag) => t.tags.includes(tag));
    const matchesTime = filterByTime(t, timeFilter);
    return matchesSearch && matchesTags && matchesTime;
  });

  const allTags = Array.from(new Set(transcripts.flatMap((t) => t.tags)));
  const groups = groupByDate(filtered);

  const toggleBulk = useCallback((id: string) => {
    setBulkSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }, []);

  return (
    <div className={`tl-panel${!selectedId ? " tl-panel-full" : ""}`}>
      {/* Header */}
      <div className="tl-header">
        <div className="tl-header-row">
          <h1 className="tl-title">Documenten</h1>
          <div className="tl-header-actions">
            <button className="icon-btn icon-btn-sm" onClick={onRefresh} disabled={isLoading} title="Vernieuwen">
              <ArrowSync24Regular style={{ fontSize: 15, animation: isLoading ? "spin 1s linear infinite" : undefined }} />
            </button>
            <button
              className={`icon-btn icon-btn-sm${bulkMode ? " active" : ""}`}
              onClick={() => { setBulkMode(!bulkMode); setBulkSelected(new Set()); }}
              title="Selectiemodus"
              style={bulkMode ? { color: "var(--fill-accent)" } : undefined}
            >
              <CheckboxChecked24Regular style={{ fontSize: 15 }} />
            </button>
          </div>
        </div>

        <div className="tl-search">
          <Search24Regular style={{ fontSize: 14, color: "var(--text-tertiary)", flexShrink: 0 }} />
          <input
            ref={searchRef}
            type="text"
            placeholder="Zoeken..."
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
          />
        </div>

        <div className="tl-filters">
          {TIME_FILTERS.map((f) => (
            <button
              key={f.key}
              className={`tl-filter-pill${timeFilter === f.key ? " active" : ""}`}
              onClick={() => setTimeFilter(f.key)}
            >
              {f.label}
            </button>
          ))}
        </div>

        {allTags.length > 0 && (
          <div className="tl-tags">
            {allTags.map((tag) => (
              <button
                key={tag}
                className={`tl-tag-pill${selectedTags.includes(tag) ? " active" : ""}`}
                onClick={() => onTagToggle(tag)}
              >
                {tag}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Bulk bar */}
      {bulkMode && (
        <div className="tl-bulk-bar">
          <button className="btn btn-sm" onClick={() => {
            if (bulkSelected.size === filtered.length) setBulkSelected(new Set());
            else setBulkSelected(new Set(filtered.map((t) => t.id)));
          }}>
            {bulkSelected.size === filtered.length ? "Deselecteer" : "Alles"}
          </button>
          {bulkSelected.size > 0 && (
            <>
              <span className="tl-bulk-count">{bulkSelected.size} geselecteerd</span>
              <button className="btn btn-sm tl-bulk-delete" onClick={() => {
                onBulkDelete(Array.from(bulkSelected));
                setBulkSelected(new Set());
                setBulkMode(false);
              }}>
                <Delete24Regular style={{ fontSize: 12 }} /> Verwijder
              </button>
            </>
          )}
        </div>
      )}

      {/* List */}
      <div className="tl-scroll">
        {isLoading ? (
          <div className="tl-skeletons">
            {[1, 2, 3, 4, 5].map((i) => (
              <div key={i} className="tl-skeleton">
                <div className="skeleton skeleton-line skeleton-line-medium" />
                <div className="skeleton skeleton-line skeleton-line-short" />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="tl-empty">
            <p className="text-caption text-secondary">
              {searchQuery ? "Geen resultaten" : "Geen documenten"}
            </p>
          </div>
        ) : (
          groups.map((group) => (
            <div key={group.label} className="tl-group">
              <div className="tl-group-label">{group.label}</div>
              {group.items.map((t) => (
                <div
                  key={t.id}
                  className={`tl-item${selectedId === t.id ? " active" : ""}`}
                  role="button"
                  tabIndex={0}
                  aria-label={t.title || "Naamloze opname"}
                  onKeyDown={(event) => {
                    if (event.target !== event.currentTarget || !["Enter", " "].includes(event.key)) return;
                    event.preventDefault();
                    bulkMode ? toggleBulk(t.id) : onSelect(t.id);
                  }}
                  onClick={() => bulkMode ? toggleBulk(t.id) : onSelect(t.id)}
                  onContextMenu={(e) => onContextMenu(e, t)}
                >
                  {bulkMode && (
                    <span className="tl-item-check" style={{ color: bulkSelected.has(t.id) ? "var(--fill-accent)" : "var(--text-tertiary)" }}>
                      {bulkSelected.has(t.id)
                        ? <CheckboxChecked24Regular style={{ fontSize: 16 }} />
                        : <CheckboxUnchecked24Regular style={{ fontSize: 16 }} />
                      }
                    </span>
                  )}
                  <div className="tl-item-content">
                    <div className="tl-item-top">
                      <span className="tl-item-title">{t.title || "Naamloze opname"}</span>
                      <span className="tl-item-time">{timeAgo(t.created_at)}</span>
                    </div>
                    {(t.notule_html || t.raw_transcription) && (
                      <p className="tl-item-preview">
                        {t.notule_html ? stripHtml(t.notule_html) : t.raw_transcription?.slice(0, 120)}
                      </p>
                    )}
                    <div className="tl-item-meta-row">
                      <div className="tl-item-dots">
                        {(t.notule_html || t.has_notes) && <span className="tl-dot tl-dot-notule" title="Notule" />}
                        {(t.raw_transcription || t.has_transcription) && <span className="tl-dot tl-dot-transcript" title="Transcriptie" />}
                      </div>
                      {t.profile_name && (
                        <span className="tl-item-profile">{t.profile_name}</span>
                      )}
                      {t.tags.slice(0, 2).map((tag) => (
                        <span key={tag} className="tl-item-tag">{tag}</span>
                      ))}
                    </div>
                  </div>
                  {!bulkMode && (
                    <button
                      className="icon-btn icon-btn-sm tl-item-menu"
                      onClick={(e) => { e.stopPropagation(); onContextMenu(e, t); }}
                      title="Meer opties"
                    >
                      <MoreHorizontal24Regular style={{ fontSize: 15 }} />
                    </button>
                  )}
                </div>
              ))}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
