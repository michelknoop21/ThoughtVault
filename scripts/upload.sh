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
MSI_ARTIFACT="TranscriptStudio-${VERSION}.msi"
DMG_PATH="$BUILD_DIR/$DMG_ARTIFACT"
MSI_PATH="$BUILD_DIR/$MSI_ARTIFACT"

mkdir -p "$BUILD_DIR"

# Auto-find MSI from Tauri build output if not already in build/
if [ ! -f "$MSI_PATH" ]; then
    TAURI_MSI=$(find "$ROOT_DIR/transcript-studio-windows/src-tauri/target/release/bundle" -name "*.msi" -type f 2>/dev/null | head -1)
    if [ -n "$TAURI_MSI" ]; then
        cp "$TAURI_MSI" "$MSI_PATH"
        echo "  Found MSI in Tauri output, copied to build/"
    fi
fi

# Also check the server for an existing MSI if we only have a DMG locally
if [ ! -f "$MSI_PATH" ] && [ -f "$DMG_PATH" ]; then
    echo "  No local MSI found, checking server for existing Windows release..."
    REMOTE_MSI_VERSION=$(ssh "$SERVER" "python3 -c \"
import json
try:
    with open('$REMOTE_DIR/releases.json') as f:
        data = json.load(f)
    print(data.get('windows', {}).get('version', ''))
except:
    print('')
\"" 2>/dev/null || true)
    if [ -n "$REMOTE_MSI_VERSION" ]; then
        echo "  Server has Windows MSI v${REMOTE_MSI_VERSION} (will be preserved in manifest)"
    fi
fi

FOUND_ANY=false
if [ -f "$DMG_PATH" ]; then FOUND_ANY=true; fi
if [ -f "$MSI_PATH" ]; then FOUND_ANY=true; fi

if [ "$FOUND_ANY" = false ]; then
    echo "ERROR: No artifacts found in $BUILD_DIR"
    echo "Expected: $DMG_ARTIFACT and/or $MSI_ARTIFACT"
    echo "Run scripts/build.sh first."
    exit 1
fi

DOWNLOAD_PAGE="$SCRIPT_DIR/download-page.html"
FEATURES_PAGE="$SCRIPT_DIR/features-page.html"

echo "Uploading artifacts to server..."

# Ensure remote directory exists
ssh "$SERVER" "mkdir -p $REMOTE_DIR"

# Upload artifacts
MANIFEST_UPDATES=""
if [ -f "$DMG_PATH" ]; then
    scp "$DMG_PATH" "$SERVER:$REMOTE_DIR/$DMG_ARTIFACT"
    echo "  Uploaded: $DMG_ARTIFACT"
    MANIFEST_UPDATES="macos"
fi
if [ -f "$MSI_PATH" ]; then
    scp "$MSI_PATH" "$SERVER:$REMOTE_DIR/$MSI_ARTIFACT"
    echo "  Uploaded: $MSI_ARTIFACT"
    if [ -n "$MANIFEST_UPDATES" ]; then
        MANIFEST_UPDATES="$MANIFEST_UPDATES,windows"
    else
        MANIFEST_UPDATES="windows"
    fi
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

platforms = '$MANIFEST_UPDATES'.split(',')
if 'macos' in platforms:
    data['macos'] = {
        'url': '/tstudio/download/$DMG_ARTIFACT',
        'version': '$VERSION',
        'filename': '$DMG_ARTIFACT'
    }
if 'windows' in platforms:
    data['windows'] = {
        'url': '/tstudio/download/$MSI_ARTIFACT',
        'version': '$VERSION',
        'filename': '$MSI_ARTIFACT'
    }
# Preserve existing platform entries that weren't updated

with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2)

print('  Updated releases.json')
\""

echo ""
echo "Upload complete."
if [ -f "$DMG_PATH" ]; then
    echo "  macOS:     https://n8n.prezent.nl/tstudio/download/$DMG_ARTIFACT"
fi
if [ -f "$MSI_PATH" ]; then
    echo "  Windows:   https://n8n.prezent.nl/tstudio/download/$MSI_ARTIFACT"
fi
echo "  Manifest:  https://n8n.prezent.nl/tstudio/download/releases.json"
echo "  Downloads: https://n8n.prezent.nl/tstudio/download/"
