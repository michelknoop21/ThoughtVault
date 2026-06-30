import { useState, useRef, useEffect } from "react";
import {
  ArrowLeft24Regular,
  ArrowSync24Regular,
  Edit24Regular,
  Checkmark24Regular,
  Dismiss24Regular,
  Share24Regular,
  DocumentPdf24Regular,
  TextDescription24Regular,
  Code24Regular,
  Copy24Regular,
  ArrowDownload24Regular,
  Delete24Regular,
  Tag24Regular,
  Document24Regular,
  Clipboard24Regular,
  Sparkle24Regular,
  Notebook24Regular,
} from "@fluentui/react-icons";
import DOMPurify from "dompurify";
import { marked } from "marked";
import type { Transcript } from "../../types";

type DetailTab = "notule" | "transcriptie";

interface TranscriptDetailProps {
  transcript: Transcript;
  regeneratingId: string | null;
  onBack: () => void;
  onRegenerate: (transcript: Transcript) => void;
  onDelete: (transcript: Transcript) => void;
  onUpdateTitle: (id: string, title: string) => Promise<void>;
  onSaveNotule: (id: string, html: string) => Promise<void>;
  onCopy: (text: string) => void;
  onExportPDF: (transcript: Transcript) => void;
  onExportTXT: (transcript: Transcript) => void;
  onExportMarkdown: (transcript: Transcript) => void;
  onExportHTML: (transcript: Transcript) => void;
  onExportObsidian: (transcript: Transcript) => void;
  onOpenTags: (id: string) => void;
  onGenerateTitle: (transcript: Transcript) => void;
}

export function TranscriptDetail({
  transcript,
  regeneratingId,
  onBack,
  onRegenerate,
  onDelete,
  onUpdateTitle,
  onSaveNotule,
  onCopy,
  onExportPDF,
  onExportTXT,
  onExportMarkdown,
  onExportHTML,
  onExportObsidian,
  onOpenTags,
  onGenerateTitle,
}: TranscriptDetailProps) {
  const [detailTab, setDetailTab] = useState<DetailTab>("notule");
  const [isEditingTitle, setIsEditingTitle] = useState(false);
  const [editTitle, setEditTitle] = useState("");
  const [isEditingNotule, setIsEditingNotule] = useState(false);
  const [editedHTML, setEditedHTML] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [exportOpen, setExportOpen] = useState(false);
  const [deleteConfirm, setDeleteConfirm] = useState(false);
  const titleInputRef = useRef<HTMLInputElement>(null);
  const editorRef = useRef<HTMLDivElement>(null);
  const exportRef = useRef<HTMLDivElement>(null);

  const hasNotule = !!(transcript.notule_html || transcript.has_notes);
  const hasTranscription = !!(transcript.raw_transcription || transcript.has_transcription);
  const hasBothTabs = hasNotule && hasTranscription;
  const isRegenerating = regeneratingId === transcript.id;

  // Auto-select tab based on available content
  useEffect(() => {
    if (hasNotule) setDetailTab("notule");
    else if (hasTranscription) setDetailTab("transcriptie");
  }, [transcript.id]);

  // Close export menu on outside click
  useEffect(() => {
    if (!exportOpen) return;
    function handleClick(e: MouseEvent) {
      if (exportRef.current && !exportRef.current.contains(e.target as Node)) setExportOpen(false);
    }
    document.addEventListener("click", handleClick);
    return () => document.removeEventListener("click", handleClick);
  }, [exportOpen]);

  // Title editing
  function startTitleEdit() {
    setEditTitle(transcript.title || "");
    setIsEditingTitle(true);
    setTimeout(() => titleInputRef.current?.focus(), 0);
  }

  async function saveTitleEdit() {
    if (editTitle.trim() && editTitle !== transcript.title) {
      await onUpdateTitle(transcript.id, editTitle.trim());
    }
    setIsEditingTitle(false);
  }

  // Notule editing
  function startNotuleEdit() {
    setEditedHTML(transcript.notule_html || "");
    setIsEditingNotule(true);
  }

  async function saveNotuleEdit() {
    if (!editedHTML.trim()) return;
    setIsSaving(true);
    try {
      await onSaveNotule(transcript.id, editedHTML);
      setIsEditingNotule(false);
    } finally {
      setIsSaving(false);
    }
  }

  const sanitizedNotule = transcript.notule_html
    ? DOMPurify.sanitize(
        transcript.notule_html.startsWith("<")
          ? transcript.notule_html
          : (marked(transcript.notule_html) as string)
      )
    : "";

  return (
    <div className="td-panel">
      {/* Toolbar — single compact bar */}
      <div className="td-toolbar">
        <button className="td-toolbar-btn" onClick={onBack} title="Terug">
          <ArrowLeft24Regular style={{ fontSize: 18 }} />
        </button>

        <div className="td-toolbar-separator" />

        {/* Tab toggle (only if both exist) */}
        {hasBothTabs && (
          <div className="td-tab-toggle">
            <button
              className={`td-tab-btn${detailTab === "notule" ? " active" : ""}`}
              onClick={() => { setDetailTab("notule"); setIsEditingNotule(false); }}
            >
              Notule
            </button>
            <button
              className={`td-tab-btn${detailTab === "transcriptie" ? " active" : ""}`}
              onClick={() => { setDetailTab("transcriptie"); setIsEditingNotule(false); }}
            >
              Transcriptie
            </button>
          </div>
        )}

        <div className="td-toolbar-spacer" />

        {/* Actions */}
        {detailTab === "notule" && (
          <>
            {isEditingNotule ? (
              <>
                <button className="td-toolbar-btn td-toolbar-btn-accent td-toolbar-btn-labeled" onClick={saveNotuleEdit} disabled={isSaving}>
                  <Checkmark24Regular style={{ fontSize: 15 }} />
                  <span>{isSaving ? "Opslaan..." : "Opslaan"}</span>
                </button>
                <button className="td-toolbar-btn td-toolbar-btn-labeled" onClick={() => setIsEditingNotule(false)} disabled={isSaving}>
                  <Dismiss24Regular style={{ fontSize: 15 }} />
                  <span>Annuleren</span>
                </button>
              </>
            ) : (
              <>
                <button className="td-toolbar-btn td-toolbar-btn-labeled" onClick={startNotuleEdit} disabled={!transcript.notule_html} title="Notule bewerken">
                  <Edit24Regular style={{ fontSize: 15 }} />
                  <span>Bewerken</span>
                </button>
                <div className="td-toolbar-separator" />
                <button className="td-toolbar-btn td-toolbar-btn-labeled" onClick={() => onRegenerate(transcript)} disabled={isRegenerating} title="Notulen opnieuw genereren met AI">
                  <ArrowSync24Regular style={{ fontSize: 15, animation: isRegenerating ? "spin 1s linear infinite" : undefined }} />
                  <span>Regenereer</span>
                </button>
                <button className="td-toolbar-btn td-toolbar-btn-labeled" onClick={() => onGenerateTitle(transcript)} disabled={!transcript.notule_html} title="Titel genereren uit notule-inhoud">
                  <Sparkle24Regular style={{ fontSize: 15 }} />
                  <span>Titel</span>
                </button>
              </>
            )}
          </>
        )}

        {detailTab === "transcriptie" && (
          <button
            className="td-toolbar-btn td-toolbar-btn-labeled"
            onClick={() => transcript.raw_transcription && onCopy(transcript.raw_transcription)}
            disabled={!transcript.raw_transcription}
            title="Kopieer transcriptie"
          >
            <Copy24Regular style={{ fontSize: 15 }} />
            <span>Kopieer</span>
          </button>
        )}

        <div className="td-toolbar-separator" />

        {/* Export dropdown */}
        <div className="td-export-wrap" ref={exportRef}>
          <button className="td-toolbar-btn td-toolbar-btn-labeled" onClick={() => setExportOpen(!exportOpen)} title="Exporteren">
            <Share24Regular style={{ fontSize: 15 }} />
            <span>Export</span>
          </button>
          {exportOpen && (
            <div className="td-export-menu">
              {transcript.notule_html && (
                <>
                  <button className="td-export-item" onClick={() => { onExportPDF(transcript); setExportOpen(false); }}>
                    <DocumentPdf24Regular style={{ fontSize: 15 }} /> PDF
                  </button>
                  <button className="td-export-item" onClick={() => { onExportMarkdown(transcript); setExportOpen(false); }}>
                    <Code24Regular style={{ fontSize: 15 }} /> Markdown
                  </button>
                  <button className="td-export-item" onClick={() => { onExportHTML(transcript); setExportOpen(false); }}>
                    <ArrowDownload24Regular style={{ fontSize: 15 }} /> HTML
                  </button>
                  <button className="td-export-item" onClick={() => { onExportObsidian(transcript); setExportOpen(false); }}>
                    <Notebook24Regular style={{ fontSize: 15 }} /> Obsidian
                  </button>
                </>
              )}
              <button className="td-export-item" onClick={() => { onExportTXT(transcript); setExportOpen(false); }}>
                <TextDescription24Regular style={{ fontSize: 15 }} /> TXT
              </button>
              {transcript.notule_html && (
                <>
                  <div className="td-export-divider" />
                  <button className="td-export-item" onClick={() => { onCopy(stripHtml(transcript.notule_html!)); setExportOpen(false); }}>
                    <Copy24Regular style={{ fontSize: 15 }} /> Kopieer tekst
                  </button>
                </>
              )}
            </div>
          )}
        </div>

        <button className="td-toolbar-btn td-toolbar-btn-labeled" onClick={() => onOpenTags(transcript.id)} title="Tags beheren">
          <Tag24Regular style={{ fontSize: 15 }} />
          <span>Tags</span>
        </button>

        <button className="td-toolbar-btn td-toolbar-btn-danger" onClick={() => setDeleteConfirm(true)} title="Verwijderen">
          <Delete24Regular style={{ fontSize: 15 }} />
        </button>
      </div>

      {/* Document content */}
      <div className="td-scroll">
        <div className="td-document">
          <div className="td-doc-accent" />

          {/* Editable title */}
          <div className="td-doc-header">
            {isEditingTitle ? (
              <input
                ref={titleInputRef}
                className="td-title-input"
                value={editTitle}
                onChange={(e) => setEditTitle(e.target.value)}
                onBlur={saveTitleEdit}
                onKeyDown={(e) => {
                  if (e.key === "Enter") saveTitleEdit();
                  if (e.key === "Escape") setIsEditingTitle(false);
                }}
              />
            ) : (
              <h2 className="td-doc-title" onClick={startTitleEdit} title="Klik om te bewerken">
                {transcript.title || "Naamloze opname"}
                <Edit24Regular className="td-title-edit-icon" />
              </h2>
            )}
            <div className="td-doc-meta">
              <span>{formatDate(transcript.created_at)}</span>
              {transcript.duration_seconds > 0 && (
                <>
                  <span className="td-meta-sep">&middot;</span>
                  <span>{formatDuration(transcript.duration_seconds)}</span>
                </>
              )}
              {transcript.profile_name && (
                <>
                  <span className="td-meta-sep">&middot;</span>
                  <span className="td-meta-profile">{transcript.profile_name}</span>
                </>
              )}
            </div>
            {transcript.tags.length > 0 && (
              <div className="td-doc-tags">
                {transcript.tags.map((tag) => (
                  <span key={tag} className="td-tag">{tag}</span>
                ))}
              </div>
            )}
          </div>

          <div className="td-doc-divider" />

          {/* Content */}
          {detailTab === "notule" ? (
            transcript.notule_html ? (
              isEditingNotule ? (
                <div
                  ref={editorRef}
                  className="prose td-doc-body td-doc-editing"
                  contentEditable
                  role="textbox"
                  aria-label="Notule bewerken"
                  aria-multiline="true"
                  suppressContentEditableWarning
                  dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(editedHTML) }}
                  onInput={(e) => setEditedHTML((e.target as HTMLDivElement).innerHTML)}
                />
              ) : (
                <div
                  className="prose td-doc-body"
                  dangerouslySetInnerHTML={{ __html: sanitizedNotule }}
                />
              )
            ) : (
              <div className="td-empty-content">
                <Document24Regular style={{ fontSize: 40, opacity: 0.3 }} />
                <p>Geen notulen beschikbaar</p>
                <button className="btn btn-accent" onClick={() => onRegenerate(transcript)}>
                  Notulen genereren
                </button>
              </div>
            )
          ) : (
            transcript.raw_transcription ? (
              <div className="td-doc-body td-transcription">
                {transcript.raw_transcription}
              </div>
            ) : (
              <div className="td-empty-content">
                <Clipboard24Regular style={{ fontSize: 40, opacity: 0.3 }} />
                <p>Geen transcriptie beschikbaar</p>
              </div>
            )
          )}
        </div>
      </div>

      {/* Delete confirm */}
      {deleteConfirm && (
        <div className="td-overlay" onClick={() => setDeleteConfirm(false)}>
          <div className="td-confirm" onClick={(e) => e.stopPropagation()}>
            <p className="td-confirm-title">Verwijderen?</p>
            <p className="td-confirm-text">
              "{transcript.title || "Naamloze opname"}" wordt definitief verwijderd.
            </p>
            <div className="td-confirm-actions">
              <button className="btn btn-secondary btn-sm" onClick={() => setDeleteConfirm(false)}>Annuleren</button>
              <button
                className="btn btn-sm"
                style={{ color: "var(--text-error)", borderColor: "rgba(188,0,22,0.3)" }}
                onClick={() => { onDelete(transcript); setDeleteConfirm(false); }}
              >
                Verwijderen
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// --- Utilities ---

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
