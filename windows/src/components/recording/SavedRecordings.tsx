import { useState, useEffect } from "react";
import {
  Delete24Regular,
  ArrowSync24Regular,
  BinRecycle24Regular,
  Folder24Regular,
} from "../ui/StudioIcons";
import {
  listRecordings,
  deleteRecording,
  cleanupOldRecordings,
  getRecordingsDir,
  type RecordingFile,
} from "../../services/tauriCommands";
import { uploadAndTrack } from "../../services/uploadAndTrack";
import { processLocally } from "../../services/localPipeline";
import { useSettingsStore } from "../../stores/settingsStore";
import { useToast } from "../ui/InfoBar";
import { useConfirmation } from "../ui/useConfirmation";

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDuration(seconds: number | null): string {
  if (!seconds) return "--:--";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function formatDate(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleDateString("nl-NL", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function SavedRecordings({
  onReprocess,
  initiallyExpanded = false,
}: {
  onReprocess?: (filePath: string) => void;
  initiallyExpanded?: boolean;
}) {
  const [recordings, setRecordings] = useState<RecordingFile[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [expanded, setExpanded] = useState(initiallyExpanded);
  const settings = useSettingsStore();
  const toast = useToast();
  const { confirm, confirmation } = useConfirmation();

  useEffect(() => {
    if (expanded) loadRecordings();
  }, [expanded]);

  async function loadRecordings() {
    setIsLoading(true);
    try {
      const dir = await getRecordingsDir();
      const files = await listRecordings(dir);
      setRecordings(files.sort((a, b) => b.created_at - a.created_at));
    } catch {
      setRecordings([]);
    } finally {
      setIsLoading(false);
    }
  }

  async function handleDelete(file: RecordingFile) {
    if (!await confirm(`“${file.filename}” wordt definitief verwijderd.`, "Opname verwijderen", "Verwijderen")) return;
    try {
      await deleteRecording(file.path);
      setRecordings((prev) => prev.filter((r) => r.path !== file.path));
      toast.show("Opname verwijderd", "success");
    } catch {
      toast.show("Verwijderen mislukt", "error");
    }
  }

  async function handleCleanup() {
    if (!await confirm("Alle opnames ouder dan 7 dagen worden definitief verwijderd.", "Oude opnames opruimen", "Opruimen")) return;
    try {
      const dir = await getRecordingsDir();
      const count = await cleanupOldRecordings(dir, 7);
      toast.show(`${count} oude opname${count !== 1 ? "s" : ""} verwijderd`, "success");
      await loadRecordings();
    } catch {
      toast.show("Opruimen mislukt", "error");
    }
  }

  async function handleReprocess(file: RecordingFile) {
    if (onReprocess) {
      onReprocess(file.path);
      return;
    }
    // Local mode: process fully on-device, mirroring the recording handler.
    if (settings.processing_mode === "local") {
      toast.show("Lokale verwerking gestart, voortgang zichtbaar in de verwerkingsbalk", "success");
      await processLocally(
        file.path,
        settings.default_profile_id,
        settings.default_recording_mode,
        [],
        file.duration_seconds ?? 0,
      );
      return;
    }
    toast.show("Upload gestart, voortgang zichtbaar in de verwerkingsbalk", "success");
    await uploadAndTrack(
      file.path,
      settings.default_profile_id,
      settings.default_recording_mode,
    );
  }

  if (!expanded) {
    return (
      <button
        onClick={() => setExpanded(true)}
        className="btn btn-secondary"
        style={{ fontSize: 12, gap: 6, display: "flex", alignItems: "center" }}
      >
        <Folder24Regular style={{ fontSize: 14 }} />
        Opgeslagen opnames
      </button>
    );
  }

  return (
    <div className="card card-static" style={{ width: "100%", padding: 0, overflow: "hidden" }}>
      {confirmation}
      {/* Header */}
      <div
        className="flex-row justify-between"
        style={{ padding: "10px 14px", borderBottom: "1px solid var(--border-secondary)", alignItems: "center" }}
      >
        <span className="text-body-strong" style={{ fontSize: 13 }}>
          Opgeslagen opnames ({recordings.length})
        </span>
        <div className="flex-row gap-6">
          <button
            className="icon-btn icon-btn-sm"
            onClick={handleCleanup}
            title="Opnames ouder dan 7 dagen verwijderen"
          >
            <BinRecycle24Regular style={{ fontSize: 14 }} />
          </button>
          <button
            className="icon-btn icon-btn-sm"
            onClick={loadRecordings}
            title="Vernieuwen"
          >
            <ArrowSync24Regular style={{ fontSize: 14 }} />
          </button>
          <button
            className="icon-btn icon-btn-sm"
            onClick={() => setExpanded(false)}
            title="Inklappen"
            style={{ fontSize: 12, fontWeight: 600 }}
          >
            &times;
          </button>
        </div>
      </div>

      {/* List */}
      <div style={{ maxHeight: 400, overflowY: "auto" }}>
        {isLoading ? (
          <div style={{ padding: 14, textAlign: "center" }}>
            <span className="text-caption text-secondary">Laden...</span>
          </div>
        ) : recordings.length === 0 ? (
          <div style={{ padding: 14, textAlign: "center" }}>
            <span className="text-caption text-secondary">Geen opgeslagen opnames</span>
          </div>
        ) : (
          recordings.map((file) => (
            <div
              key={file.path}
              className="flex-row gap-10"
              style={{
                padding: "8px 14px",
                borderBottom: "1px solid var(--border-secondary)",
                alignItems: "center",
                fontSize: 12,
              }}
            >
              <div className="flex-1" style={{ minWidth: 0 }}>
                <p className="truncate" style={{ fontWeight: 500, fontSize: 12, color: "var(--text-primary)" }}>
                  {file.filename}
                </p>
                <p className="text-caption text-secondary" style={{ marginTop: 1 }}>
                  {formatDate(file.created_at)} · {formatDuration(file.duration_seconds)} · {formatBytes(file.size_bytes)}
                </p>
              </div>
              <button
                className="icon-btn icon-btn-sm"
                onClick={() => handleReprocess(file)}
                title="Opnieuw verwerken"
              >
                <ArrowSync24Regular style={{ fontSize: 13 }} />
              </button>
              <button
                className="icon-btn icon-btn-sm"
                onClick={() => handleDelete(file)}
                title="Verwijderen"
                style={{ color: "var(--text-error)" }}
              >
                <Delete24Regular style={{ fontSize: 13 }} />
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
