import { useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { reportFailure } from "../services/crashReporter";
import { useSupportStore } from "../stores/supportStore";

export async function reportPreviousCrash(): Promise<void> {
  try {
    const previous = await invoke<{ crashed: boolean; stage: unknown }>("session_begin");
    if (!previous.crashed) return;
    const stage = previous.stage;
    if (stage === "opnemen" || stage === "transcriberen" || stage === "notule") {
      await reportFailure(stage, `ThoughtVault stopte onverwacht tijdens ${stage}.`, `gestopt tijdens ${stage}`);
    } else {
      await reportFailure("crash", "ThoughtVault stopte onverwacht.", "gestopt zonder af te sluiten");
    }
  } catch { /* Session diagnostics must not interrupt startup. */ }
}

export function useSupportLifecycle(): void {
  useEffect(() => {
    if (!("__TAURI_INTERNALS__" in window)) return;
    let disposed = false;
    const flush = async () => {
      if (disposed) return;
      try { await useSupportStore.getState().flushQueue(); } catch { /* Retry when online. */ }
    };
    const refresh = async () => {
      if (disposed) return;
      try { await useSupportStore.getState().refreshUnread(); } catch { /* Keep the last count. */ }
    };
    // Rust consumes the previous session once per process, including StrictMode/remounts.
    void reportPreviousCrash().finally(flush);
    void refresh();
    window.addEventListener("online", flush);
    window.addEventListener("focus", refresh);
    const timer = window.setInterval(refresh, 15 * 60 * 1000);
    return () => {
      disposed = true;
      window.removeEventListener("online", flush);
      window.removeEventListener("focus", refresh);
      window.clearInterval(timer);
    };
  }, []);
}
