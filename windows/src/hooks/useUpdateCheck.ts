import { beginMainCloseHandler, hasMainWork, mustKeepMain } from "../services/mainWindowLifetime";
import type { Update } from "@tauri-apps/plugin-updater";
import { useCallback, useEffect, useRef, useState } from "react";
import { useSettingsStore } from "../stores/settingsStore";

const RELEASES_URL = "https://thoughtvault.yinga.ai/d-05921304471ce66e62d0a2b7f324c2354dfb1d895d23a895bba7f86110e2472e/releases.json";

function isNewer(remote: string, local: string): boolean {
  if (!/^\d+\.\d+\.\d+$/.test(remote) || !/^\d+\.\d+\.\d+$/.test(local)) return false;
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
      // A verified native candidate owns both the version and its installation action.
      if (updateRef.current) return;
      const res = await fetch(RELEASES_URL, { cache: "no-store" });
      if (!res.ok) return;
      const json = await res.json();

      // Determine channel from app title
      const isDev = appName.toLowerCase().includes("dev");

      const { invoke } = await import("@tauri-apps/api/core");
      const architecture = await invoke<string>("app_architecture");
      // Never offer an x64 installer to an ARM installation when architecture is unknown.
      if (architecture !== "x86_64" && architecture !== "aarch64") return;
      const platformKey = `${isDev ? "dev_" : ""}windows_${architecture === "aarch64" ? "arm64" : "x64"}`;
      const platformInfo = json[platformKey];
      const remoteVersion = platformInfo?.version;
      if (!remoteVersion || typeof remoteVersion !== "string") return;
      if (unmountedRef.current || updateRef.current) return;

      if (isNewer(remoteVersion, currentVersion)) {
        const filename = platformInfo?.filename;
        const rawUrl = platformInfo?.download_url ?? platformInfo?.url;
        const url = new URL(rawUrl ?? filename, RELEASES_URL);
        const base = new URL(RELEASES_URL);
        if (url.origin !== base.origin || url.username || url.password || url.search || url.hash ||
            url.pathname.slice(0, url.pathname.lastIndexOf("/") + 1) !== base.pathname.replace("releases.json", "") ||
            !/^[A-Za-z0-9._-]+\.msi$/.test(decodeURIComponent(url.pathname.split("/").pop() ?? ""))) return;
        setLatestVersion(remoteVersion);
        setDownloadUrl(url.href);
      }
    } catch {
      // Silently ignore — update check is best-effort
    }
  }, []);

  const installNow = useCallback(async () => {
    if (installingRef.current) return installingRef.current;
    const update = updateRef.current;
    if (!update || unmountedRef.current) return;
    const keepBeforeDownload = await mustKeepMain();
    if (installingRef.current) return installingRef.current;
    if (unmountedRef.current || updateRef.current !== update || keepBeforeDownload || hasMainWork()) return;
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
    const keepBeforeInstall = await mustKeepMain();
    if (unmountedRef.current || updateRef.current !== update || keepBeforeInstall || hasMainWork()) return;
    if (installingRef.current) return installingRef.current;
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
    const registration = beginMainCloseHandler();
    let unlisten: (() => void) | null = null;
    void (async () => {
      try {
        const { getCurrentWindow } = await import("@tauri-apps/api/window");
        if (disposed) return;
        const un = await getCurrentWindow().onCloseRequested(async (event) => {
          event.preventDefault();
          if (disposed) return;
          let installation = installingRef.current;
          // Prevent synchronously, before any asynchronous widget lookup can allow default destruction.
          try {
            if (!installation) {
              const keep = await mustKeepMain();
              if (disposed) return;
              if (keep || hasMainWork()) { await getCurrentWindow().hide(); return; }
            }
          } catch { return; } // Keep the owner when native window enumeration fails.
          const update = updateRef.current;
          installation ??= installingRef.current;
          if (!installation) {
            if (!update || !downloadedRef.current || !useSettingsStore.getState().check_for_updates) {
              try { await getCurrentWindow().destroy(); }
              catch { /* Keep main; a subsequent close can retry. */ }
              return;
            }
          }
          try {
            if (!installation) {
              installation = update!.install();
              installingRef.current = installation;
            }
            await installation;
          } catch (e) {
            console.warn("Update install failed", e);
            // preventDefault stopped the default close, so close by hand.
            try {
              const keep = await mustKeepMain();
              if (disposed) return;
              if (keep || hasMainWork()) await getCurrentWindow().hide();
              else await getCurrentWindow().destroy();
            } catch { /* Keep main if native state cannot be checked. */ }
          } finally {
            if (installingRef.current === installation) installingRef.current = null;
          }
        });
        if (disposed || !registration.activate()) un(); else unlisten = un;
      } catch { registration.dispose(); }
    })();
    return () => { disposed = true; registration.dispose(); unlisten?.(); };
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
