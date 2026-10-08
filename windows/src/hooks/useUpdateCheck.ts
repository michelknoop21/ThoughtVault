import type { Update } from "@tauri-apps/plugin-updater";
import { useEffect, useState } from "react";
import { useSettingsStore } from "../stores/settingsStore";

const RELEASES_URL = "https://thoughtvault.yinga.ai/d-05921304471ce66e62d0a2b7f324c2354dfb1d895d23a895bba7f86110e2472e/releases.json";
const DOWNLOAD_BASE = "https://thoughtvault.yinga.ai";

function isNewer(remote: string, local: string): boolean {
  const r = remote.split(".").map(Number);
  const l = local.split(".").map(Number);
  if (r.length < 3 || l.length < 3) return false;
  if (r[0] !== l[0]) return r[0] > l[0];
  if (r[1] !== l[1]) return r[1] > l[1];
  return r[2] > l[2];
}

export function useUpdateCheck() {
  const [nativeUpdate, setNativeUpdate] = useState<Update | null>(null);
  const [latestVersion, setLatestVersion] = useState<string | null>(null);
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const checkForUpdates = useSettingsStore((s) => s.check_for_updates);

  useEffect(() => {
    if (!checkForUpdates) return;
    if (!("__TAURI_INTERNALS__" in window)) return;

    let cancelled = false;
    let allocated: Update | null = null;

    (async () => {
      try {
        const { getVersion, getName } = await import("@tauri-apps/api/app");
        const currentVersion = await getVersion();
        const appName = await getName();

        try {
          const {check} = await import("@tauri-apps/plugin-updater");
          const candidate = await check();
          allocated = candidate;
          if (cancelled) { await candidate?.close(); return; }
          if (candidate?.version) {
            setNativeUpdate(candidate);
            setLatestVersion(candidate.version);
          }
        } catch { /* The existing manifest check remains a fallback. */ }
        const res = await fetch(RELEASES_URL);
        if (!res.ok) return;
        const json = await res.json();

        // Determine channel from app title
        const isDev = appName.toLowerCase().includes("dev");

        const platformKey = isDev ? "dev_windows_x64" : "windows_x64";
        const platformInfo = json[platformKey];
        const remoteVersion = platformInfo?.version;
        if (!remoteVersion || typeof remoteVersion !== "string") return;
        if (cancelled) return;

        if (isNewer(remoteVersion, currentVersion)) {
          setLatestVersion(remoteVersion);
          if (platformInfo?.url) {
            const url = new URL(platformInfo.url, DOWNLOAD_BASE);
            if (url.origin === DOWNLOAD_BASE && url.pathname.startsWith("/d-05921304471ce66e62d0a2b7f324c2354dfb1d895d23a895bba7f86110e2472e/")) setDownloadUrl(url.href);
          }
        }
      } catch {
        // Silently ignore — update check is best-effort
      }
    })();

    return () => { cancelled = true; void allocated?.close().catch(() => {}); };
  }, [checkForUpdates]);

  return { isUpdateAvailable: latestVersion !== null, latestVersion, downloadUrl, nativeUpdate };
}
