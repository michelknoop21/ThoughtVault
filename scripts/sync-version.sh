#!/bin/bash
# Sync VERSION file to all platform build configs
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$ROOT_DIR/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: VERSION file not found at $VERSION_FILE"
    exit 1
fi

VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
PATCH=$(echo "$VERSION" | cut -d. -f3)

echo "Syncing version $VERSION to all platform configs..."

# 1. Xcode project.pbxproj — MARKETING_VERSION (all occurrences)
PBXPROJ="$ROOT_DIR/ThoughtVault.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
    sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" "$PBXPROJ"
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $PATCH/" "$PBXPROJ"
    echo "  Updated: project.pbxproj (MARKETING_VERSION=$VERSION, CURRENT_PROJECT_VERSION=$PATCH)"
else
    echo "  Skipped: project.pbxproj (not found)"
fi

# 1b. macOS Info.plist — CFBundleShortVersionString + CFBundleVersion
INFO_PLIST="$ROOT_DIR/macos/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    # PlistBuddy: BSD sed chokes on the {n;s;} multi-command syntax
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $PATCH" "$INFO_PLIST"
    echo "  Updated: macos/Info.plist (CFBundleShortVersionString=$VERSION, CFBundleVersion=$PATCH)"
else
    echo "  Skipped: macos/Info.plist (not found)"
fi

# 2. Tauri tauri.conf.json
TAURI_CONF="$ROOT_DIR/windows/src-tauri/tauri.conf.json"
if [ -f "$TAURI_CONF" ]; then
    sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" "$TAURI_CONF"
    echo "  Updated: tauri.conf.json (version=$VERSION)"
else
    echo "  Skipped: tauri.conf.json (not found)"
fi

# 3. Cargo.toml — first version under [package] only
CARGO_TOML="$ROOT_DIR/windows/src-tauri/Cargo.toml"
if [ -f "$CARGO_TOML" ]; then
    # Use awk to only replace the first version = "..." line (under [package])
    awk -v ver="$VERSION" '
        !done && /^version = "/ {
            print "version = \"" ver "\""
            done = 1
            next
        }
        { print }
    ' "$CARGO_TOML" > "$CARGO_TOML.tmp" && mv "$CARGO_TOML.tmp" "$CARGO_TOML"
    echo "  Updated: Cargo.toml (version=$VERSION)"
else
    echo "  Skipped: Cargo.toml (not found)"
fi

# 4. Android build.gradle.kts — reads from ../VERSION at build time, no file edit needed
ANDROID_BUILD="$ROOT_DIR/transcript-studio-android/app/build.gradle.kts"
if [ -f "$ANDROID_BUILD" ]; then
    echo "  Android: reads VERSION at build time (no edit needed)"
else
    echo "  Skipped: Android build.gradle.kts (not found)"
fi

echo "Version sync complete: $VERSION"
