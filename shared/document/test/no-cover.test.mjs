import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
test("the bundled Yinga notes use the compact layout without a cover", async () => {
  const yinga = JSON.parse(await readFile(new URL("../dist/Yinga.tvhuisstijl", import.meta.url), "utf8"));
  assert.equal(yinga.layout, "compact");
  assert.equal(yinga.runningHeader, true);
  assert.equal(yinga.runningFooter, true);
});
