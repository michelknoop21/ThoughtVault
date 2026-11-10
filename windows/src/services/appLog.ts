import { invoke } from "@tauri-apps/api/core";

export type LogLevel = "info" | "warn" | "error";

function write(level: LogLevel, category: string, message: string): void {
  try { void invoke("log_write", { level, category, message }).catch(() => {}); }
  catch { /* Logging must also work outside Tauri. */ }
}

export const log: Record<LogLevel, (category: string, message: string) => void> = {
  info: (category, message) => write("info", category, message),
  warn: (category, message) => write("warn", category, message),
  error: (category, message) => write("error", category, message),
};

export function mask(value: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) hash = Math.imul(hash ^ value.charCodeAt(i), 0x01000193);
  return `k-${(hash >>> 0).toString(16).padStart(8, "0").slice(0, 6)}`;
}

// Only audited fixed contexts are readable: provider errors and stacks can contain meeting text.
const consoleContexts = /^\[(TaskRecovery|App|OAuth|Recording|Widget|API|SSE|Upload|LocalPipeline|ContextSuggestions|PersonMatcher|PersonalCorrections|ErrorBoundary)\](?: |$)/;
function consoleArgument(value: unknown): string {
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (typeof value === "string") {
    const context = value.match(consoleContexts)?.[0].trim();
    return context ? `${context} ${mask(value.slice(context.length))}` : mask(value);
  }
  if (value instanceof Error) return `Error ${mask(value.message)} ${mask(value.stack ?? "")}`;
  // Do not serialize objects: error payloads can contain whole transcripts or secrets.
  return "[details omitted]";
}

let consoleInstalled = false;
export function installConsoleForwarding(): void {
  if (consoleInstalled) return;
  consoleInstalled = true;
  for (const level of ["warn", "error"] as const) {
    const original = console[level].bind(console);
    console[level] = (...args: unknown[]) => {
      original(...args);
      try { log[level]("console", args.map(consoleArgument).join(" ")); }
      catch { /* Never let diagnostic formatting affect the caller. */ }
    };
  }
}

let clicksInstalled = false;
export function installClickPath(): void {
  if (clicksInstalled) return;
  clicksInstalled = true;
  document.addEventListener("click", event => {
    if (!(event.target instanceof Element)) return;
    const button = event.target.closest("button");
    if (!button) return;
    // Rendered notes can contain their own aria-label and data attributes.
    const content = button.closest('.prose, [contenteditable="true"]');
    const label = content ? null : button.getAttribute("data-log-label") ?? button.getAttribute("aria-label");
    log.info("Klikpad", `knop: ${label ? label.slice(0, 40) : mask((button.textContent ?? "").trim().slice(0, 40))}`);
  }, true);
}

const routes = new Set(["/", "/recording", "/tasks", "/transcripts", "/profiles", "/people", "/account", "/settings", "/admin", "/login"]);
export function logRoute(pathname: string): void {
  const path = pathname.split(/[?#]/, 1)[0];
  log.info("Klikpad", `scherm: ${routes.has(path) ? path : mask(path)}`);
}

export async function readLogTail(maxBytes = 1_000_000): Promise<string> {
  try {
    return await invoke<string>("log_tail", { maxBytes: Number.isFinite(maxBytes) ? Math.max(0, Math.min(1_000_000, Math.floor(maxBytes))) : 1_000_000 });
  } catch { return ""; }
}

export async function readClickPath(): Promise<string[]> {
  const lines = (await readLogTail()).split("\n");
  return lines.filter(line => line.includes("[Klikpad] ")).slice(-30).map(line => line.slice(line.indexOf("[Klikpad] ") + 10, line.indexOf("[Klikpad] ") + 90));
}

export async function scrubText(text: string): Promise<string> {
  try { return await invoke<string>("log_scrub", { text }); }
  catch { return text; }
}

// Automatic diagnostics must never fall back to unsanitized input.
export async function scrubReportText(text: string): Promise<string> {
  const scrubbed = await invoke<string>("log_scrub", { text });
  if (typeof scrubbed !== "string") throw new Error("Diagnostic scrubbing failed");
  return scrubbed;
}
