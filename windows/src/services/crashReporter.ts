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
  console.error("[ThoughtVault]", data);
}
