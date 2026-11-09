import { expect, it, vi } from "vitest";
import { auditSource } from "../notuleAudit";

it("checks the source and separate user note without exposing the candidate", async () => {
  const request = vi.fn(async (_system: string, user: string) => {
    expect(JSON.parse(user.slice(user.indexOf("\n") + 1))).toEqual({ source: "Noor controleert vrijdag.", quickNote: "Budget is nog onbeslist." });
    return '{"uncertain":false}';
  });
  await expect(auditSource("Noor controleert vrijdag.", "Budget is nog onbeslist.", request)).resolves.toBeUndefined();
  expect(request).toHaveBeenCalledTimes(1);
});

it.each([
  'not JSON', 'null', '{}', '{"uncertain":true}', '{"uncertain":"false"}', '{"uncertain":0}',
])("rejects uncertain or invalid source evidence without retry: %s", async response => {
  const request = vi.fn(async () => response);
  await expect(auditSource("Noor controleert vrijdag.", "", request)).rejects.toThrow();
  expect(request).toHaveBeenCalledTimes(1);
});

it("rejects empty or oversized sources before making a request", async () => {
  const request = vi.fn();
  for (const source of ["", "a".repeat(64_001)]) await expect(auditSource(source, "", request)).rejects.toThrow();
  expect(request).not.toHaveBeenCalled();
});
