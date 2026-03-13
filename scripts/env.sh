#!/bin/bash
# Shared build environment configuration
# Sourced by release.sh, build.sh, upload.sh
#
# BUILD_CHANNEL: "dev" (default) or "production"
# Set via: export BUILD_CHANNEL=production  or  release.sh --production

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
BUILD_DIR="$ROOT_DIR/build"
SERVER="michelk@3.69.205.209"
REMOTE_DIR="/home/michelk/tstudio-releases"

# Default to dev channel
BUILD_CHANNEL="${BUILD_CHANNEL:-dev}"

if [ "$BUILD_CHANNEL" = "production" ]; then
    APP_DISPLAY_NAME="TranscriptStudio"
    BUNDLE_ID_MACOS="nl.prezent.TranscriptStudio"
    BUNDLE_ID_WINDOWS="nl.prezent.transcript-studio"
    BUNDLE_ID_ANDROID="nl.prezent.transcriptstudio"
    TAURI_PRODUCT_NAME="TranscriptStudio"
    DMG_NAME="TranscriptStudio-${VERSION}.dmg"
    MSI_PREFIX="TranscriptStudio"
    APK_NAME="TranscriptStudio-${VERSION}.apk"
else
    APP_DISPLAY_NAME="TranscriptStudio Dev"
    BUNDLE_ID_MACOS="nl.prezent.TranscriptStudio.dev"
    BUNDLE_ID_WINDOWS="nl.prezent.transcript-studio-dev"
    BUNDLE_ID_ANDROID="nl.prezent.transcriptstudio.dev"
    TAURI_PRODUCT_NAME="TranscriptStudio Dev"
    DMG_NAME="TranscriptStudio-Dev-${VERSION}.dmg"
    MSI_PREFIX="TranscriptStudio-Dev"
    APK_NAME="TranscriptStudio-Dev-${VERSION}.apk"
fi

MSI_X64_NAME="${MSI_PREFIX}_${VERSION}_x64.msi"
MSI_ARM64_NAME="${MSI_PREFIX}_${VERSION}_arm64.msi"
