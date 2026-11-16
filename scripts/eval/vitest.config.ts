// Plain object on purpose: this file lives outside windows/, so it cannot import from vitest/config.
import { resolve } from "node:path";

const here = import.meta.dirname;
const windows = resolve(here, "../../windows");

export default {
  root: windows,
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: [resolve(windows, "src/test-setup.ts")],
    include: [resolve(here, "eval.test.ts")],
    testTimeout: 6 * 3600 * 1000,
    hookTimeout: 60_000,
    reporters: ["dot"],
  },
  resolve: { alias: { "@tauri-apps/api/core": resolve(here, "tauri-core-shim.ts") } },
  server: { fs: { strict: false } },
};
