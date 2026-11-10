import type { Update } from "@tauri-apps/plugin-updater";
import { useCallback, useEffect, useRef, useState } from "react";
import { useSettingsStore } from "../stores/settingsStore";
import { isBusy, useRecordingStore } from "../stores/recordingStore";

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
  const installingRef = useRef<Promise<void> | null>(null);

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
        if (candidate && installingRef.current) {
          if (candidate !== updateRef.current) await candidate.close();
          return;
        }
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
                  if (unmountedRef.current || updateRef.current !== candidate) return;
                  downloadedRef.current = true;
                  setDownloaded(true);
                },
                (e) => {
                  if (unmountedRef.current || updateRef.current !== candidate) return;
                  console.warn("Update download failed", e);
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

  const installNow = useCallback(async () => {
    if (installingRef.current) return installingRef.current;
    const update = updateRef.current;
    if (!update || unmountedRef.current || isBusy(useRecordingStore.getState())) return;
    if (!downloadRef.current) {
      downloadRef.current = update.download().then(() => {
        if (unmountedRef.current || updateRef.current !== update) return;
        downloadedRef.current = true;
        setDownloaded(true);
      }, (error) => {
        if (updateRef.current === update) downloadRef.current = null;
        throw error;
      });
    }
    await downloadRef.current;
    if (installingRef.current) return installingRef.current;
    if (unmountedRef.current || updateRef.current !== update || isBusy(useRecordingStore.getState())) return;
    if (!downloadedRef.current) throw new Error("Update download failed");
    const installation = update.install();
    installingRef.current = installation;
    try {
      await installation;
    } finally {
      if (installingRef.current === installation) installingRef.current = null;
    }
  }, []);

  useEffect(() => {
    unmountedRef.current = false;
    return () => {
      unmountedRef.current = true;
      if (!downloadedRef.current) void updateRef.current?.close().catch(() => {});
    };
  }, []);

  // Install a downloaded update when the window closes and nothing is running.
  useEffect(() => {
    if (!("__TAURI_INTERNALS__" in window)) return;
    let disposed = false;
    let unlisten: (() => void) | null = null;
    void (async () => {
      try {
        const { getCurrentWindow } = await import("@tauri-apps/api/window");
        const un = await getCurrentWindow().onCloseRequested(async (event) => {
          if (disposed) return;
          const update = updateRef.current;
          let installation = installingRef.current;
          if (!installation) {
            if (!update || !downloadedRef.current) return;
            if (!useSettingsStore.getState().check_for_updates) return;
            if (isBusy(useRecordingStore.getState())) return;
          }
          event.preventDefault();
          try {
            if (!installation) {
              installation = update!.install();
              installingRef.current = installation;
            }
            await installation;
          } catch (e) {
            console.warn("Update install failed", e);
            // preventDefault stopped the default close, so close by hand.
            try { await getCurrentWindow().destroy(); } catch { /* nothing left to do */ }
          } finally {
            if (installingRef.current === installation) installingRef.current = null;
          }
        });
        if (disposed) un(); else unlisten = un;
      } catch { /* not running inside Tauri */ }
    })();
    return () => { disposed = true; unlisten?.(); };
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

  return { isUpdateAvailable: latestVersion !== null, latestVersion, downloadUrl, nativeUpdate, downloaded, installNow };
}
