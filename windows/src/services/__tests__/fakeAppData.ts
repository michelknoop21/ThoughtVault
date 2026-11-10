// In-memory stand-in for the app data directory behind the Tauri file commands.
// The map lives on globalThis so it survives vi.resetModules().
import { vi } from "vitest";

const holder = globalThis as unknown as { __appDataFiles?: Map<string, string> };
export const files: Map<string, string> = (holder.__appDataFiles ??= new Map());

export const tauriCore = {
  invoke: vi.fn(async (command: string, args: Record<string, unknown> = {}) => {
    const name = args.name as string;
    switch (command) {
      case "load_personal_corrections": {
        const raw = files.get("personal-corrections.json");
        return raw === undefined ? null : JSON.parse(raw);
      }
      case "save_personal_corrections":
        files.set("personal-corrections.json", JSON.stringify(args.document));
        return undefined;
      case "read_context_file":
        return files.get(name) ?? null;
      case "write_context_file":
        files.set(name, args.contents as string);
        return undefined;
      case "set_aside_context_file":
        files.set(`${name}.unreadable-${args.suffix}`, files.get(name) ?? "");
        files.delete(name);
        return undefined;
    }
    throw Error(`Unexpected command ${command}`);
  }),
};
