import { useState } from "react";
import type { Update } from "@tauri-apps/plugin-updater";
import { useRecordingStore } from "../../stores/recordingStore";
import { ArrowDownload24Regular, Dismiss24Regular } from "./StudioIcons";

interface UpdateBannerProps {
  version: string;
  downloadUrl: string | null;
  onDismiss: () => void;
  nativeUpdate?: Update | null;
}

export function UpdateBanner({ version, downloadUrl, onDismiss, nativeUpdate }: UpdateBannerProps) {
  const [installing, setInstalling] = useState(false);
  const [error, setError] = useState("");
  const busy = useRecordingStore(s => s.phase !== "idle" || s.backgroundTasks.some(t => !["completed", "failed"].includes(t.status)));

  async function handleUpdate() {
    setInstalling(true);
    setError("");
    try {
      if (nativeUpdate) await nativeUpdate.downloadAndInstall();
      else if (downloadUrl) {
        const { open } = await import("@tauri-apps/plugin-shell");
        await open(downloadUrl);
      }
    } catch {
      setError("Bijwerken mislukt. Probeer opnieuw.");
    } finally {
      setInstalling(false);
    }
  }

  return (
    <div
      className="card flex-row gap-12 desktop-update-banner"
      style={{
        padding: "10px 14px",
        alignItems: "center",
        background: "var(--fill-accent-default)",
        border: "none",
      }}
    >
      <ArrowDownload24Regular style={{ fontSize: 18, color: "#fff", flexShrink: 0 }} />
      <div className="flex-1" style={{ minWidth: 0 }}>
        <p style={{ fontSize: 13, fontWeight: 600, color: "#fff", margin: 0 }}>
          Versie {version} is beschikbaar
        </p>
      </div>
      {error && <p role="alert">{error}</p>}
      {(downloadUrl || nativeUpdate) && (
        <button
          onClick={(e) => { e.stopPropagation(); handleUpdate(); }}
          disabled={installing || busy}
          className="btn btn-sm flex-shrink-0"
          style={{
            background: "rgba(255,255,255,0.2)",
            color: "#fff",
            border: "1px solid rgba(255,255,255,0.3)",
          }}
        >
          {installing ? "Bezig..." : "Nu bijwerken"}
        </button>
      )}
      <button
        onClick={(e) => {
          e.stopPropagation();
          onDismiss();
        }}
        className="icon-btn icon-btn-sm"
        style={{ color: "rgba(255,255,255,0.8)" }}
      >
        <Dismiss24Regular style={{ fontSize: 16 }} />
      </button>
    </div>
  );
}
