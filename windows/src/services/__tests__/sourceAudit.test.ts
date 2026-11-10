import { expect, it, vi } from "vitest";
import { appendSourceWarning, auditNotule, auditSource, UNCHECKED_SOURCE_WARNING, UNCLEAR_SOURCE_WARNING } from "../notuleAudit";
import { extractTitle } from "../titleExtractor";

it("checks the source and separate user note without exposing the candidate", async () => {
  const request = vi.fn(async (_system: string, user: string) => {
    expect(JSON.parse(user.slice(user.indexOf("\n") + 1))).toEqual({ source: "Noor controleert vrijdag.", quickNote: "Budget is nog onbeslist." });
    return '{"uncertain":false}';
  });
  await expect(auditSource("Noor controleert vrijdag.", "Budget is nog onbeslist.", request)).resolves.toBeNull();
  expect(request).toHaveBeenCalledTimes(1);
});

it.each([
  ["not JSON", UNCHECKED_SOURCE_WARNING], ["null", UNCLEAR_SOURCE_WARNING], ["{}", UNCLEAR_SOURCE_WARNING],
  ['{"uncertain":true}', UNCLEAR_SOURCE_WARNING], ['{"uncertain":"false"}', UNCLEAR_SOURCE_WARNING], ['{"uncertain":0}', UNCLEAR_SOURCE_WARNING],
])("warns on uncertain or invalid source evidence without retry: %s", async (response, warning) => {
  const request = vi.fn(async () => response);
  await expect(auditSource("Noor controleert vrijdag.", "", request)).resolves.toBe(warning);
  expect(request).toHaveBeenCalledTimes(1);
});

it("rejects empty or oversized sources before making a request", async () => {
  const request = vi.fn();
  for (const source of ["", "a".repeat(64_001)]) await expect(auditSource(source, "", request)).rejects.toThrow();
  expect(request).not.toHaveBeenCalled();
});

it("places the warning before </body> when the notule is a full document, otherwise at the end", () => {
  const section = `<h2>Let op: controleer de transcriptie</h2><p>${UNCLEAR_SOURCE_WARNING}</p>`;
  expect(appendSourceWarning(UNCLEAR_SOURCE_WARNING, "<html><body><p>Notule.</p></BODY></html>")).toBe(`<html><body><p>Notule.</p>${section}</BODY></html>`);
  expect(appendSourceWarning(UNCLEAR_SOURCE_WARNING, "<p>x</p>")).toBe(`<p>x</p>${section}`);
  expect(appendSourceWarning(null, "<p>x</p>")).toBe("<p>x</p>");
});

it("keeps the insertion point when lowercasing changes the length", () => {
  const html = "<html><body><p>İstanbul: Noor belt vrijdag.</p></body></html>";
  expect(appendSourceWarning(UNCLEAR_SOURCE_WARNING, html)).toBe(
    `<html><body><p>İstanbul: Noor belt vrijdag.</p><h2>Let op: controleer de transcriptie</h2><p>${UNCLEAR_SOURCE_WARNING}</p></body></html>`);
});

it("never uses the warning heading as the title", () => {
  const html = "<h1>Notulen</h1><h2>Besluiten</h2><p>Noor neemt vrijdag contact op met de leverancier.</p>";
  expect(extractTitle(appendSourceWarning(UNCLEAR_SOURCE_WARNING, html))).toBe(extractTitle(html));
  expect(extractTitle(html)).toBe("Noor neemt vrijdag contact op met de leverancier");
});

it("still audits an exact copy of the source when the source check warned", async () => {
  const positive = '{"uncertain":false,"source":[{"id":"T1","status":"covered"}],"notes":[{"id":"N1","status":"supported","evidence":["T1"]}]}';
  const plain = vi.fn(async () => positive);
  await auditNotule("Noor belt vrijdag.", "<p>Noor belt vrijdag.</p>", "", plain);
  expect(plain).not.toHaveBeenCalled();
  const unclear = vi.fn(async () => positive);
  await auditNotule("Noor belt vrijdag.", "<p>Noor belt vrijdag.</p>", "", unclear, [], true);
  expect(unclear).toHaveBeenCalledTimes(1);
});
