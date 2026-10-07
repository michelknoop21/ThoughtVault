#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/macos" "$FIXTURE/ThoughtVault.xcodeproj"
cp "$ROOT/scripts/sync-version.sh" "$FIXTURE/scripts/"
cp "$ROOT/macos/Info.plist" "$FIXTURE/macos/"
cp "$ROOT/ThoughtVault.xcodeproj/project.pbxproj" "$FIXTURE/ThoughtVault.xcodeproj/"
BEFORE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$FIXTURE/macos/Info.plist")
printf '2.0.0\n' > "$FIXTURE/VERSION"
bash "$FIXTURE/scripts/sync-version.sh" > /dev/null
AFTER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$FIXTURE/macos/Info.plist")
[ "$AFTER" -eq "$((BEFORE + 1))" ]
bash "$FIXTURE/scripts/sync-version.sh" > /dev/null
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$FIXTURE/macos/Info.plist")" -eq "$AFTER" ]
echo 'Monotonic Mac build number and retry check passed'
