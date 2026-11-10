import type { Update } from "@tauri-apps/plugin-updater";
import { useCallback, useEffect, useRef, useState } from "react";
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

export const UPDATE_CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;
export const CHECK_UPDATES_EVENT = "tv-check-updates";

export function useUpdateCheck() {
  const [nativeUpdate, setNativeUpdate] = useState<Update | null>(null);
  const [latestVersion, setLatestVersion] = useState<string | null>(null);
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const [downloaded, setDownloaded] = useState(false);
  const checkForUpdates = useSettingsStore((s) => s.check_for_updates);
  // Refs mirror the state so install-on-close (Task 2) can read them outside render.
  const updateRef = useRef<Update | null>(null);
  const downloadRef = useRef<Promise<void> | null>(null);
  const downloadedRef = useRef(false);
  const unmountedRef = useRef(false);

  const runCheck = useCallback(async () => {
    if (!("__TAURI_INTERNALS__" in window)) return;
    try {
      const { getVersion, getName } = await import("@tauri-apps/api/app");
      const currentVersion = await getVersion();
      const appName = await getName();

      try {
        const { check } = await import("@tauri-apps/plugin-updater");
        const candidate = await check();
        if (candidate && unmountedRef.current) { await candidate.close(); return; }
        if (candidate?.version) {
          const held = updateRef.current;
          if (held && held.version === candidate.version && downloadRef.current) {
            // Same version already downloading or downloaded: keep the held one.
            await candidate.close();
          } else {
            if (held && held !== candidate) void held.close().catch(() => {});
            updateRef.current = candidate;
            downloadRef.current = null;
            downloadedRef.current = false;
            setDownloaded(false);
            setNativeUpdate(candidate);
            setLatestVersion(candidate.version);
            if (useSettingsStore.getState().check_for_updates) {
              const p = candidate.download().then(
                () => {
                  if (updateRef.current !== candidate) return;
                  downloadedRef.current = true;
                  setDownloaded(true);
                },
                (e) => {
                  console.warn("Update download failed", e);
                  if (updateRef.current !== candidate) return;
                  downloadRef.current = null;
                  downloadedRef.current = false;
                  setDownloaded(false);
                },
              );
              downloadRef.current = p;
            }
          }
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
      if (unmountedRef.current) return;

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
  }, []);

  useEffect(() => {
    unmountedRef.current = false;
    return () => {
      unmountedRef.current = true;
      if (!downloadedRef.current) void updateRef.current?.close().catch(() => {});
    };
  }, []);

  useEffect(() => {
    if (!checkForUpdates) return;
    void runCheck();
    const id = setInterval(() => void runCheck(), UPDATE_CHECK_INTERVAL_MS);
    return () => clearInterval(id);
  }, [checkForUpdates, runCheck]);

  // Registered regardless of the toggle so the settings button always works.
  useEffect(() => {
    const onEvent = () => void runCheck();
    window.addEventListener(CHECK_UPDATES_EVENT, onEvent);
    return () => window.removeEventListener(CHECK_UPDATES_EVENT, onEvent);
  }, [runCheck]);

  return { isUpdateAvailable: latestVersion !== null, latestVersion, downloadUrl, nativeUpdate, downloaded };
}
