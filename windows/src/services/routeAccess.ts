import type { ProcessingMode } from "../types";

const LOCAL_ROUTES = new Set(["/", "/recording", "/transcripts", "/tasks", "/settings", "/people", "/profiles"]);

export function canOpenRoute(path: string, mode: ProcessingMode, isAuthenticated: boolean): boolean {
  return isAuthenticated || (mode === "local" && LOCAL_ROUTES.has(path));
}
export function shouldBlockForLocalNotes(mode: "local" | "cloud", localReady: boolean): boolean {
  return mode === "local" && !localReady;
}
