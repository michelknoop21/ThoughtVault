#!/bin/bash
# Screenshots of the macOS app for the manual (docs/handleiding/media/mac-*.webp).
#
# Usage: scripts/handleiding-shots-mac.sh [--only <name>]
#
# Builds a debug app, gives the copy its own bundle id (com.buildmind.ThoughtVault.screens)
# so it gets its own sandbox container and never opens the real store, then starts it once
# per screen with debug launch arguments and captures its window. The app is started in the
# background (`open -g`); it takes no focus and receives no keystrokes.
# Needs Screen Recording permission for the terminal that runs this.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MEDIA="$ROOT/docs/handleiding/media"
WORK="${TV_SHOTS_WORK:-/Volumes/SSD/mac-caches/tv-handleiding-shots}"
DERIVED="${TV_SHOTS_DERIVED:-/Volumes/SSD/mac-caches/tv-screens-dd}"
BUNDLE_ID="com.buildmind.ThoughtVault.screens"
APP="$WORK/ThoughtVault.app"
ONLY=""
[ "${1:-}" = "--only" ] && ONLY="$2"
mkdir -p "$WORK" "$MEDIA"

cat > "$WORK/screens.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
</dict></plist>
PLIST

if [ "${TV_SHOTS_SKIP_BUILD:-}" != "1" ]; then
    heavy run --label tv-handleiding-mac --run-timeout 3600 -- xcodebuild \
        -project "$ROOT/ThoughtVault.xcodeproj" -scheme ThoughtVault -configuration Debug \
        -destination "platform=macOS" -derivedDataPath "$DERIVED" build \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
        CODE_SIGN_ENTITLEMENTS="$WORK/screens.entitlements" > "$WORK/build.log" 2>&1 \
        || { tail -20 "$WORK/build.log"; exit 1; }
fi

# Copy the build and give the copy its own identity. Info.plist hardcodes the real bundle id.
rm -rf "$APP"
cp -R "$DERIVED/Build/Products/Debug/ThoughtVault.app" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --deep --sign - --entitlements "$WORK/screens.entitlements" "$APP" 2> "$WORK/codesign.log"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$BUNDLE_ID" ] \
    || { echo "ERROR: bundle id is not $BUNDLE_ID, refusing to start the app"; exit 1; }
swiftc -O "$ROOT/scripts/handleiding/winid.swift" -o "$WORK/winid"

stop_app() { pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true; }
trap stop_app EXIT

# shot <name> <launch arguments...>
shot() {
    local name="$1"; shift
    [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && return 0
    stop_app; sleep 1
    open -g -n "$APP" --args -hasCompletedOnboarding YES -TVDebugSeed YES -TVDebugNoNotify YES \
        -TVDebugWindow 1440x900 -localStoreOpenInProgress NO -AppleLanguages "(nl)" -AppleLocale nl_NL "$@"
    sleep "${TV_SHOTS_WAIT:-8}"
    local pid wid
    pid="$(pgrep -f "$APP/Contents/MacOS/" | head -1)"
    [ -n "$pid" ] || { echo "FAIL $name: app did not start"; return 1; }
    wid="$("$WORK/winid" "$pid")" || { echo "FAIL $name: no window"; return 1; }
    screencapture -x -o -l "$wid" "$WORK/$name.png"
    python3 - "$WORK/$name.png" "$MEDIA/$name.webp" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
if im.width > 2200:  # retina capture: 2x is more than the page ever shows
    im = im.resize((im.width // 2 * 3 // 2, im.height // 2 * 3 // 2), Image.LANCZOS)
im.save(sys.argv[2], "WEBP", quality=86, method=6)
PY
    echo "ok $name ($(($(stat -f%z "$MEDIA/$name.webp") / 1024)) KB)"
}

shot mac-home                      -TVDebugTab home
shot mac-opnemen                   -TVDebugTab record
shot mac-taken                     -TVDebugTab tasks
shot mac-notulen                   -TVDebugTab transcripts
shot mac-notule-open               -TVDebugOpen transcript
shot mac-mensen                    -TVDebugTab people
shot mac-persoon-bewerken          -TVDebugTab people -TVDebugOpen person
shot mac-instellingen-algemeen     -TVDebugTab settings -TVDebugSettingsTab algemeen
shot mac-instellingen-verwerking   -TVDebugTab settings -TVDebugSettingsTab verwerking
shot mac-instellingen-woordenlijst -TVDebugTab settings -TVDebugSettingsTab woordenlijst
shot mac-instellingen-notulen      -TVDebugTab settings -TVDebugSettingsTab notulen
shot mac-instellingen-agenda       -TVDebugTab settings -TVDebugSettingsTab agenda
shot mac-instellingen-obsidian     -TVDebugTab settings -TVDebugSettingsTab obsidian
shot mac-instellingen-account      -TVDebugTab settings -TVDebugSettingsTab account
shot mac-instellingen-geavanceerd  -TVDebugTab settings -TVDebugSettingsTab geavanceerd
shot mac-support-melding           -TVDebugOpen support-report
shot mac-support-gesprek           -TVDebugOpen support-thread
shot mac-notule-voorstellen        -TVDebugOpen transcript -TVDebugSuggestions expanded
shot mac-eerste-start-contact      -TVDebugOpen identity

stop_app
rm -f "$WORK"/*.png
echo "Klaar. Verwijder na afloop de container: ~/Library/Containers/$BUNDLE_ID"
