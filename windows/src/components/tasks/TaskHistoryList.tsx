import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useTaskHistory, durationLabel, outcomeLabel, type TaskHistoryEntry } from "../../services/taskHistory";
import { canReprocess, deleteTask, deleteTaskRecording, hasNotule, hasRecording, isRunning } from "../../services/taskActions";
import { useRecordingStore } from "../../stores/recordingStore";
import { useLocalTranscriptsStore } from "../../stores/localTranscriptsStore";
import { useTranscriptsStore } from "../../stores/transcriptsStore";
import { useConfirmation } from "../ui/useConfirmation";
import { DeleteTaskDialog, ReprocessDialog, TaskDetailDialog, type TaskAction } from "./TaskDialogs";

const OUTCOME_CLASS: Record<string, string> = {
  Voltooid: "bg-green-500/10 text-green-600 border-green-500/30",
  Mislukt: "bg-red-500/10 text-red-600 border-red-500/30",
  Geannuleerd: "bg-gray-500/10 text-gray-500 border-gray-500/30",
  Onderbroken: "bg-amber-500/10 text-amber-600 border-amber-500/30",
  Bezig: "bg-blue-500/10 text-blue-600 border-blue-500/30",
};

/** History entries that are not shown as an active task above. */
export function historyEntries(entries: TaskHistoryEntry[], shownIds: Set<string>): TaskHistoryEntry[] {
  return entries.filter(entry => !shownIds.has(entry.id));
}

/** "Geschiedenis" on the Taken page: every finished task with details and actions. */
export function TaskHistoryList({ shownIds }: { shownIds: Set<string> }) {
  const entries = historyEntries(useTaskHistory(s => s.entries), shownIds);
  useRecordingStore(s => s.backgroundTasks);  // re-render when a task starts or stops running
  useLocalTranscriptsStore(s => s.items);     // and when a notule appears or disappears
  const navigate = useNavigate();
  const { confirm, confirmation } = useConfirmation();
  const [open, setOpen] = useState<{ id: string; action: TaskAction } | null>(null);
  const [error, setError] = useState("");
  const current = open && useTaskHistory.getState().entries.find(e => e.id === open.id);

  if (entries.length === 0) return null;

  function openNotule(entry: TaskHistoryEntry) {
    useTranscriptsStore.getState().setSelectedId(entry.transcript_id);
    navigate("/transcripts");
  }

  async function act(entry: TaskHistoryEntry, action: TaskAction) {
    setError("");
    if (action !== "delete-recording") { setOpen({ id: entry.id, action }); return; }
    setOpen(null);
    if (!await confirm(`Het audiobestand van "${entry.title}" wordt definitief verwijderd. De notule en de transcriptie blijven bewaard.`, "Opname verwijderen", "Opname verwijderen")) return;
    try { await deleteTaskRecording(entry); } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  }

  return <section className="task-history" aria-labelledby="task-history-title" style={{ marginTop: 24 }}>
    <h3 id="task-history-title" className="page-title-sm" style={{ font: "var(--type-body)", fontWeight: 600, margin: "0 0 10px" }}>Geschiedenis</h3>
    {error && <div className="error-banner-inline" role="alert">{error}</div>}
    <div className="flex-col gap-10">
      {entries.map(entry => {
        const running = isRunning(entry);
        const outcome = outcomeLabel(entry, running);
        const meta = [new Date(entry.created_at).toLocaleString("nl-NL", { dateStyle: "medium", timeStyle: "short" }), entry.profile_name,
          entry.recording_seconds ? `opname ${durationLabel(entry.recording_seconds)}` : undefined,
          entry.recording_deleted ? "opname verwijderd" : undefined].filter(Boolean).join(" · ");
        return <article key={entry.id} className="card" style={{ padding: 16, display: "flex", flexDirection: "column", gap: 10 }}>
          <div className="flex-row" style={{ justifyContent: "space-between", alignItems: "flex-start", gap: 12 }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <p className="truncate" style={{ font: "var(--type-body)", fontWeight: 600, color: "var(--text-primary)", margin: 0 }}>{entry.title}</p>
              <p style={{ font: "var(--type-caption)", color: "var(--text-secondary)", margin: "4px 0 0" }}>{meta}</p>
            </div>
            <span className={OUTCOME_CLASS[outcome]} style={{ padding: "2px 10px", borderRadius: 999, fontSize: 11, fontWeight: 600, border: "1px solid", whiteSpace: "nowrap" }}>{outcome}</span>
          </div>
          {entry.error_message && entry.status !== "completed" &&
            <p style={{ font: "var(--type-caption)", color: "var(--status-error)", margin: 0 }}>{entry.error_message}</p>}
          <div className="flex-row gap-4" style={{ flexWrap: "wrap" }}>
            <button className="btn btn-sm" onClick={() => void act(entry, "details")}>Details</button>
            <button className="btn btn-sm" disabled={!canReprocess(entry)} onClick={() => void act(entry, "reprocess")}>Opnieuw verwerken</button>
            {hasNotule(entry) && <button className="btn btn-sm" onClick={() => openNotule(entry)}>Naar de notule</button>}
            <button className="btn btn-sm" disabled={!hasRecording(entry) || running} onClick={() => void act(entry, "delete-recording")}>Opname verwijderen</button>
            <button className="btn btn-sm" style={{ color: "var(--status-error)" }} disabled={running} onClick={() => void act(entry, "delete")}>Verwijderen</button>
          </div>
        </article>;
      })}
    </div>
    {current && open?.action === "details" && <TaskDetailDialog entry={current} onClose={() => setOpen(null)}
      onOpenNotule={() => { setOpen(null); openNotule(current); }} onAction={action => void act(current, action)} />}
    {current && open?.action === "reprocess" && <ReprocessDialog entry={current} onClose={() => setOpen(null)} />}
    {current && open?.action === "delete" && <DeleteTaskDialog entry={current} onClose={() => setOpen(null)}
      onDelete={includeNotule => { setOpen(null); void deleteTask(current, includeNotule).catch(e => setError(e instanceof Error ? e.message : String(e))); }} />}
    {confirmation}
  </section>;
}
