#!/bin/bash
# Build release artifacts for the current platform
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
BUILD_DIR="$ROOT_DIR/build"
OS=$(uname -s)

mkdir -p "$BUILD_DIR"

echo "Building TranscriptStudio $VERSION for $OS..."

if [ "$OS" = "Darwin" ]; then
    # macOS: xcodebuild archive → export .app → create DMG
    ARCHIVE_PATH="$BUILD_DIR/TranscriptStudio.xcarchive"
    APP_NAME="TranscriptStudio"
    DMG_NAME="TranscriptStudio-${VERSION}.dmg"
    DMG_PATH="$BUILD_DIR/$DMG_NAME"
    EXPORT_DIR="$BUILD_DIR/export"

    echo "Step 1/4: Archiving..."
    xcodebuild archive \
        -project "$ROOT_DIR/TranscriptStudio.xcodeproj" \
        -scheme TranscriptStudio \
        -configuration Release \
        -destination "platform=macOS,arch=arm64" \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        SKIP_INSTALL=NO \
        | tail -1

    echo "Step 2/4: Exporting .app..."
    rm -rf "$EXPORT_DIR"
    mkdir -p "$EXPORT_DIR"
    cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/" 2>/dev/null \
        || cp -R "$ARCHIVE_PATH/Products/usr/local/bin/$APP_NAME.app" "$EXPORT_DIR/" 2>/dev/null \
        || { echo "ERROR: Could not find .app in archive. Checking structure..."; find "$ARCHIVE_PATH/Products" -name "*.app" 2>/dev/null; exit 1; }

    echo "Step 3/4: Ad-hoc code signing..."
    codesign --force --deep --sign - "$EXPORT_DIR/$APP_NAME.app"
    echo "  Signed with ad-hoc signature"

    echo "Step 4/4: Creating DMG..."
    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$EXPORT_DIR" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    # Clean up intermediate files
    rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

    echo ""
    echo "Build complete: $DMG_PATH"
    echo "Size: $(du -h "$DMG_PATH" | cut -f1)"

    # Check for Windows MSI in build/ for upcoming upload
    MSI_NAME="TranscriptStudio-${VERSION}.msi"
    MSI_PATH="$BUILD_DIR/$MSI_NAME"
    # Also check Tauri output directory in case target/ was synced from Windows
    if [ ! -f "$MSI_PATH" ]; then
        TAURI_MSI=$(find "$ROOT_DIR/transcript-studio-windows/src-tauri/target/release/bundle" -name "*.msi" -type f 2>/dev/null | head -1)
        if [ -n "$TAURI_MSI" ]; then
            cp "$TAURI_MSI" "$MSI_PATH"
            echo ""
            echo "Windows MSI found in Tauri output, copied as: $MSI_NAME"
        fi
    fi
    if [ -f "$MSI_PATH" ]; then
        echo "Windows MSI ready: $MSI_PATH"
        echo "Size: $(du -h "$MSI_PATH" | cut -f1)"
    else
        echo ""
        echo "NOTE: No Windows MSI found."
        echo "  Place it in build/ as: $MSI_NAME"
    fi

else
    # Windows (or Linux): Tauri build → MSI
    WINDOWS_DIR="$ROOT_DIR/transcript-studio-windows"
    MSI_NAME="TranscriptStudio-${VERSION}.msi"

    if [ ! -d "$WINDOWS_DIR" ]; then
        echo "ERROR: transcript-studio-windows directory not found"
        exit 1
    fi

    cd "$WINDOWS_DIR"
    echo "Running Tauri build..."
    npm run tauri build

    # Find the MSI in the Tauri output
    MSI_SOURCE=$(find src-tauri/target/release/bundle -name "*.msi" -type f 2>/dev/null | head -1)
    if [ -z "$MSI_SOURCE" ]; then
        echo "ERROR: MSI not found in Tauri build output"
        exit 1
    fi

    cp "$MSI_SOURCE" "$BUILD_DIR/$MSI_NAME"
    echo ""
    echo "Build complete: $BUILD_DIR/$MSI_NAME"
    echo "Size: $(du -h "$BUILD_DIR/$MSI_NAME" | cut -f1)"
fi
