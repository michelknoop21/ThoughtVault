import { useState } from "react";
import type { Update } from "@tauri-apps/plugin-updater";
import { ArrowDownload24Regular, Dismiss24Regular } from "@fluentui/react-icons";
import { useRecordingStore } from "../../stores/recordingStore";

export function updateIsBusy(state: Pick<ReturnType<typeof useRecordingStore.getState>, "phase" | "backgroundTasks" | "isSubmittingYouTube" | "regenerationCount">): boolean {
  return state.phase !== "idle" || state.isSubmittingYouTube || state.regenerationCount > 0 ||
    state.backgroundTasks.some((task) => !["completed", "failed", "cancelled"].includes(task.status));
}

export function UpdateBanner({ update, onDismiss }: { update: Update; onDismiss: () => void }) {
  const [installing, setInstalling] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const busy = useRecordingStore(updateIsBusy);
  async function install() {
    if (updateIsBusy(useRecordingStore.getState())) return;
    setInstalling(true); setError(null);
    try {
      let total = 0, received = 0;
      await update.download((event) => {
        if (event.event === "Started") total = event.data.contentLength ?? 0;
        if (event.event === "Progress") received += event.data.chunkLength;
        if (total) setProgress(Math.round(received / total * 100));
      }, { timeout: 600000 });
      if (updateIsBusy(useRecordingStore.getState())) throw Error("Opnemen of verwerken is gestart. Probeer bijwerken zodra dit klaar is.");
      useRecordingStore.setState({ updateInstalling: true });
      await update.install();
    } catch (cause) {
      setError(`Bijwerken mislukt: ${cause instanceof Error ? cause.message : String(cause)}`);
      useRecordingStore.setState({ updateInstalling: false });
      setInstalling(false);
    }
  }
  return <div className="card flex-row gap-12" role="status" style={{ padding: "10px 14px", alignItems: "center" }}>
    <ArrowDownload24Regular aria-hidden />
    <div className="flex-1">
      <p>Versie {update.version} is beschikbaar</p>
      {busy && <p>Bijwerken kan zodra opnemen en verwerken klaar zijn.</p>}
      {error && <p role="alert">{error}</p>}
    </div>
    <button className="btn btn-accent btn-sm" disabled={installing || busy} onClick={() => void install()}>
      {installing ? `Bijwerken… ${progress}%` : error ? "Opnieuw proberen" : "Nu bijwerken"}
    </button>
    <button className="icon-btn icon-btn-sm" aria-label="Updatemelding sluiten" disabled={installing} onClick={onDismiss}><Dismiss24Regular /></button>
  </div>;
}
