import { useEffect, useRef, useState } from "react";
import { useUploadQueueStore } from "../stores/uploadQueueStore";
import { useSettingsStore } from "../stores/settingsStore";

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

export function OfflineQueueBanner() {
  const [count, setCount] = useState(0);
  const [processing, setProcessing] = useState(false);
  const isProcessingRef = useRef(false);

  // Upload queue progress state
  const currentItem = useUploadQueueStore((s) => s.currentItem);
  const progress = useUploadQueueStore((s) => s.progress);
  const uploadSpeed = useUploadQueueStore((s) => s.uploadSpeed);
  const queueItems = useUploadQueueStore((s) => s.items);
  const permanentlyFailed = useUploadQueueStore((s) => s.permanentlyFailed);
  const clearPermanentlyFailed = useUploadQueueStore((s) => s.clearPermanentlyFailed);
  const resetQueueStore = useUploadQueueStore((s) => s.reset);
  const processingMode = useSettingsStore((s) => s.processing_mode);

  async function handleClearQueue() {
    try {
      const { clearQueue } = await import("../services/offlineQueue");
      await clearQueue();
    } catch { /* best-effort */ }
    resetQueueStore();
    setCount(0);
  }

  useEffect(() => {
    // The server upload queue only exists in cloud mode.
    if (processingMode === "local") return;
    let cancelled = false;

    async function checkAndProcess() {
      try {
        const { getQueue, processQueue } = await import("../services/offlineQueue");
        const queue = await getQueue();
        if (cancelled) return;
        setCount(queue.length);

        // Try to process queued uploads if there are any and we're not already processing
        if (queue.length > 0 && !isProcessingRef.current) {
          isProcessingRef.current = true;
          setProcessing(true);
          try {
            await processQueue();
            // Re-check queue after processing
            const remaining = await getQueue();
            if (!cancelled) setCount(remaining.length);
          } catch {
            // Processing failed — will retry on next interval
          }
          isProcessingRef.current = false;
          if (!cancelled) setProcessing(false);
        }
      } catch {
        // Queue not available
      }
    }
    checkAndProcess();
    const interval = setInterval(checkAndProcess, 10000);
    return () => { cancelled = true; clearInterval(interval); };
  }, [processingMode]);

  // Never surface the server upload queue in local mode.
  if (processingMode === "local") return null;

  // Use queueItems count if available, otherwise fallback to poll count
  const displayCount = queueItems.length > 0 ? queueItems.length : count;

  // Show permanently failed warning even when queue is empty
  if (displayCount === 0 && !currentItem && permanentlyFailed.length === 0) return null;

  // Permanently failed items warning
  if (displayCount === 0 && !currentItem && permanentlyFailed.length > 0) {
    return (
      <div style={{
        padding: "8px 14px",
        background: "var(--fill-warning, #b45309)",
        color: "#fff",
        fontSize: 12,
        fontWeight: 500,
        flexShrink: 0,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ flex: 1 }}>
            {permanentlyFailed.map((item) => (
              <div key={item.id}>
                '{item.fileName}' kon na meerdere pogingen niet worden ge&uuml;pload. Ga naar Opgeslagen opnames om het handmatig te proberen.
              </div>
            ))}
          </span>
          <button
            onClick={clearPermanentlyFailed}
            style={{ background: "none", border: "none", color: "#fff", cursor: "pointer", fontSize: 14, padding: "2px 6px" }}
          >
            &times;
          </button>
        </div>
      </div>
    );
  }

  const fileName = currentItem?.file_name || currentItem?.file_path?.split(/[\\/]/).pop();
  const fileSize = currentItem?.file_size_bytes;
  const currentIndex = currentItem ? queueItems.findIndex((i) => i.id === currentItem.id) + 1 : 0;

  return (
    <div style={{
      padding: "8px 14px",
      background: "var(--fill-accent-default)",
      color: "#fff",
      fontSize: 12,
      fontWeight: 500,
      flexShrink: 0,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span className="status-pulse" style={{ width: 8, height: 8, borderRadius: "50%", background: "#fff" }} />
        <span style={{ flex: 1 }}>
          {processing && currentItem ? (
            <>
              Uploaden: {fileName && <span>{fileName}</span>}
              {fileSize ? ` (${formatBytes(fileSize)})` : ""}
              {" · "}
              {progress}%
              {uploadSpeed > 0 && ` (${formatBytes(uploadSpeed)}/s)`}
              {displayCount > 1 && ` [${currentIndex}/${displayCount}]`}
            </>
          ) : processing ? (
            `${displayCount} opname${displayCount !== 1 ? "s" : ""} worden verstuurd...`
          ) : (
            `${displayCount} opname${displayCount !== 1 ? "s" : ""} in wachtrij, wordt automatisch verstuurd`
          )}
        </span>
        {!processing && displayCount > 0 && (
          <button
            onClick={handleClearQueue}
            title="Wachtrij leegmaken"
            style={{ background: "rgba(255,255,255,0.2)", border: "1px solid rgba(255,255,255,0.3)", color: "#fff", cursor: "pointer", fontSize: 11, fontWeight: 600, padding: "2px 8px", borderRadius: 4, flexShrink: 0 }}
          >
            Leegmaken
          </button>
        )}
      </div>
      {processing && currentItem && (
        <div style={{
          marginTop: 4,
          height: 3,
          borderRadius: 2,
          background: "rgba(255,255,255,0.25)",
          overflow: "hidden",
        }}>
          <div style={{
            height: "100%",
            width: `${progress}%`,
            background: "#fff",
            borderRadius: 2,
            transition: "width 300ms ease",
          }} />
        </div>
      )}
    </div>
  );
}
