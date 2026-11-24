import { DesktopDialog } from "../ui/DesktopDialog";

/** Confirmation sheet of the Taken page. */
export function ConfirmDialog({
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
    <DesktopDialog label={title} onClose={onCancel}>
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
    </DesktopDialog>
  );
}
