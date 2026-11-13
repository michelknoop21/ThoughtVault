#!/bin/bash
# Screenshots of the Windows app for the manual (docs/handleiding/media/win-*.webp).
#
# Usage: scripts/handleiding-shots-windows.sh [--only <name>]     (name without .webp)
#
# Runs the real pages in the development-only browser harness (windows/desktop-review.html,
# mocked Tauri backend, ?scenario=handleiding fixtures) on a local Vite server and captures
# every entry of docs/handleiding/media/manifest.windows.json at 1440x900. The Tauri app is
# not built or started. Screens that need a click get their steps in STEPS below.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIN="$ROOT/windows"
MEDIA="$ROOT/docs/handleiding/media"
PORT="${TV_SHOTS_PORT:-48720}"
MODULES="${TV_SHOTS_MODULES:-/Volumes/SSD/Projects/thoughtvault-macos-parity/windows/node_modules}"
WORK="$(mktemp -d)"
LINKED=""; SERVER=""

cleanup() {
    [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null || true
    [ -n "$LINKED" ] && rm -f "$WIN/node_modules"
    rm -rf "$WORK"
}
trap cleanup EXIT

# A worktree has no node_modules: borrow the installed ones, never install here.
if [ ! -e "$WIN/node_modules" ]; then ln -s "$MODULES" "$WIN/node_modules"; LINKED=1; fi
[ -d "$WIN/node_modules/vite" ] || { echo "ERROR: vite ontbreekt in $WIN/node_modules"; exit 1; }
lsof -i ":$PORT" > /dev/null && { echo "ERROR: poort $PORT is bezet"; exit 1; }

# Own cache dir, so the borrowed node_modules/.vite stays untouched.
cd "$WIN"
node -e "import('vite').then(v => v.createServer({ cacheDir: '$WORK/vite', server: { host: '127.0.0.1', port: $PORT, strictPort: true, fs: { allow: ['..', '$MODULES'] } } })).then(s => s.listen())" > "$WORK/vite.log" 2>&1 &
SERVER=$!
for _ in $(seq 30); do curl -sf -o /dev/null "http://127.0.0.1:$PORT/desktop-review.html" && break; sleep 1; done

# The Playwright that `pw` uses.
PW_HOME="$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v pw)")")"
NODE_PATH="$PW_HOME/node_modules" node - "http://127.0.0.1:$PORT/desktop-review.html" "$MEDIA/manifest.windows.json" "$WORK" "${2:-}" <<'JS'
const { chromium } = require("playwright");
const [base, manifest, out, only] = process.argv.slice(2);
const tab = name => page => page.click(`.settings-tabs button:has-text("${name}")`);
// The feedback window opens from Instellingen > Account, as in the app.
const feedback = async page => { await tab("Account")(page); await page.click(".feedback-trigger"); };
const STEPS = {
  "win-notule-open": page => page.click("text=Schadebezoek Keizersgracht"),
  "win-persoon-bewerken": page => page.click("text=Jan de Vries"),
  "win-instellingen-algemeen": tab("Algemeen"), "win-instellingen-verwerking": tab("Verwerking"),
  "win-instellingen-notulen": tab("Notulen"), "win-instellingen-agenda": tab("Agenda"),
  "win-instellingen-obsidian": tab("Obsidian"), "win-instellingen-account": tab("Account"),
  "win-instellingen-geavanceerd": tab("Geavanceerd"),
  "win-support-melding": feedback,
  "win-support-gesprek": async page => { await feedback(page); await page.click("text=Mijn meldingen"); await page.click("text=TV-2"); },
};
(async () => {
  const browser = await chromium.launch();
  for (const { file, url } of require(manifest)) {
    const name = file.replace(".webp", "");
    if (only && only !== name) continue;
    // Fresh context per shot: no localStorage or in-memory fixture state carries over.
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: "nl-NL", colorScheme: "dark", reducedMotion: "reduce" });
    const page = await context.newPage();
    await page.goto(base + url);
    await page.waitForTimeout(1500);
    if (STEPS[name]) { await STEPS[name](page); await page.waitForTimeout(1200); }
    await page.screenshot({ path: `${out}/${name}.png` });
    await context.close();
  }
  await browser.close();
})().catch(error => { console.error(error); process.exit(1); });
JS

python3 - "$WORK" "$MEDIA" <<'PY'
import glob, os, sys
from PIL import Image
for png in sorted(glob.glob(sys.argv[1] + "/*.png")):
    webp = os.path.join(sys.argv[2], os.path.basename(png)[:-4] + ".webp")
    Image.open(png).convert("RGB").save(webp, "WEBP", quality=88, method=6)
    size = os.path.getsize(webp) // 1024
    print(("ok  " if size < 400 else "TE GROOT ") + os.path.basename(webp), size, "KB")
PY
