import { useNavigate } from "react-router-dom";
import {
  ArrowUpload24Regular,
  Checkmark24Regular,
  Dismiss24Regular,
  DismissCircle24Regular,
  MicRecord24Regular,
} from "@fluentui/react-icons";
import { useRecordingStore } from "../stores/recordingStore";
import type { TranscriptTask } from "../types";

const STATUS_CONFIG: Record<string, { label: string; icon: React.ReactNode; color: string }> = {
  uploading: {
    label: "Uploaden",
    icon: <ArrowUpload24Regular style={{ fontSize: 14 }} />,
    color: "var(--brand-secondary)",
  },
  converting: {
    label: "Converteren",
    icon: <ArrowUpload24Regular style={{ fontSize: 14 }} />,
    color: "var(--brand-secondary)",
  },
  transcribing: {
    label: "Transcriberen",
    icon: <MicRecord24Regular style={{ fontSize: 14 }} />,
    color: "var(--brand-primary)",
  },
  generating: {
    label: "Notulen genereren",
    icon: <MicRecord24Regular style={{ fontSize: 14 }} />,
    color: "var(--brand-primary)",
  },
  completed: {
    label: "Voltooid",
    icon: <Checkmark24Regular style={{ fontSize: 14 }} />,
    color: "var(--status-success)",
  },
  failed: {
    label: "Mislukt",
    icon: <Dismiss24Regular style={{ fontSize: 14 }} />,
    color: "var(--status-error)",
  },
};

function ProcessingBarItem({ task }: { task: TranscriptTask }) {
  const navigate = useNavigate();
  const removeBackgroundTask = useRecordingStore((s) => s.removeBackgroundTask);
  const cancelBackgroundTask = useRecordingStore((s) => s.cancelBackgroundTask);

  const status = task.status ?? "uploading";
  const progress = task.progress ?? 0;
  const config = STATUS_CONFIG[status] ?? STATUS_CONFIG.uploading;
  const isFailed = status === "failed";
  const isCompleted = status === "completed";
  const isUploading = status === "uploading";

  return (
    <div className="processing-bar-item">
      {/* Animated progress track behind content */}
      <div
        className="processing-bar-track"
        style={{
          width: `${progress}%`,
          background: isFailed
            ? "var(--status-error)"
            : config.color,
        }}
      />

      {/* Content */}
      <div className="processing-bar-content">
        {/* Pulsing dot or status icon */}
        <span className="processing-bar-icon" style={{ color: config.color }}>
          {(!isFailed && !isCompleted) ? (
            <span className="processing-bar-pulse" style={{ background: config.color }} />
          ) : (
            config.icon
          )}
        </span>

        <span className="processing-bar-label">{config.label}</span>

        {isFailed && task.error_message && (
          <span className="processing-bar-error">{task.error_message}</span>
        )}

        <span className="processing-bar-percent">{progress}%</span>

        {/* Action */}
        {isCompleted ? (
          <button
            className="processing-bar-action"
            onClick={() => {
              removeBackgroundTask(task.task_id);
              navigate("/transcripts");
            }}
          >
            Bekijk
          </button>
        ) : isFailed ? (
          <button
            className="processing-bar-dismiss"
            onClick={() => removeBackgroundTask(task.task_id)}
            aria-label="Sluiten"
          >
            <Dismiss24Regular style={{ fontSize: 12 }} />
          </button>
        ) : isUploading ? (
          <button
            className="processing-bar-dismiss"
            onClick={() => cancelBackgroundTask(task.task_id)}
            aria-label="Annuleren"
            title="Upload annuleren"
          >
            <DismissCircle24Regular style={{ fontSize: 14 }} />
          </button>
        ) : null}
      </div>
    </div>
  );
}

export function ProcessingBar() {
  const backgroundTasks = useRecordingStore((s) => s.backgroundTasks);

  if (backgroundTasks.length === 0) return null;

  return (
    <div className="processing-bar">
      {backgroundTasks.map((task) => (
        <ProcessingBarItem key={task.task_id} task={task} />
      ))}
    </div>
  );
}
