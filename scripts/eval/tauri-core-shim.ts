// Stands in for @tauri-apps/api/core outside the Tauri shell; eval.test.ts installs the handler.
type Handler = (command: string, args?: unknown) => Promise<unknown>;
export const invoke = (command: string, args?: unknown) => (globalThis as { __evalInvoke?: Handler }).__evalInvoke!(command, args);
