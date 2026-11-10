import { log, mask } from "./appLog";

let initialized = false;

export function initCrashReporter(): void {
  if (initialized) return;
  initialized = true;
  window.addEventListener("error", event => {
    try { log.error("Onverwacht", `uncaught_error ${mask(event.message)}`); }
    catch { /* Diagnostics must never cause another error. */ }
  });
  window.addEventListener("unhandledrejection", event => {
    try {
      const reason = event.reason;
      const message = typeof reason === "string" ? reason : reason instanceof Error ? reason.message : "details omitted";
      log.error("Onverwacht", `unhandled_rejection ${mask(message)}`);
    } catch { /* Do not inspect or serialize arbitrary rejection objects. */ }
  });
}
