import { api } from "./api";

let initialized = false;

export function initCrashReporter() {
  if (initialized) return;
  initialized = true;

  window.addEventListener("error", (event) => {
    reportCrash({
      type: "uncaught_error",
      message: event.message,
      filename: event.filename,
      line: event.lineno,
      col: event.colno,
      stack: event.error?.stack,
    });
  });

  window.addEventListener("unhandledrejection", (event) => {
    const reason = event.reason;
    reportCrash({
      type: "unhandled_rejection",
      message: reason?.message ?? String(reason),
      stack: reason?.stack,
    });
  });
}

function reportCrash(data: Record<string, unknown>) {
  try {
    api.submitFeedback({
      title: `[Crash] ${String(data.message).slice(0, 80)}`,
      category: "bug",
      description: [
        `Type: ${data.type}`,
        data.filename ? `File: ${data.filename}:${data.line}:${data.col}` : "",
        `Stack: ${data.stack ?? "n/a"}`,
        `Time: ${new Date().toISOString()}`,
        `URL: ${window.location.pathname}`,
      ].filter(Boolean).join("\n"),
    }).catch(() => {
      // Silently fail — can't report a crash if API is down
    });
  } catch {
    // Prevent crash reporter from crashing
  }
}
