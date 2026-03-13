#!/bin/bash
# Upload build artifact to server and update releases.json manifest
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

DMG_PATH="$BUILD_DIR/$DMG_NAME"
MSI_X64_PATH="$BUILD_DIR/$MSI_X64_NAME"
MSI_ARM64_PATH="$BUILD_DIR/$MSI_ARM64_NAME"
APK_PATH="$BUILD_DIR/$APK_NAME"

# Legacy name (for backwards compatibility detection)
MSI_LEGACY_ARTIFACT="TranscriptStudio_${VERSION}.msi"

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
        TAURI_MSI=$(find "$ROOT_DIR/windows/src-tauri/target/$TARGET_ARCH/release/bundle" -name "*.msi" -type f 2>/dev/null | head -1)
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
if [ -f "$APK_PATH" ]; then FOUND_ANY=true; fi

if [ "$FOUND_ANY" = false ]; then
    echo "ERROR: No artifacts found in $BUILD_DIR"
    echo "Expected: $DMG_NAME and/or $MSI_X64_NAME / $MSI_ARM64_NAME / $APK_NAME"
    echo "Run scripts/build.sh first."
    exit 1
fi

DOWNLOAD_PAGE="$SCRIPT_DIR/download-page.html"
FEATURES_PAGE="$SCRIPT_DIR/features-page.html"

echo "Uploading $BUILD_CHANNEL artifacts to server..."

# Ensure remote directory exists
ssh "$SERVER" "mkdir -p $REMOTE_DIR"

# Upload artifacts
HAS_MACOS=false
HAS_WINDOWS_X64=false
HAS_WINDOWS_ARM64=false
HAS_ANDROID=false

if [ -f "$DMG_PATH" ]; then
    scp "$DMG_PATH" "$SERVER:$REMOTE_DIR/$DMG_NAME"
    echo "  Uploaded: $DMG_NAME"
    HAS_MACOS=true
fi
if [ -f "$MSI_X64_PATH" ]; then
    scp "$MSI_X64_PATH" "$SERVER:$REMOTE_DIR/$MSI_X64_NAME"
    echo "  Uploaded: $MSI_X64_NAME"
    HAS_WINDOWS_X64=true
fi
if [ -f "$MSI_ARM64_PATH" ]; then
    scp "$MSI_ARM64_PATH" "$SERVER:$REMOTE_DIR/$MSI_ARM64_NAME"
    echo "  Uploaded: $MSI_ARM64_NAME"
    HAS_WINDOWS_ARM64=true
fi
if [ -f "$APK_PATH" ]; then
    scp "$APK_PATH" "$SERVER:$REMOTE_DIR/$APK_NAME"
    echo "  Uploaded: $APK_NAME"
    HAS_ANDROID=true
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
# Dev channel writes to dev_* fields, production to existing fields
echo "Updating releases.json ($BUILD_CHANNEL)..."
ssh "$SERVER" "python3 -c \"
import json

manifest_path = '$REMOTE_DIR/releases.json'
try:
    with open(manifest_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

channel = '$BUILD_CHANNEL'

if channel == 'production':
    data['latest_version'] = '$VERSION'

    if '$HAS_MACOS' == 'true':
        data['macos'] = {
            'url': '/tstudio/download/$DMG_NAME',
            'version': '$VERSION',
            'filename': '$DMG_NAME'
        }
    if '$HAS_WINDOWS_X64' == 'true':
        data['windows_x64'] = {
            'url': '/tstudio/download/$MSI_X64_NAME',
            'version': '$VERSION',
            'filename': '$MSI_X64_NAME'
        }
        data['windows'] = {
            'url': '/tstudio/download/$MSI_X64_NAME',
            'version': '$VERSION',
            'filename': '$MSI_X64_NAME'
        }
    if '$HAS_WINDOWS_ARM64' == 'true':
        data['windows_arm64'] = {
            'url': '/tstudio/download/$MSI_ARM64_NAME',
            'version': '$VERSION',
            'filename': '$MSI_ARM64_NAME'
        }
    if '$HAS_ANDROID' == 'true':
        data['android'] = {
            'url': '/tstudio/download/$APK_NAME',
            'version': '$VERSION',
            'filename': '$APK_NAME'
        }
else:
    data['dev_latest_version'] = '$VERSION'

    if '$HAS_MACOS' == 'true':
        data['dev_macos'] = {
            'url': '/tstudio/download/$DMG_NAME',
            'version': '$VERSION',
            'filename': '$DMG_NAME'
        }
    if '$HAS_WINDOWS_X64' == 'true':
        data['dev_windows_x64'] = {
            'url': '/tstudio/download/$MSI_X64_NAME',
            'version': '$VERSION',
            'filename': '$MSI_X64_NAME'
        }
    if '$HAS_WINDOWS_ARM64' == 'true':
        data['dev_windows_arm64'] = {
            'url': '/tstudio/download/$MSI_ARM64_NAME',
            'version': '$VERSION',
            'filename': '$MSI_ARM64_NAME'
        }
    if '$HAS_ANDROID' == 'true':
        data['dev_android'] = {
            'url': '/tstudio/download/$APK_NAME',
            'version': '$VERSION',
            'filename': '$APK_NAME'
        }

with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2)

print('  Updated releases.json (' + channel + ')')
\""

echo ""
echo "Upload complete ($BUILD_CHANNEL)."
if [ -f "$DMG_PATH" ]; then
    echo "  macOS:         https://n8n.prezent.nl/tstudio/download/$DMG_NAME"
fi
if [ -f "$MSI_X64_PATH" ]; then
    echo "  Windows x64:   https://n8n.prezent.nl/tstudio/download/$MSI_X64_NAME"
fi
if [ -f "$MSI_ARM64_PATH" ]; then
    echo "  Windows arm64: https://n8n.prezent.nl/tstudio/download/$MSI_ARM64_NAME"
fi
if [ -f "$APK_PATH" ]; then
    echo "  Android:       https://n8n.prezent.nl/tstudio/download/$APK_NAME"
fi
echo "  Manifest:      https://n8n.prezent.nl/tstudio/download/releases.json"
echo "  Downloads:     https://n8n.prezent.nl/tstudio/download/"
