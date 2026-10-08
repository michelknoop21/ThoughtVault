import { useEffect, useState } from "react";
import {
  ArrowSync24Regular,
  Delete24Regular,
  DismissCircle24Regular,
  Clock24Regular,
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  ArrowClockwise24Regular,
  Person24Regular,
} from "@fluentui/react-icons";
import { useTasksStore } from "../stores/tasksStore";
import { useRecordingStore } from "../stores/recordingStore";
import { useSettingsStore } from "../stores/settingsStore";
import { processLocally } from "../services/localPipeline";
import { TaskStatusLabels } from "../types";
import type { TranscriptTask, TaskStatus } from "../types";

// --- Status color mapping ---

type StatusColorConfig = {
  bg: string;
  text: string;
  border: string;
  progressBar: string;
  pulse: boolean;
};

const STATUS_COLORS: Record<string, StatusColorConfig> = {
  pending: { bg: "bg-amber-500/10", text: "text-amber-600", border: "border-amber-500/30", progressBar: "bg-amber-500", pulse: false },
  queued: { bg: "bg-amber-500/10", text: "text-amber-600", border: "border-amber-500/30", progressBar: "bg-amber-500", pulse: false },
  uploading: { bg: "bg-blue-500/10", text: "text-blue-600", border: "border-blue-500/30", progressBar: "bg-blue-500", pulse: true },
  converting: { bg: "bg-blue-500/10", text: "text-blue-600", border: "border-blue-500/30", progressBar: "bg-blue-500", pulse: true },
  transcribing: { bg: "bg-blue-500/10", text: "text-blue-600", border: "border-blue-500/30", progressBar: "bg-blue-500", pulse: true },
  generating: { bg: "bg-blue-500/10", text: "text-blue-600", border: "border-blue-500/30", progressBar: "bg-blue-500", pulse: true },
  paused: { bg: "bg-indigo-500/10", text: "text-indigo-600", border: "border-indigo-500/30", progressBar: "bg-indigo-500", pulse: false },
  completed: { bg: "bg-green-500/10", text: "text-green-600", border: "border-green-500/30", progressBar: "bg-green-500", pulse: false },
  failed: { bg: "bg-red-500/10", text: "text-red-600", border: "border-red-500/30", progressBar: "bg-red-500", pulse: false },
  cancelled: { bg: "bg-gray-500/10", text: "text-gray-500", border: "border-gray-500/30", progressBar: "bg-gray-400", pulse: false },
};

function getStatusColors(status: string): StatusColorConfig {
  return STATUS_COLORS[status] ?? STATUS_COLORS.pending;
}

// --- Relative time ---

function timeAgo(dateString: string): string {
  const seconds = Math.floor((Date.now() - new Date(dateString).getTime()) / 1000);
  if (seconds < 60) return "Zojuist";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} ${minutes === 1 ? "minuut" : "minuten"} geleden`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} uur geleden`;
  const days = Math.floor(hours / 24);
  return `${days} ${days === 1 ? "dag" : "dagen"} geleden`;
}

// --- Active status check ---

function isActiveStatus(status: TaskStatus): boolean {
  return ["pending", "queued", "uploading", "converting", "transcribing", "generating", "paused"].includes(status);
}

// --- Confirmation dialog ---

function ConfirmDialog({
  title,
  message,
  confirmLabel,
  danger,
  onConfirm,
  onCancel,
}: {
  title: string;
  message: string;
  confirmLabel: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 1000,
        display: "grid",
        placeItems: "center",
        background: "rgba(0,0,0,0.4)",
      }}
      onClick={onCancel}
    >
      <div
        className="card"
        style={{
          maxWidth: 400,
          padding: 24,
          display: "flex",
          flexDirection: "column",
          gap: 16,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <p style={{ font: "var(--type-subtitle)", color: "var(--text-primary)", margin: 0 }}>{title}</p>
        <p style={{ font: "var(--type-body)", color: "var(--text-secondary)", margin: 0 }}>{message}</p>
        <div className="flex-row gap-8" style={{ justifyContent: "flex-end" }}>
          <button className="btn" onClick={onCancel}>
            Terug
          </button>
          <button
            className={danger ? "btn btn-danger" : "btn btn-accent"}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

// --- Task card ---

function TaskCard({
  task,
  onCancel,
  onDelete,
  onRetry,
  isLocal,
}: {
  task: TranscriptTask;
  onCancel: (taskId: string) => void;
  onDelete: (taskId: string) => void;
  onRetry: (task: TranscriptTask) => void;
  isLocal: boolean;
}) {
  const colors = getStatusColors(task.status);
  const active = isActiveStatus(task.status);
  const label = TaskStatusLabels[task.status] ?? task.status;
  const title = task.extracted_title || task.filename || "Naamloze taak";

  return (
    <div className="card" style={{ padding: 16, display: "flex", flexDirection: "column", gap: 12 }}>
      {/* Top row: title + status badge */}
      <div className="flex-row" style={{ justifyContent: "space-between", alignItems: "flex-start", gap: 12 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <p className="truncate" style={{ font: "var(--type-body)", fontWeight: 600, color: "var(--text-primary)", margin: 0 }}>
            {title}
          </p>
          {task.message && (
            <p className="truncate" style={{ font: "var(--type-caption)", color: "var(--text-secondary)", margin: "4px 0 0" }}>
              {task.message}
            </p>
          )}
        </div>
        <span
          className={`${colors.bg} ${colors.text} ${colors.border}`}
          style={{
            padding: "2px 10px",
            borderRadius: 999,
            fontSize: 11,
            fontWeight: 600,
            border: "1px solid",
            whiteSpace: "nowrap",
            flexShrink: 0,
            display: "inline-flex",
            alignItems: "center",
            gap: 6,
          }}
        >
          {colors.pulse && (
            <span
              style={{
                width: 6,
                height: 6,
                borderRadius: "50%",
                background: "currentColor",
                animation: "pulse 1.5s ease-in-out infinite",
              }}
            />
          )}
          {label}
        </span>
      </div>

      {/* Progress bar (for active tasks) */}
      {active && (
        <div style={{ height: 4, borderRadius: 2, background: "var(--surface-tertiary)", overflow: "hidden" }}>
          <div
            className={colors.progressBar}
            style={{
              height: "100%",
              borderRadius: 2,
              width: `${task.progress ?? 0}%`,
              transition: "width 0.3s ease",
            }}
          />
        </div>
      )}

      {/* Error message */}
      {task.status === "failed" && task.error_message && (
        <div className="error-banner-inline" style={{ margin: 0 }}>
          <ErrorCircle24Regular style={{ fontSize: 14, flexShrink: 0 }} />
          <span style={{ fontSize: 12 }}>{task.error_message}</span>
        </div>
      )}

      {/* Bottom row: meta + actions */}
      <div className="flex-row" style={{ justifyContent: "space-between", alignItems: "center" }}>
        <div className="flex-row gap-8" style={{ alignItems: "center" }}>
          <span className="flex-row gap-4" style={{ font: "var(--type-caption)", color: "var(--text-secondary)" }}>
            <Clock24Regular style={{ fontSize: 12 }} />
            {timeAgo(task.created_at)}
          </span>
          {task.username && (
            <span className="flex-row gap-4" style={{ font: "var(--type-caption)", color: "var(--fill-accent-default)" }}>
              <Person24Regular style={{ fontSize: 12 }} />
              {task.username}
            </span>
          )}
          {task.queue_position != null && task.queue_position > 0 && (
            <span style={{ font: "var(--type-caption)", color: "var(--text-secondary)" }}>
              Positie {task.queue_position} in wachtrij
            </span>
          )}
          {active && task.progress != null && (
            <span style={{ font: "var(--type-caption)", color: "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>
              {task.progress}%
            </span>
          )}
        </div>
        <div className="flex-row gap-4">
          {task.status === "failed" && task.local_audio_path && (
            <button className="btn btn-sm" onClick={() => onRetry(task)}>
              <ArrowSync24Regular style={{ fontSize: 14 }} /> Opnieuw verwerken
            </button>
          )}
          {active && !isLocal && (
            <button
              className="btn btn-sm"
              onClick={() => onCancel(task.task_id)}
              title="Annuleren"
              style={{ display: "inline-flex", alignItems: "center", gap: 4 }}
            >
              <DismissCircle24Regular style={{ fontSize: 14 }} />
              Annuleren
            </button>
          )}
          {(!active || !isLocal) && <button
            className="btn btn-sm"
            onClick={() => onDelete(task.task_id)}
            title="Verwijderen"
            style={{ display: "inline-flex", alignItems: "center", gap: 4, color: "var(--status-error)" }}
          >
            <Delete24Regular style={{ fontSize: 14 }} />
            Verwijderen
          </button>}
        </div>
      </div>
    </div>
  );
}

// --- Page ---

export function TasksPage() {
  const { activeTasks, isLoading, error, loadActiveTasks, cancelTask, deleteTask, startAutoRefresh, stopAutoRefresh } = useTasksStore();
  const isLocal = useSettingsStore((s) => s.processing_mode === "local");
  const localTasks = useRecordingStore((s) => s.backgroundTasks);
  const removeLocalTask = useRecordingStore((s) => s.removeBackgroundTask);
  const visibleTasks = [...localTasks, ...(isLocal ? [] : activeTasks.filter(
    (task) => !localTasks.some((local) => local.task_id === task.task_id),
  ))];

  const [confirmAction, setConfirmAction] = useState<{
    type: "cancel" | "delete";
    taskId: string;
    title: string;
  } | null>(null);

  useEffect(() => {
    startAutoRefresh();
    return () => stopAutoRefresh();
  }, [startAutoRefresh, stopAutoRefresh]);

  function handleCancel(taskId: string) {
    const task = activeTasks.find((t) => t.task_id === taskId);
    setConfirmAction({
      type: "cancel",
      taskId,
      title: task?.extracted_title || task?.filename || "deze taak",
    });
  }

  function handleDelete(taskId: string) {
    if (localTasks.some((task) => task.task_id === taskId)) {
      removeLocalTask(taskId);
      return;
    }
    const task = visibleTasks.find((t) => t.task_id === taskId);
    setConfirmAction({
      type: "delete",
      taskId,
      title: task?.extracted_title || task?.filename || "deze taak",
    });
  }

  function handleRetry(task: TranscriptTask) {
    if (!task.local_audio_path) return;
    removeLocalTask(task.task_id);
    void processLocally(task.local_audio_path, task.profile_id || "standaard", task.mode, [], task.duration_seconds ?? 0, task.task_id);
  }

  async function executeConfirmAction() {
    if (!confirmAction) return;
    if (confirmAction.type === "cancel") {
      await cancelTask(confirmAction.taskId);
    } else {
      await deleteTask(confirmAction.taskId);
    }
    setConfirmAction(null);
  }

  return (
    <div className="page-scroll desktop-page desktop-tasks">
      <div className="page-content">
        {/* Header */}
        <section>
          <div className="flex-row justify-between" style={{ alignItems: "center" }}>
            <div>
              <h2 className="text-subtitle" style={{ margin: 0 }}>Taken</h2>
              <p className="text-caption" style={{ marginTop: 4 }}>
                Overzicht van actieve en recente verwerkingstaken
              </p>
            </div>
            <button
              className="icon-btn"
              onClick={() => loadActiveTasks()}
              title="Vernieuwen"
              disabled={isLoading}
            >
              <ArrowSync24Regular
                style={{
                  fontSize: 18,
                  animation: isLoading ? "spin 1s linear infinite" : undefined,
                }}
              />
            </button>
          </div>
        </section>

        {/* Error banner */}
        {error && (
          <div className="error-banner-inline">
            <ErrorCircle24Regular style={{ fontSize: 14, flexShrink: 0 }} />
            <span style={{ flex: 1 }}>{error}</span>
            <button className="btn btn-sm" onClick={() => loadActiveTasks()}>
              Opnieuw
            </button>
          </div>
        )}

        {/* Content */}
        {!isLocal && isLoading && visibleTasks.length === 0 ? (
          <div className="empty-state">
            <ArrowClockwise24Regular
              style={{
                fontSize: 32,
                color: "var(--text-secondary)",
                animation: "spin 1s linear infinite",
              }}
            />
            <p className="empty-state-text" style={{ marginTop: 12 }}>Taken laden...</p>
          </div>
        ) : visibleTasks.length === 0 ? (
          <div className="empty-state">
            <CheckmarkCircle24Regular
              style={{ fontSize: 40, color: "var(--text-secondary)", opacity: 0.5 }}
            />
            <p className="empty-state-text" style={{ marginTop: 12 }}>
              Geen actieve taken
            </p>
            <p className="text-caption" style={{ marginTop: 4 }}>
              Start een opname om verwerkingstaken te zien
            </p>
          </div>
        ) : (
          <section>
            <div className="flex-col gap-10">
              {visibleTasks.map((task) => (
                <TaskCard
                  key={task.task_id}
                  task={task}
                  onCancel={handleCancel}
                  onDelete={handleDelete}
                  onRetry={handleRetry}
                  isLocal={localTasks.some((local) => local.task_id === task.task_id)}
                />
              ))}
            </div>
          </section>
        )}
      </div>

      {/* Confirmation dialog */}
      {confirmAction && (
        <ConfirmDialog
          title={confirmAction.type === "cancel" ? "Taak annuleren" : "Taak verwijderen"}
          message={
            confirmAction.type === "cancel"
              ? `Weet je zeker dat je "${confirmAction.title}" wilt annuleren?`
              : `Weet je zeker dat je "${confirmAction.title}" wilt verwijderen? Dit kan niet ongedaan worden.`
          }
          confirmLabel={confirmAction.type === "cancel" ? "Annuleren" : "Verwijderen"}
          danger={confirmAction.type === "delete"}
          onConfirm={executeConfirmAction}
          onCancel={() => setConfirmAction(null)}
        />
      )}
    </div>
  );
}
