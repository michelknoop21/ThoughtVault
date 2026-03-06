import { useCallback, useEffect, useRef, useState } from "react";
import {
  ChatBubblesQuestion24Regular,
  Dismiss16Regular,
  Send20Regular,
  ArrowSync16Regular,
} from "@fluentui/react-icons";
import { api } from "../services/api";
import { useToast } from "./ui/InfoBar";
import type { FeedbackSubmission, UserFeedback } from "../types";

type Tab = "new" | "history";
type Category = FeedbackSubmission["category"];

const CATEGORY_OPTIONS: { value: Category; label: string }[] = [
  { value: "bug", label: "Bug" },
  { value: "feature", label: "Feature request" },
  { value: "general", label: "Vraag" },
];

const STATUS_LABELS: Record<string, { label: string; className: string }> = {
  new: { label: "Nieuw", className: "status-badge-neutral" },
  open: { label: "Open", className: "status-badge-neutral" },
  in_progress: { label: "In behandeling", className: "status-badge-neutral" },
  resolved: { label: "Opgelost", className: "status-badge-success" },
  closed: { label: "Gesloten", className: "status-badge-success" },
};

function formatDate(iso: string): string {
  try {
    return new Intl.DateTimeFormat("nl-NL", {
      day: "numeric",
      month: "short",
      year: "numeric",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export default function FeedbackWidget() {
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<Tab>("new");
  const [unreadCount, setUnreadCount] = useState(0);

  // Form state
  const [title, setTitle] = useState("");
  const [category, setCategory] = useState<Category>("bug");
  const [description, setDescription] = useState("");
  const [submitting, setSubmitting] = useState(false);

  // History state
  const [feedbackList, setFeedbackList] = useState<UserFeedback[]>([]);
  const [loadingHistory, setLoadingHistory] = useState(false);

  const panelRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const toast = useToast();

  // Load unread count on mount
  useEffect(() => {
    api.getUnreadFeedbackCount().then(setUnreadCount);
  }, []);

  // Load history when tab switches to history
  useEffect(() => {
    if (tab === "history" && open) {
      loadHistory();
    }
  }, [tab, open]);

  const loadHistory = useCallback(async () => {
    setLoadingHistory(true);
    try {
      const items = await api.getMyFeedback();
      setFeedbackList(items);

      // Mark unread items as read
      const unread = items.filter(
        (item) => item.response && item.status !== "new"
      );
      for (const item of unread) {
        await api.markFeedbackRead(item.id);
      }
      setUnreadCount(0);
    } catch {
      // Silently fail
    } finally {
      setLoadingHistory(false);
    }
  }, []);

  // Close on outside click
  useEffect(() => {
    if (!open) return;

    function handleClick(e: MouseEvent) {
      if (
        panelRef.current &&
        !panelRef.current.contains(e.target as Node) &&
        buttonRef.current &&
        !buttonRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    }

    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [open]);

  const handleSubmit = async () => {
    if (!title.trim() || !description.trim()) {
      toast.show("Vul titel en beschrijving in.", "warning");
      return;
    }

    setSubmitting(true);
    try {
      await api.submitFeedback({ category, title: title.trim(), description: description.trim() });
      toast.show("Feedback verstuurd!", "success");
      setTitle("");
      setDescription("");
      setCategory("bug");
      // Refresh unread count
      const count = await api.getUnreadFeedbackCount();
      setUnreadCount(count);
    } catch (err) {
      toast.show(
        err instanceof Error ? err.message : "Fout bij versturen.",
        "error"
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      {/* Floating button */}
      <button
        ref={buttonRef}
        onClick={() => setOpen((prev) => !prev)}
        style={{
          position: "fixed",
          right: 20,
          bottom: 20,
          zIndex: 1000,
          width: 48,
          height: 48,
          borderRadius: "50%",
          background: "var(--btn-primary-gradient)",
          border: "none",
          color: "#fff",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          cursor: "default",
          boxShadow: "var(--btn-primary-shadow)",
          transition: "transform 150ms var(--ease-smooth), box-shadow 150ms var(--ease-smooth)",
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.transform = "scale(1.08)";
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.transform = "scale(1)";
        }}
        title="Feedback"
      >
        <ChatBubblesQuestion24Regular />
        {unreadCount > 0 && (
          <span
            style={{
              position: "absolute",
              top: -2,
              right: -2,
              minWidth: 18,
              height: 18,
              borderRadius: 9,
              background: "var(--status-error)",
              color: "#fff",
              fontSize: "var(--font-micro)",
              fontWeight: 700,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              padding: "0 5px",
              lineHeight: 1,
            }}
          >
            {unreadCount}
          </span>
        )}
      </button>

      {/* Panel */}
      {open && (
        <div
          ref={panelRef}
          style={{
            position: "fixed",
            right: 20,
            bottom: 78,
            zIndex: 1001,
            width: 360,
            maxHeight: 500,
            background: "var(--card-bg)",
            backdropFilter: `blur(var(--card-blur))`,
            border: "1px solid var(--card-border)",
            borderRadius: "var(--radius-sm)",
            boxShadow: "0 8px 32px rgba(0,0,0,0.16)",
            display: "flex",
            flexDirection: "column",
            overflow: "hidden",
            animation: "feedbackSlideIn 150ms var(--ease-smooth)",
          }}
        >
          {/* Header */}
          <div
            className="flex-row"
            style={{
              padding: "12px 16px",
              borderBottom: "1px solid var(--border-secondary)",
              alignItems: "center",
              justifyContent: "space-between",
              gap: 8,
              flexShrink: 0,
            }}
          >
            <span
              style={{
                fontSize: "var(--font-headline)",
                fontWeight: 600,
                color: "var(--text-primary)",
              }}
            >
              Feedback
            </span>
            <button
              onClick={() => setOpen(false)}
              style={{
                background: "none",
                border: "none",
                color: "var(--text-tertiary)",
                cursor: "default",
                padding: 4,
                display: "flex",
                alignItems: "center",
              }}
            >
              <Dismiss16Regular />
            </button>
          </div>

          {/* Tabs */}
          <div
            className="flex-row"
            style={{
              padding: "0 16px",
              borderBottom: "1px solid var(--border-secondary)",
              gap: 0,
              flexShrink: 0,
            }}
          >
            {(["new", "history"] as Tab[]).map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                style={{
                  background: "none",
                  border: "none",
                  borderBottom:
                    tab === t
                      ? "2px solid var(--brand-primary)"
                      : "2px solid transparent",
                  color:
                    tab === t
                      ? "var(--brand-primary)"
                      : "var(--text-secondary)",
                  fontSize: "var(--font-body)",
                  fontWeight: tab === t ? 600 : 400,
                  padding: "10px 16px",
                  cursor: "default",
                  transition:
                    "color 150ms ease, border-color 150ms ease",
                }}
              >
                {t === "new" ? "Nieuw" : "Mijn feedback"}
              </button>
            ))}
          </div>

          {/* Content */}
          <div
            style={{
              flex: 1,
              overflowY: "auto",
              padding: 16,
            }}
          >
            {tab === "new" ? (
              <div className="flex-col" style={{ gap: 12 }}>
                {/* Title */}
                <div className="form-field">
                  <label className="form-label">Titel</label>
                  <input
                    className="input"
                    type="text"
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    placeholder="Korte omschrijving"
                    maxLength={100}
                  />
                </div>

                {/* Category */}
                <div className="form-field">
                  <label className="form-label">Categorie</label>
                  <select
                    className="select"
                    value={category}
                    onChange={(e) => setCategory(e.target.value as Category)}
                  >
                    {CATEGORY_OPTIONS.map((opt) => (
                      <option key={opt.value} value={opt.value}>
                        {opt.label}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Description */}
                <div className="form-field">
                  <label className="form-label">Beschrijving</label>
                  <textarea
                    className="input"
                    rows={4}
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    placeholder="Beschrijf je feedback..."
                    style={{ resize: "vertical" }}
                  />
                </div>

                {/* Submit */}
                <button
                  className="btn btn-accent"
                  onClick={handleSubmit}
                  disabled={submitting || !title.trim() || !description.trim()}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: 6,
                  }}
                >
                  <Send20Regular />
                  {submitting ? "Versturen..." : "Versturen"}
                </button>
              </div>
            ) : (
              <div className="flex-col" style={{ gap: 8 }}>
                {loadingHistory ? (
                  <div
                    style={{
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      gap: 8,
                      padding: 24,
                      color: "var(--text-tertiary)",
                      fontSize: "var(--font-body)",
                    }}
                  >
                    <ArrowSync16Regular
                      style={{ animation: "spin 1s linear infinite" }}
                    />
                    Laden...
                  </div>
                ) : feedbackList.length === 0 ? (
                  <div
                    className="text-caption"
                    style={{
                      textAlign: "center",
                      padding: 24,
                      color: "var(--text-tertiary)",
                    }}
                  >
                    Nog geen feedback verstuurd.
                  </div>
                ) : (
                  feedbackList.map((item) => {
                    const statusInfo = STATUS_LABELS[item.status] ?? {
                      label: item.status,
                      className: "status-badge-neutral",
                    };
                    return (
                      <div
                        key={item.id}
                        style={{
                          padding: 12,
                          background: "var(--surface-secondary)",
                          borderRadius: "var(--radius-xs)",
                          border: "1px solid var(--border-secondary)",
                        }}
                      >
                        <div
                          className="flex-row"
                          style={{
                            justifyContent: "space-between",
                            alignItems: "flex-start",
                            gap: 8,
                            marginBottom: 4,
                          }}
                        >
                          <span
                            style={{
                              fontSize: "var(--font-body)",
                              fontWeight: 600,
                              color: "var(--text-primary)",
                              flex: 1,
                            }}
                          >
                            {item.title}
                          </span>
                          <span className={statusInfo.className}>
                            {statusInfo.label}
                          </span>
                        </div>
                        <span
                          className="text-caption"
                          style={{ color: "var(--text-tertiary)" }}
                        >
                          {formatDate(item.created_at)}
                        </span>
                        {item.response && (
                          <div
                            style={{
                              marginTop: 8,
                              padding: "8px 10px",
                              background: "var(--accent-bg-secondary)",
                              borderRadius: "var(--radius-xs)",
                              fontSize: "var(--font-caption)",
                              color: "var(--text-secondary)",
                              lineHeight: 1.4,
                            }}
                          >
                            <span
                              style={{
                                fontWeight: 600,
                                fontSize: "var(--font-micro)",
                                textTransform: "uppercase",
                                letterSpacing: "0.5px",
                                color: "var(--brand-secondary)",
                                display: "block",
                                marginBottom: 4,
                              }}
                            >
                              Reactie
                            </span>
                            {item.response}
                          </div>
                        )}
                      </div>
                    );
                  })
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Inline keyframes */}
      <style>{`
        @keyframes feedbackSlideIn {
          from {
            opacity: 0;
            transform: translateY(8px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
      `}</style>
    </>
  );
}
