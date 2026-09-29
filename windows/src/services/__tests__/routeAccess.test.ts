import { describe, expect, it } from "vitest";
import { canOpenRoute } from "../routeAccess";

describe("route access without an account", () => {
  it("opens the recording, notes, tasks and settings in local mode", () => {
    for (const route of ["/", "/recording", "/transcripts", "/tasks", "/settings", "/people", "/profiles"]) {
      expect(canOpenRoute(route, "local", false)).toBe(true);
    }
  });

  it("keeps account and admin routes behind login", () => {
    for (const route of ["/account", "/admin"]) {
      expect(canOpenRoute(route, "local", false)).toBe(false);
    }
    expect(canOpenRoute("/recording", "cloud", false)).toBe(false);
    expect(canOpenRoute("/recording", "cloud", true)).toBe(true);
  });
});
