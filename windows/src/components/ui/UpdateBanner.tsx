import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { ArrowDownload24Regular, Dismiss24Regular } from "@fluentui/react-icons";

interface UpdateBannerProps {
  version: string;
  downloadUrl: string | null;
  onDismiss: () => void;
}

export function UpdateBanner({ version, downloadUrl, onDismiss }: UpdateBannerProps) {
  const [installing, setInstalling] = useState(false);

  async function handleUpdate() {
    if (!downloadUrl) return;
    setInstalling(true);
    try {
      // Download the MSI and hand off to the installer; the app quits itself.
      await invoke("download_and_run_installer", { url: downloadUrl });
    } catch {
      // Fall back to a browser download if the in-app installer fails.
      try {
        const { open } = await import("@tauri-apps/plugin-shell");
        await open(downloadUrl);
      } catch {
        window.open(downloadUrl, "_blank");
      }
      setInstalling(false);
    }
  }

  return (
    <div
      className="card flex-row gap-12"
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
      {downloadUrl && (
        <button
          onClick={(e) => { e.stopPropagation(); handleUpdate(); }}
          disabled={installing}
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
