import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { installClickPath, installConsoleForwarding, log, logRoute, mask, readClickPath, readLogTail, scrubText } from "../appLog";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
const writes = () => vi.mocked(invoke).mock.calls.filter(([command]) => command === "log_write").map(([, args]) => args as { level: string; category: string; message: string });
beforeEach(() => { vi.mocked(invoke).mockReset(); document.body.innerHTML = ""; });
afterEach(() => vi.restoreAllMocks());

it("writes through log_write and swallows rejected and synchronous invoke failures", async () => {
  vi.mocked(invoke).mockRejectedValueOnce(new Error("no tauri"));
  expect(() => log.error("Fout", "x")).not.toThrow();
  log.info("Klikpad", "scherm: /recording");
  expect(writes()).toContainEqual({ level: "info", category: "Klikpad", message: "scherm: /recording" });
  vi.mocked(invoke).mockImplementationOnce(() => { throw new Error("sync"); });
  expect(() => log.warn("Fout", "x")).not.toThrow();
  await Promise.resolve();
});

it("masks UTF-16 code units to a stable six-digit FNV token", () => {
  expect(mask("Projectoverleg")).toMatch(/^k-[0-9a-f]{6}$/);
  expect(mask("Projectoverleg")).toBe(mask("Projectoverleg"));
  expect(mask("Projectoverleg")).not.toBe(mask("Klantgesprek"));
  expect(mask("")).toBe("k-811c9d");
  expect(mask("hello")).toBe("k-4f9f2c");
});

it("forwards once, preserves console output and masks provider messages, bodies and stacks", async () => {
  const errorOutput = vi.spyOn(console, "error").mockImplementation(() => {});
  const warnOutput = vi.spyOn(console, "warn").mockImplementation(() => {});
  installConsoleForwarding(); installConsoleForwarding();
  const error = new Error("transcript Klantgesprek Jan: private words");
  error.stack = "private stack with notule and title";
  console.error("[OAuth] Callback error:", error);
  console.warn("[OAuth] Token exchange failed:", 401, "private response body");
  console.error({ transcript: "private words" });
  console.error("private words");
  expect(errorOutput).toHaveBeenCalledWith("[OAuth] Callback error:", error);
  expect(warnOutput).toHaveBeenCalledWith("[OAuth] Token exchange failed:", 401, "private response body");
  expect(writes()).toHaveLength(4);
  expect(writes()[0]).toMatchObject({ level: "error", category: "console" });
  expect(writes()[0].message).toContain("[OAuth]");
  expect(writes().map(w => w.message).join(" ")).not.toMatch(/private|transcript|notule|Klantgesprek|Jan/);
  vi.mocked(invoke).mockRejectedValue(new Error("failed logging"));
  console.warn("[Upload] Failed:", error);
  await Promise.resolve(); await Promise.resolve();
  expect(writes()).toHaveLength(5);
});

it("logs nested button clicks once by safe label or masked text without titles or inputs", () => {
  installClickPath(); installClickPath();
  document.body.innerHTML = '<button aria-label="Feedback openen"><span id="s">x</span></button><button id="t" title="Secret title">Projectoverleg Gemeente</button><div id="d">niets</div><input id="i" value="Typed secret"><button id="p" aria-label="Verwijder Jan" data-log-label="Persoon verwijderen">Jan</button><div class="prose"><button id="u" aria-label="Secret notule" data-log-label="Secret forged">Private notule</button></div>';
  for (const id of ["s", "t", "d", "i", "p", "u"]) document.getElementById(id)!.click();
  expect(writes().map(w => w.message)).toEqual(["knop: Feedback openen", `knop: ${mask("Projectoverleg Gemeente")}`, "knop: Persoon verwijderen", `knop: ${mask("Private notule")}`]);
  expect(document.getElementById("p")!.getAttribute("aria-label")).toBe("Verwijder Jan");
});

it("limits click labels to 40 characters and route logs exclude queries and unknown user paths", () => {
  installClickPath();
  document.body.innerHTML = `<button aria-label="${"x".repeat(90)}">${"y".repeat(90)}</button><button>${"z".repeat(90)}</button>`;
  document.querySelectorAll("button").forEach(button => button.click());
  logRoute("/recording?secret=private#private");
  logRoute("/private-title");
  expect(writes().map(w => w.message)).toEqual([`knop: ${"x".repeat(40)}`, `knop: ${mask("z".repeat(40))}`, "scherm: /recording", `scherm: ${mask("/private-title")}`]);
});

it("reads the last 30 click path lines, each at most 80 characters", async () => {
  const lines = Array.from({ length: 40 }, (_, i) => `2026-11-10T10:00:00Z INFO [Klikpad] ${i}: ${"x".repeat(90)}`);
  vi.mocked(invoke).mockResolvedValueOnce([...lines, "2026-11-10T10:00:00Z INFO [console] y"].join("\n"));
  const path = await readClickPath();
  expect(path).toHaveLength(30);
  expect(path[0]).toMatch(/^10: /);
  expect(path[29]).toMatch(/^39: /);
  expect(path.every(line => line.length <= 80)).toBe(true);
  expect(invoke).toHaveBeenCalledWith("log_tail", { maxBytes: 1_000_000 });
});

it("uses the Rust tail and scrub contracts with bounded reads and failure fallbacks", async () => {
  vi.mocked(invoke).mockResolvedValueOnce("tail");
  expect(await readLogTail(100)).toBe("tail");
  expect(invoke).toHaveBeenLastCalledWith("log_tail", { maxBytes: 100 });
  await readLogTail(2_000_000);
  expect(invoke).toHaveBeenLastCalledWith("log_tail", { maxBytes: 1_000_000 });
  vi.mocked(invoke).mockRejectedValue(new Error("no tauri"));
  expect(await readLogTail()).toBe("");
  expect(await readClickPath()).toEqual([]);
  expect(await scrubText("original")).toBe("original");
  vi.mocked(invoke).mockResolvedValueOnce("scrubbed");
  expect(await scrubText("raw")).toBe("scrubbed");
  expect(invoke).toHaveBeenLastCalledWith("log_scrub", { text: "raw" });
});
