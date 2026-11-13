#!/bin/bash
# Screenshots of the iPhone app for the manual (docs/handleiding/media/ios-*.webp).
#
# Usage: scripts/handleiding-shots-ios.sh [--only <name>]
#
# Builds the app for the simulator, then starts it once per screen with debug launch
# arguments (taps are not available on this Xcode) and takes a simulator screenshot.
# The simulator has its own data, so the sample data never touches a real store.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MEDIA="$ROOT/docs/handleiding/media"
DERIVED="${TV_SHOTS_DERIVED_IOS:-/Volumes/SSD/mac-caches/tv-screens-dd-ios}"
DEVICE_NAME="TV Handleiding iPhone"
BUNDLE_ID="com.buildmind.ThoughtVault"
ONLY=""
[ "${1:-}" = "--only" ] && ONLY="$2"

if [ "${TV_SHOTS_IN_SIM:-}" != "1" ]; then
    UDID="$(xcrun simctl list devices available | sed -n "s/.*$DEVICE_NAME (\([0-9A-F-]*\)).*/\1/p" | head -1)"
    if [ -z "$UDID" ]; then
        RUNTIME="$(xcrun simctl list runtimes | sed -n 's/.*\(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\).*/\1/p' | tail -1)"
        UDID="$(xcrun simctl create "$DEVICE_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$RUNTIME")"
    fi
    if [ "${TV_SHOTS_SKIP_BUILD:-}" != "1" ]; then
        heavy run --label tv-handleiding-ios --run-timeout 3600 -- xcodebuild \
            -project "$ROOT/ThoughtVault.xcodeproj" -scheme ThoughtVault -configuration Debug \
            -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" build \
            CODE_SIGNING_ALLOWED=NO > "$DERIVED.log" 2>&1 || { tail -20 "$DERIVED.log"; exit 1; }
    fi
    # met-simulator boots the device and shuts it down again afterwards.
    TV_SHOTS_IN_SIM=1 TV_SHOTS_UDID="$UDID" exec met-simulator "$UDID" -- "$0" "$@"
fi

UDID="$TV_SHOTS_UDID"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/ThoughtVault.app"
TMP="$(mktemp -d)"
trap 'xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
for service in microphone speech-recognition calendar; do
    xcrun simctl privacy "$UDID" grant "$service" "$BUNDLE_ID" 2>/dev/null || true
done

# shot <name> <launch arguments...>
shot() {
    local name="$1"; shift
    [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && return 0
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    sleep 1
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -hasCompletedOnboarding YES -TVDebugSeed YES -TVDebugNoNotify YES \
        -localStoreOpenInProgress NO -AppleLanguages "(nl)" -AppleLocale nl_NL "$@" >/dev/null
    sleep "${TV_SHOTS_WAIT:-7}"
    xcrun simctl io "$UDID" screenshot "$TMP/$name.png" >/dev/null 2>&1
    python3 - "$TMP/$name.png" "$MEDIA/$name.webp" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
im = im.resize((im.width * 2 // 3, im.height * 2 // 3), Image.LANCZOS)  # 3x capture to 2x
im.save(sys.argv[2], "WEBP", quality=86, method=6)
PY
    echo "ok $name ($(($(stat -f%z "$MEDIA/$name.webp") / 1024)) KB)"
}

shot ios-home               -TVDebugTab home
shot ios-opnemen            -TVDebugTab record
shot ios-taken              -TVDebugTab tasks
shot ios-notulen            -TVDebugTab transcripts
shot ios-instellingen       -TVDebugTab settings
shot ios-onboarding-microfoon -hasCompletedOnboarding NO -TVDebugOpen onboarding-mic
echo "Klaar."
