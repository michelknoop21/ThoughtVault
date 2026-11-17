import { useState } from "react";
import type { Update } from "@tauri-apps/plugin-updater";
import { isBusy, useRecordingStore } from "../../stores/recordingStore";
import { ArrowDownload24Regular, Dismiss24Regular } from "./StudioIcons";
import { DesktopDialog } from "./DesktopDialog";

interface UpdateBannerProps {
  version: string;
  downloadUrl: string | null;
  onDismiss: () => void;
  nativeUpdate?: Update | null;
  downloaded?: boolean;
  onInstall?: () => Promise<void>;
  dismissible?: boolean;
}

export function UpdateBanner({ version, downloadUrl, onDismiss, nativeUpdate, downloaded = false, onInstall, dismissible = true }: UpdateBannerProps) {
  const [showDetails, setShowDetails] = useState(false);
  const [installing, setInstalling] = useState(false);
  const [error, setError] = useState("");
  const [opened, setOpened] = useState(false);
  const busy = useRecordingStore(isBusy);
  const direct = !!nativeUpdate && !!onInstall;
  async function handleUpdate() {
    if (installing || isBusy(useRecordingStore.getState())) return;
    setInstalling(true);
    setError("");
    try {
      if (direct) await onInstall!();
      else if (downloadUrl) {
        const { open } = await import("@tauri-apps/plugin-shell");
        await open(downloadUrl);
        setOpened(true);
      } else throw new Error("No installer available");
    } catch {
      setError("Bijwerken mislukt. Controleer je verbinding en probeer opnieuw.");
    } finally { setInstalling(false); }
  }
  return <>
    <section className="desktop-update-banner update-notice" aria-label="Applicatie-update">
      <span className="update-notice-icon"><ArrowDownload24Regular aria-hidden="true" /></span>
      <div className="update-notice-copy">
        <strong>{busy ? "Update klaar. Je opname gaat voor." : `ThoughtVault ${version} is beschikbaar`}</strong>
        <p>{busy ? "Bijwerken kan zodra opnemen en verwerken klaar zijn." : downloaded ? "De update is gedownload en wordt geïnstalleerd als je ThoughtVault afsluit." : "Werk bij wanneer het jou uitkomt."}</p>
      </div>
      <button className="btn btn-accent" onClick={() => { setError(""); setOpened(false); setShowDetails(true); }}>Bekijk update</button>
      {dismissible && <button className="icon-btn" aria-label="Updatemelding verbergen" onClick={onDismiss}><Dismiss24Regular /></button>}
    </section>
    {showDetails && <DesktopDialog label="ThoughtVault bijwerken" onClose={() => { if (!installing) setShowDetails(false); }}>
      <div className="update-sheet">
        <header><ArrowDownload24Regular aria-hidden="true" /><button className="icon-btn" aria-label="Sluiten" disabled={installing} onClick={() => setShowDetails(false)}><Dismiss24Regular /></button></header>
        <h2>Een nieuwe ThoughtVault staat klaar.</h2><p className="update-version">Versie {version}</p>
        <p>{direct ? "De updater downloadt en installeert de nieuwe versie. ThoughtVault sluit daarvoor kort af." : "Download het installatiebestand voor jouw computer. Daarna rond je de installatie zelf af."}</p>
        {!direct && <ol><li>Download het MSI-bestand.</li><li>Sluit ThoughtVault af.</li><li>Open het bestand en volg de installatie.</li></ol>}
        {busy && <p>Rond eerst je opname en verwerking af. Je kunt daarna bijwerken.</p>}
        {opened && <p role="status">De download is in je browser geopend. Open het gedownloade MSI-bestand om de installatie af te ronden.</p>}
        {error && <p className="update-error" role="alert">{error}</p>}
        <footer><button className="btn" disabled={installing} onClick={() => setShowDetails(false)}>Later</button><button className="btn btn-accent" disabled={installing || busy || (!direct && !downloadUrl)} onClick={handleUpdate}>{installing ? "Bezig…" : direct ? "Nu bijwerken" : "Download voor Windows"}</button></footer>
      </div>
    </DesktopDialog>}
  </>;
}
