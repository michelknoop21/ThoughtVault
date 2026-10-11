import { useConfirmation } from "../components/ui/useConfirmation";
import { DesktopDialog } from "../components/ui/DesktopDialog";
import { useEffect, useState, useRef, useCallback } from "react";
import {
  ArrowDownload24Regular,
  Tag24Regular,
  ArrowSync24Regular,
  Delete24Regular,
  Document24Regular,
  Dismiss24Regular,
  Add24Regular,
} from "../components/ui/StudioIcons";
import DOMPurify from "dompurify";
import { useTranscriptsStore } from "../stores/transcriptsStore";
import { useLocalTranscriptsStore, isLocalId } from "../stores/localTranscriptsStore";
import { useSettingsStore } from "../stores/settingsStore";
import { useProfilesStore } from "../stores/profilesStore";
import { useRecordingStore } from "../stores/recordingStore";
import { LLMService } from "../services/llm";
import { prepareNotuleHtml } from "../services/notulePresentation";
import { hasUsableNotule, hasUsableTranscription } from "../services/notuleValidation";
import { extractTitle } from "../services/titleExtractor";
import { api } from "../services/api";
import { createSSEClient } from "../services/sse";
import { persistNotesSection } from "../services/uploadAndTrack";
import { exportToObsidian, importFromObsidian, acknowledgeObsidianImport } from "../services/obsidian";
import { htmlToMarkdown, htmlToPlainText } from "../utils/htmlToMarkdown";
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
  const { confirm, confirmation } = useConfirmation();
  const {
    transcripts, selectedId, searchQuery, selectedTags,
    setTranscripts, updateTranscript, deleteTranscript,
    setSelectedId, setSearchQuery, setSelectedTags, setIsLoading,
  } = useTranscriptsStore();
  const [contextMenu, setContextMenu] = useState<ContextMenu | null>(null);
  const [regeneratingId, setRegeneratingId] = useState<string | null>(null);
  const [regenerateTarget, setRegenerateTarget] = useState<Transcript | null>(null);
  const [regenerateProfileId, setRegenerateProfileId] = useState("");
  const [tagsDialogId, setTagsDialogId] = useState<string | null>(null);
  const [newTagInput, setNewTagInput] = useState("");
  const [availableTags, setAvailableTags] = useState<string[]>([]);
  const toast = useToast();
  const isLoading = useTranscriptsStore((s) => s.isLoading);
  const lastLoadRef = useRef<number>(0);

  const refreshTranscripts = useCallback(async () => {
    lastLoadRef.current = Date.now();
    setIsLoading(true);
    // Locally generated transcripts always show, even with no server/login.
    const local = useLocalTranscriptsStore.getState().items;
    try {
      if (useSettingsStore.getState().processing_mode === "local") {
        setTranscripts(local);
        return;
      }
      const data = await api.getTranscripts();
      setTranscripts([...local, ...data]);
    } catch (err) {
      setTranscripts(local);
      // In local mode there is no backend, so a failed fetch is expected.
      if (useSettingsStore.getState().processing_mode !== "local") {
        const msg = err instanceof Error ? err.message : "Laden mislukt";
        toast.show("Documenten laden mislukt: " + msg, "error");
      }
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
    // Local records carry full detail already — nothing to fetch.
    if (isLocalId(id)) return;
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
      if (isLocalId(transcript.id)) {
        await useLocalTranscriptsStore.getState().remove(transcript.id);
      } else {
        await api.deleteTranscript(transcript.id);
      }
      deleteTranscript(transcript.id);
      toast.show("Verwijderd", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Verwijderen mislukt", "error");
    }
  }

  // --- Bulk delete ---
  async function handleBulkDelete(ids: string[]) {
    const localIds = ids.filter(isLocalId);
    const serverIds = ids.filter((id) => !isLocalId(id));
    try {
      for (const id of localIds) await useLocalTranscriptsStore.getState().remove(id);
      if (serverIds.length) await api.bulkDeleteTranscripts(serverIds);
      ids.forEach((id) => deleteTranscript(id));
      toast.show(`${ids.length} items verwijderd`, "success");
    } catch {
      toast.show("Bulk verwijderen mislukt", "error");
    }
  }

  // --- Title update ---
  async function handleUpdateTitle(id: string, title: string) {
    try {
      if (isLocalId(id)) {
        await useLocalTranscriptsStore.getState().update(id, { title });
        updateTranscript(id, { title });
        return;
      }
      const updated = await api.updateTranscript(id, { title });
      updateTranscript(id, { title: updated.title || title });
    } catch {
      toast.show("Titel opslaan mislukt", "error");
      throw new Error("Titel opslaan mislukt");
    }
  }

  // --- Notule save ---
  async function handleSaveNotule(id: string, html: string, syncObsidian = true) {
    try {
      if (isLocalId(id)) {
        await useLocalTranscriptsStore.getState().update(id, { notule_html: html });
        updateTranscript(id, { notule_html: html });
        toast.show("Notule opgeslagen", "success");
        const settings = useSettingsStore.getState();
        if (syncObsidian && settings.obsidian_enabled) {
          const saved = useTranscriptsStore.getState().transcripts.find((item) => item.id === id);
          if (saved) void exportToObsidian(saved, settings).catch((error) =>
            toast.show(error instanceof Error ? error.message : "Obsidian-sync mislukt", "error"));
        }
        return;
      }
      await api.updateNotuleHTML(id, html);
      updateTranscript(id, { notule_html: html });
      toast.show("Notule opgeslagen", "success");
      const settings = useSettingsStore.getState();
      if (syncObsidian && settings.obsidian_enabled) {
        const saved = useTranscriptsStore.getState().transcripts.find((item) => item.id === id);
        if (saved) void exportToObsidian(saved, settings).catch((error) =>
          toast.show(error instanceof Error ? error.message : "Obsidian-sync mislukt", "error"));
      }
    } catch {
      toast.show("Opslaan mislukt", "error");
      throw new Error("Opslaan mislukt");
    }
  }

  // --- Regenerate ---
  function requestRegenerate(transcript: Transcript) {
    const profiles = useProfilesStore.getState().profiles;
    const current = profiles.find((p) => p.name === transcript.profile_name || p.id === transcript.profile_name);
    setRegenerateProfileId(current?.id ?? profiles[0]?.id ?? "");
    setRegenerateTarget(transcript);
  }

  async function handleRegenerate(transcript: Transcript, profileId: string) {
    if (regeneratingId === transcript.id) return;
    const profile = useProfilesStore.getState().profiles.find((p) => p.id === profileId);
    if (!profile) { toast.show("Kies een notulentemplate", "error"); return; }
    setRegenerateTarget(null);
    const tasks = useRecordingStore.getState();
    const taskId = `regen-${transcript.id}`;
    tasks.removeBackgroundTask(taskId);
    tasks.addBackgroundTask({ task_id: taskId, status: "generating", progress: 10,
      mode: "microphone", profile_id: profileId, extracted_title: transcript.title,
      created_at: new Date().toISOString(), message: `Notulen met ${profile.name}` });
    // Local records: re-run the on-device LLM over the stored transcription.
    if (isLocalId(transcript.id)) {
      const transcription = transcript.raw_transcription ?? "";
      if (!hasUsableTranscription(transcription)) {
        tasks.updateBackgroundTask(taskId, { status: "failed", error_message: "Geen bruikbare transcriptie beschikbaar" });
        toast.show("Geen bruikbare transcriptie beschikbaar", "error");
        return;
      }
      setRegeneratingId(transcript.id);
      try {
        const html = await LLMService.generateNotulen(transcription, profile,
          () => tasks.updateBackgroundTask(taskId, { progress: 60 }), [], transcript.quick_note);
        if (!hasUsableNotule(html)) throw new Error("Geen bruikbare notule gegenereerd");
        const title = extractTitle(html) || transcript.title;
        await useLocalTranscriptsStore.getState().update(transcript.id, { notule_html: html, title, profile_name: profile.name, profile_id: profile.id });
        updateTranscript(transcript.id, { notule_html: html, title, profile_name: profile.name, profile_id: profile.id });
        tasks.updateBackgroundTask(taskId, { status: "completed", progress: 100 });
        const settings = useSettingsStore.getState();
        if (settings.obsidian_enabled) {
          const saved = useLocalTranscriptsStore.getState().items.find((item) => item.id === transcript.id);
          if (saved) void exportToObsidian(saved, settings).catch((error) =>
            toast.show(error instanceof Error ? error.message : "Obsidian-sync mislukt", "error"));
        }
        toast.show("Notule opnieuw gegenereerd", "success");
      } catch (error) {
        tasks.updateBackgroundTask(taskId, { status: "failed", error_message: error instanceof Error ? error.message : "Regenereren mislukt" });
        toast.show("Regenereren mislukt", "error");
      } finally {
        setRegeneratingId(null);
      }
      return;
    }
    setRegeneratingId(transcript.id);
    try {
      const { task_id } = await api.regenerateNotule(transcript.id, profileId);
      const sseClient = createSSEClient(api.getStreamUrl(task_id));
      let finalStatus: string | undefined;
      sseClient.connect(
        (update) => {
          finalStatus = update.status;
          tasks.updateBackgroundTask(taskId, { status: update.status, progress: update.progress });
          if (update.notule_html) updateTranscript(transcript.id, { notule_html: update.notule_html });
          if (update.extracted_title) updateTranscript(transcript.id, { title: update.extracted_title });
        },
        () => { tasks.updateBackgroundTask(taskId, { status: "failed", error_message: "Verbinding met server verloren" }); setRegeneratingId(null); toast.show("Regenereren mislukt", "error"); },
        async () => {
          if (finalStatus === "failed" || finalStatus === "cancelled" || finalStatus === "error") {
            setRegeneratingId(null);
            toast.show("Regenereren mislukt", "error");
            return;
          }
          tasks.updateBackgroundTask(taskId, { status: "completed", progress: 100 });
          setRegeneratingId(null);
          setTimeout(async () => {
            try {
              const updated = await api.getTranscript(transcript.id);
              // The server wiped the Notities section when it regenerated.
              if (updated.notule_html) updated.notule_html = await persistNotesSection(transcript.task_id ?? transcript.id, updated.notule_html, profileId);
              updateTranscript(transcript.id, { title: updated.title, notule_html: updated.notule_html, profile_id: profileId, profile_name: profile?.name ?? updated.profile_name });
              const settings = useSettingsStore.getState();
              if (settings.obsidian_enabled && updated.notule_html) {
                await exportToObsidian(updated, settings);
              }
            } catch (error) {
              toast.show(error instanceof Error ? error.message : "Notule ophalen mislukt", "error");
            }
          }, 8000);
        }
      );
    } catch (error) {
      tasks.updateBackgroundTask(taskId, { status: "failed", error_message: error instanceof Error ? error.message : "Regenereren mislukt" });
      setRegeneratingId(null);
      toast.show("Regenereren mislukt", "error");
    }
  }

  // --- Generate title from notule content ---
  const SECTION_WORDS = new Set([
    "besluiten", "kernargumenten", "notulen", "samenvatting",
    "actiepunten", "agendapunten", "conclusie", "inleiding",
    "toelichting", "bijlagen", "vervolgstappen",
  ]);

  async function handleGenerateTitle(transcript: Transcript) {
    if (!transcript.notule_html) return;
    const tmp = document.createElement("div");
    tmp.innerHTML = transcript.notule_html;

    // Collect candidate titles in priority order
    const candidates: string[] = [];

    // 1. h4 subtitles (handleiding-profiel puts real title here)
    tmp.querySelectorAll("h4").forEach((el) => {
      const text = el.textContent?.trim();
      if (text && text.length > 5 && text.length < 120) candidates.push(text);
    });

    // 2. h1 headings only (h2/h3 are section headings)
    tmp.querySelectorAll("h1").forEach((el) => {
      const text = el.textContent?.trim();
      if (text && text.length > 3 && text.length < 120) candidates.push(text);
    });

    // 3. First bold/strong text (often a meeting title)
    tmp.querySelectorAll("strong, b").forEach((el) => {
      const text = el.textContent?.trim();
      if (text && text.length > 5 && text.length < 120) candidates.push(text);
    });

    // 4. First non-trivial paragraph
    tmp.querySelectorAll("p").forEach((el) => {
      const text = el.textContent?.trim();
      if (text && text.length > 10 && text.length < 120) {
        candidates.push(text.length > 80 ? text.slice(0, 77) + "..." : text);
      }
    });

    // Pick the first candidate that differs from current title and isn't a section word
    const currentLower = (transcript.title || "").toLowerCase();
    const newTitle = candidates.find(
      (c) => c.toLowerCase() !== currentLower && !SECTION_WORDS.has(c.toLowerCase())
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
    const title = document.createElement("span");
    title.textContent = transcript.title || "Notulen";
    const frame = document.createElement("iframe");
    frame.title = "Notule afdrukken";
    frame.style.cssText = "position:fixed;width:0;height:0;border:0";
    frame.onload = () => {
      const printWindow = frame.contentWindow;
      if (!printWindow) { frame.remove(); toast.show("Afdrukvenster openen mislukt", "error"); return; }
      printWindow.addEventListener("afterprint", () => frame.remove(), { once: true });
      printWindow.print();
    };
    frame.srcdoc = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${title.innerHTML}</title><style>body{font-family:'Segoe UI Variable','Segoe UI',system-ui,sans-serif;font-size:12pt;line-height:1.6;color:#1a1a1a;padding:20pt}h1{font-size:18pt;font-weight:700;color:#9048F0;margin-bottom:12pt}h2{font-size:14pt;font-weight:600;margin-top:16pt}h3{font-size:12pt;font-weight:600;margin-top:12pt}p{margin:6pt 0}ul,ol{margin:6pt 0;padding-left:20pt}li{margin:3pt 0}table{border-collapse:collapse;width:100%;margin:12pt 0}th,td{border:1px solid #ddd;padding:6pt 8pt;text-align:left}th{background:#f5f5f5;font-weight:600}</style></head><body><h1>${title.innerHTML}</h1><p style="color:#666;font-size:10pt">${formatDate(transcript.created_at)} &middot; ${formatDuration(transcript.duration_seconds)}</p>${DOMPurify.sanitize(prepareNotuleHtml(transcript.notule_html, transcript.title))}</body></html>`;
    document.body.append(frame);
  }

  function handleExportTXT(transcript: Transcript) {
    const content = transcript.notule_html
      ? htmlToPlainText(prepareNotuleHtml(transcript.notule_html, transcript.title))
      : transcript.raw_transcription;
    if (content) downloadFile(content, `${transcript.title || "notulen"}.txt`, "text/plain");
  }

  function handleExportMarkdown(transcript: Transcript) {
    if (!transcript.notule_html) return;
    downloadFile(htmlToMarkdown(prepareNotuleHtml(transcript.notule_html, transcript.title)), `${transcript.title || "notulen"}.md`, "text/markdown");
  }

  function handleExportHTML(transcript: Transcript) {
    if (!transcript.notule_html) return;
    const title = document.createElement("h1");
    title.textContent = transcript.title || "Notulen";
    downloadFile(title.outerHTML + prepareNotuleHtml(transcript.notule_html, transcript.title), `${transcript.title || "notulen"}.html`, "text/html");
  }

  async function handleExportObsidian(transcript: Transcript) {
    const settings = useSettingsStore.getState();
    try {
      await exportToObsidian(transcript, settings);
      toast.show("Geëxporteerd naar Obsidian", "success");
    } catch (err) {
      toast.show(err instanceof Error ? err.message : "Export naar Obsidian mislukt", "error");
    }
  }

  async function handleImportObsidian(transcript: Transcript) {
    const settings = useSettingsStore.getState();
    try {
      const { html, markdown } = await importFromObsidian(transcript, settings);
      if (html === transcript.notule_html) {
        acknowledgeObsidianImport(transcript, markdown, html);
        toast.show("Obsidian-versie is bijgewerkt", "success");
        return;
      }
      if (!await confirm("De versie uit Obsidian vervangt de huidige notule in ThoughtVault. Doorgaan?", "Notule vervangen", "Vervangen")) return;
      await handleSaveNotule(transcript.id, html, false);
      acknowledgeObsidianImport(transcript, markdown, html);
      toast.show("Wijzigingen uit Obsidian opgehaald", "success");
    } catch (error) {
      toast.show(error instanceof Error ? error.message : "Obsidian ophalen mislukt", "error");
    }
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
    if (isLocalId(transcriptId)) {
      setAvailableTags(Array.from(new Set(transcripts.flatMap((t) => t.tags))));
      return;
    }
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
      const t = transcripts.find((t) => t.id === transcriptId);
      if (t && !t.tags.includes(trimmed)) {
        if (isLocalId(transcriptId)) {
          await useLocalTranscriptsStore.getState().update(transcriptId, { tags: [...t.tags, trimmed] });
        } else {
          await api.updateTranscriptTags(transcriptId, [trimmed], []);
        }
        updateTranscript(transcriptId, { tags: [...t.tags, trimmed] });
      }
      setNewTagInput("");
    } catch {
      toast.show("Tag toevoegen mislukt", "error");
    }
  }

  async function handleRemoveTag(transcriptId: string, tag: string) {
    try {
      const t = transcripts.find((t) => t.id === transcriptId);
      if (t) {
        const tags = t.tags.filter((x) => x !== tag);
        if (isLocalId(transcriptId)) {
          await useLocalTranscriptsStore.getState().update(transcriptId, { tags });
        } else {
          await api.updateTranscriptTags(transcriptId, [], [tag]);
        }
        updateTranscript(transcriptId, { tags });
      }
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
    <div className={`tp-root desktop-notulen${selectedId ? " has-detail" : ""}`}>
      {confirmation}
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
          onRegenerate={requestRegenerate}
          onDelete={handleDelete}
          onUpdateTitle={handleUpdateTitle}
          onSaveNotule={handleSaveNotule}
          onCopy={handleCopy}
          onExportPDF={handleExportPDF}
          onExportTXT={handleExportTXT}
          onExportMarkdown={handleExportMarkdown}
          onExportHTML={handleExportHTML}
          onExportObsidian={handleExportObsidian}
          onImportObsidian={handleImportObsidian}
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
          <button className="context-menu-item" onClick={() => { requestRegenerate(contextMenu.transcript); setContextMenu(null); }}>
            <ArrowSync24Regular style={{ fontSize: 16 }} /> Regenereer notulen
          </button>
          <div className="context-menu-divider" />
          <button className="context-menu-item context-menu-item-danger" onClick={() => { handleDelete(contextMenu.transcript); setContextMenu(null); }}>
            <Delete24Regular style={{ fontSize: 16 }} /> Verwijderen
          </button>
        </div>
      )}

      {regenerateTarget && <DesktopDialog className="td-overlay" label="Notule opnieuw genereren" onClose={() => setRegenerateTarget(null)}>
        <div className="td-tags-dialog" onClick={(e) => e.stopPropagation()}>
          <h3 className="td-tags-title">Notulen regenereren</h3>
          <p className="text-caption">Kies het template voor de nieuwe notulen.</p>
          <select className="select" value={regenerateProfileId}
            onChange={(e) => setRegenerateProfileId(e.target.value)}>
            {useProfilesStore.getState().profiles.map((profile) =>
              <option key={profile.id} value={profile.id}>{profile.name}</option>)}
          </select>
          <div className="flex-row gap-8" style={{ justifyContent: "flex-end", marginTop: 16 }}>
            <button className="btn" onClick={() => setRegenerateTarget(null)}>Annuleren</button>
            <button className="btn btn-accent" onClick={() => void handleRegenerate(regenerateTarget, regenerateProfileId)}>Regenereren</button>
          </div>
        </div>
      </DesktopDialog>}

      {/* Tags dialog */}
      {tagsDialogId && (
        <DesktopDialog className="td-overlay" label="Tags beheren" onClose={() => setTagsDialogId(null)}>
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
        </DesktopDialog>
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

function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString("nl-NL", { day: "numeric", month: "short", year: "numeric" })
    + " om " + d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" });
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}
