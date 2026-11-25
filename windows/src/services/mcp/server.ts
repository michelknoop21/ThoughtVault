// Connects the Rust listener (src-tauri/src/mcp.rs) to the router: each `mcp-request` line is
// answered through `mcp_respond`. Runs in the main window while the setting is on.
// Every line gets exactly one `mcp_respond`; an empty line tells Rust no answer is due, so it can
// close a half-closed connection once all requests are settled.
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useSettingsStore } from "../../stores/settingsStore";
import { getAppVersion } from "../tauriCommands";
import { log } from "../appLog";
import { handleMessage } from "./router";
import { handlers } from "./tools";

/** Starts or stops the local MCP server; the returned function removes the request listener. */
export function syncMcpServer(enabled: boolean): () => void {
  if (!enabled) {
    void invoke("mcp_set_enabled", { enabled: false }).catch(() => {});
    return () => {};
  }
  let stopped = false;
  let unlisten: (() => void) | undefined;
  const version = getAppVersion().catch(() => "0");
  void listen<{ conn: number; line: string }>("mcp-request", async ({ payload }) => {
    let response: string | null = null;
    try {
      response = await handleMessage(payload.line, {
        allowWrite: useSettingsStore.getState().mcp_allow_write,
        version: await version,
        handlers,
      });
    } finally {
      await invoke("mcp_respond", { conn: payload.conn, line: response ?? "" }).catch(() => {});
    }
  }).then(async (remove) => {
    if (stopped) return remove();
    unlisten = remove;
    await invoke("mcp_set_enabled", { enabled: true });
  }).catch((error) => log.warn("mcp", `AI-koppeling starten mislukt: ${error instanceof Error ? error.message : String(error)}`));
  return () => {
    stopped = true;
    unlisten?.();
  };
}
