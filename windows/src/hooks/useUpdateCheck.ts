import { useEffect, useState } from "react";
import { useSettingsStore } from "../stores/settingsStore";

const RELEASES_URL = "https://n8n.prezent.nl/tstudio/download/releases.json";
const DOWNLOAD_BASE = "https://n8n.prezent.nl";

function isNewer(remote: string, local: string): boolean {
  const r = remote.split(".").map(Number);
  const l = local.split(".").map(Number);
  if (r.length < 3 || l.length < 3) return false;
  if (r[0] !== l[0]) return r[0] > l[0];
  if (r[1] !== l[1]) return r[1] > l[1];
  return r[2] > l[2];
}

export function useUpdateCheck() {
  const [latestVersion, setLatestVersion] = useState<string | null>(null);
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const checkForUpdates = useSettingsStore((s) => s.check_for_updates);

  useEffect(() => {
    if (!checkForUpdates) return;
    if (!("__TAURI_INTERNALS__" in window)) return;

    let cancelled = false;

    (async () => {
      try {
        const { getVersion } = await import("@tauri-apps/api/app");
        const currentVersion = await getVersion();

        const res = await fetch(RELEASES_URL);
        if (!res.ok) return;
        const json = await res.json();

        // Determine channel from app title
        const isDev = document.title.toLowerCase().includes("dev");

        const versionKey = isDev ? "dev_latest_version" : "latest_version";
        const platformKey = isDev ? "dev_windows_x64" : "windows_x64";

        const remoteVersion = json[versionKey];
        if (!remoteVersion || typeof remoteVersion !== "string") return;
        if (cancelled) return;

        if (isNewer(remoteVersion, currentVersion)) {
          setLatestVersion(remoteVersion);
          const platformInfo = json[platformKey];
          if (platformInfo?.url) {
            setDownloadUrl(DOWNLOAD_BASE + platformInfo.url);
          }
        }
      } catch {
        // Silently ignore — update check is best-effort
      }
    })();

    return () => { cancelled = true; };
  }, [checkForUpdates]);

  return { isUpdateAvailable: latestVersion !== null, latestVersion, downloadUrl };
}
