import { useEffect, useState } from "react";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { useSettingsStore } from "../stores/settingsStore";

export function useUpdateCheck() {
  const [update, setUpdate] = useState<Update | null>(null);
  const enabled = useSettingsStore((s) => s.check_for_updates);
  useEffect(() => {
    if (!enabled || !("__TAURI_INTERNALS__" in window)) { setUpdate(null); return; }
    let cancelled = false;
    let current: Update | null = null;
    let checking = false;
    async function refresh() {
      if (checking) return;
      checking = true;
      try {
        const next = await check({ timeout: 15000 });
        if (cancelled) { await next?.close(); return; }
        // Keep the resource while the banner may be downloading/installing it.
        if (current) { await next?.close(); return; }
        current = next;
        setUpdate(next);
        if (next && localStorage.getItem("notifiedUpdateVersion") !== next.version) {
          const { isPermissionGranted, sendNotification } = await import("@tauri-apps/plugin-notification");
          if (await isPermissionGranted()) {
            sendNotification({ title: "Update beschikbaar", body: `Versie ${next.version} van ThoughtVault is beschikbaar.` });
            localStorage.setItem("notifiedUpdateVersion", next.version);
          }
        }
      } catch { /* Offline checks are best-effort; install errors are shown in the banner. */ }
      finally { checking = false; }
    }
    void refresh();
    const timer = window.setInterval(() => void refresh(), 6 * 60 * 60 * 1000);
    return () => { cancelled = true; window.clearInterval(timer); void current?.close(); };
  }, [enabled]);
  return { update };
}
