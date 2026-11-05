import { useEffect, useState } from "react";
import {
  CheckmarkCircle24Regular,
  ErrorCircle24Regular,
  Warning24Regular,
  Info24Regular,
  Dismiss16Regular,
} from "./StudioIcons";
import { create } from "zustand";

type Severity = "success" | "error" | "warning" | "info";

interface Toast {
  id: string;
  message: string;
  severity: Severity;
}

interface ToastStore {
  toasts: Toast[];
  show: (message: string, severity?: Severity) => void;
  dismiss: (id: string) => void;
}

export const useToast = create<ToastStore>()((set) => ({
  toasts: [],
  show: (message, severity = "info") => {
    const id = Date.now().toString(36);
    set((state) => {
      const updated = [...state.toasts, { id, message, severity }];
      // Keep max 2 visible — dismiss oldest when exceeding
      if (updated.length > 2) {
        return { toasts: updated.slice(-2) };
      }
      return { toasts: updated };
    });
    // Auto-dismiss after 4s
    setTimeout(() => {
      set((state) => ({ toasts: state.toasts.filter((t) => t.id !== id) }));
    }, 4000);
  },
  dismiss: (id) => set((state) => ({ toasts: state.toasts.filter((t) => t.id !== id) })),
}));

const SEVERITY_CONFIG: Record<Severity, { icon: React.ReactNode; bg: string; border: string; color: string }> = {
  success: {
    icon: <CheckmarkCircle24Regular />,
    bg: "rgba(15, 123, 15, 0.06)",
    border: "rgba(15, 123, 15, 0.20)",
    color: "var(--fill-system-success)",
  },
  error: {
    icon: <ErrorCircle24Regular />,
    bg: "rgba(196, 43, 28, 0.06)",
    border: "rgba(196, 43, 28, 0.20)",
    color: "var(--fill-system-critical)",
  },
  warning: {
    icon: <Warning24Regular />,
    bg: "rgba(157, 93, 0, 0.06)",
    border: "rgba(157, 93, 0, 0.20)",
    color: "var(--fill-system-caution)",
  },
  info: {
    icon: <Info24Regular />,
    bg: "rgba(0, 95, 184, 0.06)",
    border: "rgba(0, 95, 184, 0.20)",
    color: "var(--fill-system-attention)",
  },
};

export function InfoBarHost() {
  const { toasts, dismiss } = useToast();

  if (toasts.length === 0) return null;

  return (
    <div style={{
      position: "fixed",
      bottom: 32,
      right: 32,
      zIndex: 9999,
      display: "flex",
      flexDirection: "column",
      gap: 8,
      maxWidth: 380,
      maxHeight: "calc(100vh - 80px)",
      overflowY: "auto",
    }}>
      {toasts.map((toast) => (
        <InfoBarItem key={toast.id} toast={toast} onDismiss={() => dismiss(toast.id)} />
      ))}
    </div>
  );
}

function InfoBarItem({ toast, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  const [visible, setVisible] = useState(false);
  const config = SEVERITY_CONFIG[toast.severity];

  useEffect(() => {
    requestAnimationFrame(() => setVisible(true));
  }, []);

  return (
    <div style={{
      display: "flex",
      alignItems: "flex-start",
      gap: 10,
      padding: "10px 12px",
      background: config.bg,
      border: `1px solid ${config.border}`,
      borderRadius: 8,
      backdropFilter: "blur(20px)",
      boxShadow: "0 4px 16px rgba(0,0,0,0.12)",
      opacity: visible ? 1 : 0,
      transform: visible ? "translateY(0)" : "translateY(8px)",
      transition: "opacity 150ms ease, transform 150ms ease",
    }}>
      <span style={{ color: config.color, flexShrink: 0, marginTop: 1 }}>
        {config.icon}
      </span>
      <span style={{
        flex: 1,
        fontSize: 13,
        lineHeight: 1.4,
        color: "var(--text-primary)",
      }}>
        {toast.message}
      </span>
      <button
        onClick={onDismiss}
        aria-label="Melding sluiten"
        style={{
          background: "none",
          border: "none",
          color: "var(--text-tertiary)",
          cursor: "default",
          padding: 0,
          width: 28,
          height: 28,
          minWidth: 28,
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Dismiss16Regular />
      </button>
    </div>
  );
}
