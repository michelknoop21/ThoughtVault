import { expect, it, vi } from "vitest";
import { appendWarnings, auditSource, UNCHECKED_SOURCE_WARNING, UNCLEAR_SOURCE_WARNING } from "../notuleAudit";

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
  const warnings = [UNCLEAR_SOURCE_WARNING, "A <b> & c"];
  const section = `<h2>Even nalopen</h2><ul><li>${UNCLEAR_SOURCE_WARNING}</li><li>A &lt;b&gt; &amp; c</li></ul>`;
  expect(appendWarnings(warnings, "<html><body><p>Notule.</p></BODY></html>")).toBe(`<html><body><p>Notule.</p>${section}</BODY></html>`);
  expect(appendWarnings(warnings, "<p>x</p>")).toBe(`<p>x</p>${section}`);
  expect(appendWarnings([], "<p>x</p>")).toBe("<p>x</p>");
});
