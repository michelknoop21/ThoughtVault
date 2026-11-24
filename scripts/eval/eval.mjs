#!/usr/bin/env node
// Entry point: runs eval.test.ts through the vitest that is already installed in windows/.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const here = import.meta.dirname;
const windows = resolve(here, "../../windows");
const vitest = resolve(windows, "node_modules/.bin/vitest");
if (!existsSync(vitest)) {
  console.error("windows/node_modules ontbreekt: draai eerst npm ci in windows/.");
  process.exit(2);
}
const result = spawnSync(vitest, ["run", "--config", resolve(here, "vitest.config.ts")], {
  cwd: windows,
  stdio: "inherit",
  env: { ...process.env, EVAL_ARGS: JSON.stringify(process.argv.slice(2)) },
});
process.exit(result.status ?? 1);
