import { expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { AUDIT_SUFFIX_TEXT, KORT_BLOCK, NORMAAL_BLOCK } from "../notuleDetailLevel";

// The detail level texts must stay identical on both platforms. In the test container the Swift folder is
// mounted next to the copied windows folder, at the same relative path as in the repository.
const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

it.each([["KORT_BLOCK", KORT_BLOCK], ["NORMAAL_BLOCK", NORMAAL_BLOCK], ["AUDIT_SUFFIX_TEXT", AUDIT_SUFFIX_TEXT]])(
  "%s appears verbatim in the Swift and TypeScript sources", (_name, text) => {
    expect(text.length).toBeGreaterThan(200);
    expect(read("../../../../macos/Services/NotuleDetailLevel.swift")).toContain(`"${text}"`);
    expect(read("../notuleDetailLevel.ts")).toContain(`"${text}"`);
  });
