#!/bin/bash
# Upload build artifact to server and update releases.json manifest
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
BUILD_DIR="$ROOT_DIR/build"

SERVER="michelk@3.69.205.209"
REMOTE_DIR="/home/michelk/tstudio-releases"

DMG_ARTIFACT="TranscriptStudio-${VERSION}.dmg"
MSI_X64_ARTIFACT="TranscriptStudio_${VERSION}_x64.msi"
MSI_ARM64_ARTIFACT="TranscriptStudio_${VERSION}_arm64.msi"
# Legacy name (for backwards compatibility detection)
MSI_LEGACY_ARTIFACT="TranscriptStudio_${VERSION}.msi"

DMG_PATH="$BUILD_DIR/$DMG_ARTIFACT"
MSI_X64_PATH="$BUILD_DIR/$MSI_X64_ARTIFACT"
MSI_ARM64_PATH="$BUILD_DIR/$MSI_ARM64_ARTIFACT"

mkdir -p "$BUILD_DIR"

# Auto-find MSIs from Tauri build output if not already in build/
for TARGET_ARCH in x86_64-pc-windows-msvc aarch64-pc-windows-msvc; do
    if [ "$TARGET_ARCH" = "x86_64-pc-windows-msvc" ]; then
        MSI_CHECK="$MSI_X64_PATH"
        ARCH_LABEL="x64"
    else
        MSI_CHECK="$MSI_ARM64_PATH"
        ARCH_LABEL="arm64"
    fi
    if [ ! -f "$MSI_CHECK" ]; then
        TAURI_MSI=$(find "$ROOT_DIR/transcript-studio-windows/src-tauri/target/$TARGET_ARCH/release/bundle" -name "*.msi" -type f 2>/dev/null | head -1)
        if [ -n "$TAURI_MSI" ]; then
            cp "$TAURI_MSI" "$MSI_CHECK"
            echo "  Found $ARCH_LABEL MSI in Tauri output, copied to build/"
        fi
    fi
done

# Backwards compat: rename legacy single MSI to x64
if [ ! -f "$MSI_X64_PATH" ] && [ -f "$BUILD_DIR/$MSI_LEGACY_ARTIFACT" ]; then
    cp "$BUILD_DIR/$MSI_LEGACY_ARTIFACT" "$MSI_X64_PATH"
    echo "  Renamed legacy MSI to x64"
fi

FOUND_ANY=false
if [ -f "$DMG_PATH" ]; then FOUND_ANY=true; fi
if [ -f "$MSI_X64_PATH" ]; then FOUND_ANY=true; fi
if [ -f "$MSI_ARM64_PATH" ]; then FOUND_ANY=true; fi

if [ "$FOUND_ANY" = false ]; then
    echo "ERROR: No artifacts found in $BUILD_DIR"
    echo "Expected: $DMG_ARTIFACT and/or $MSI_X64_ARTIFACT / $MSI_ARM64_ARTIFACT"
    echo "Run scripts/build.sh first."
    exit 1
fi

DOWNLOAD_PAGE="$SCRIPT_DIR/download-page.html"
FEATURES_PAGE="$SCRIPT_DIR/features-page.html"

echo "Uploading artifacts to server..."

# Ensure remote directory exists
ssh "$SERVER" "mkdir -p $REMOTE_DIR"

# Upload artifacts
HAS_MACOS=false
HAS_WINDOWS_X64=false
HAS_WINDOWS_ARM64=false

if [ -f "$DMG_PATH" ]; then
    scp "$DMG_PATH" "$SERVER:$REMOTE_DIR/$DMG_ARTIFACT"
    echo "  Uploaded: $DMG_ARTIFACT"
    HAS_MACOS=true
fi
if [ -f "$MSI_X64_PATH" ]; then
    scp "$MSI_X64_PATH" "$SERVER:$REMOTE_DIR/$MSI_X64_ARTIFACT"
    echo "  Uploaded: $MSI_X64_ARTIFACT"
    HAS_WINDOWS_X64=true
fi
if [ -f "$MSI_ARM64_PATH" ]; then
    scp "$MSI_ARM64_PATH" "$SERVER:$REMOTE_DIR/$MSI_ARM64_ARTIFACT"
    echo "  Uploaded: $MSI_ARM64_ARTIFACT"
    HAS_WINDOWS_ARM64=true
fi

# Upload website pages
if [ -f "$DOWNLOAD_PAGE" ]; then
    scp "$DOWNLOAD_PAGE" "$SERVER:$REMOTE_DIR/index.html"
    echo "  Updated: download page"
fi
if [ -f "$FEATURES_PAGE" ]; then
    scp "$FEATURES_PAGE" "$SERVER:$REMOTE_DIR/features.html"
    echo "  Updated: features page"
fi

# Upload screenshots
SCREENSHOTS_DIR="$SCRIPT_DIR/screenshots"
if [ -d "$SCREENSHOTS_DIR" ]; then
    ssh "$SERVER" "mkdir -p $REMOTE_DIR/screenshots"
    scp "$SCREENSHOTS_DIR"/*.png "$SERVER:$REMOTE_DIR/screenshots/"
    echo "  Updated: screenshots"
fi

# Update releases.json manifest on server
echo "Updating releases.json..."
ssh "$SERVER" "python3 -c \"
import json

manifest_path = '$REMOTE_DIR/releases.json'
try:
    with open(manifest_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

data['latest_version'] = '$VERSION'

if $HAS_MACOS:
    data['macos'] = {
        'url': '/tstudio/download/$DMG_ARTIFACT',
        'version': '$VERSION',
        'filename': '$DMG_ARTIFACT'
    }
if $HAS_WINDOWS_X64:
    data['windows_x64'] = {
        'url': '/tstudio/download/$MSI_X64_ARTIFACT',
        'version': '$VERSION',
        'filename': '$MSI_X64_ARTIFACT'
    }
    # Keep 'windows' pointing to x64 as the default
    data['windows'] = {
        'url': '/tstudio/download/$MSI_X64_ARTIFACT',
        'version': '$VERSION',
        'filename': '$MSI_X64_ARTIFACT'
    }
if $HAS_WINDOWS_ARM64:
    data['windows_arm64'] = {
        'url': '/tstudio/download/$MSI_ARM64_ARTIFACT',
        'version': '$VERSION',
        'filename': '$MSI_ARM64_ARTIFACT'
    }

with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2)

print('  Updated releases.json')
\""

echo ""
echo "Upload complete."
if [ -f "$DMG_PATH" ]; then
    echo "  macOS:         https://n8n.prezent.nl/tstudio/download/$DMG_ARTIFACT"
fi
if [ -f "$MSI_X64_PATH" ]; then
    echo "  Windows x64:   https://n8n.prezent.nl/tstudio/download/$MSI_X64_ARTIFACT"
fi
if [ -f "$MSI_ARM64_PATH" ]; then
    echo "  Windows arm64: https://n8n.prezent.nl/tstudio/download/$MSI_ARM64_ARTIFACT"
fi
echo "  Manifest:      https://n8n.prezent.nl/tstudio/download/releases.json"
echo "  Downloads:     https://n8n.prezent.nl/tstudio/download/"
