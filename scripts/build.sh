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

    # Check for Windows MSIs in build/ for upcoming upload
    FOUND_MSI=false
    for ARCH in x64 arm64; do
        MSI_NAME="TranscriptStudio_${VERSION}_${ARCH}.msi"
        MSI_PATH="$BUILD_DIR/$MSI_NAME"
        if [ -f "$MSI_PATH" ]; then
            echo "Windows MSI ($ARCH) ready: $MSI_PATH ($(du -h "$MSI_PATH" | cut -f1))"
            FOUND_MSI=true
        fi
    done
    # Also check Tauri output directory in case target/ was synced from Windows
    if [ "$FOUND_MSI" = false ]; then
        for TARGET_ARCH in x86_64-pc-windows-msvc aarch64-pc-windows-msvc; do
            if [ "$TARGET_ARCH" = "x86_64-pc-windows-msvc" ]; then ARCH_LABEL="x64"; else ARCH_LABEL="arm64"; fi
            TAURI_MSI=$(find "$ROOT_DIR/transcript-studio-windows/src-tauri/target/$TARGET_ARCH/release/bundle" -name "*.msi" -type f 2>/dev/null | head -1)
            if [ -n "$TAURI_MSI" ]; then
                MSI_NAME="TranscriptStudio_${VERSION}_${ARCH_LABEL}.msi"
                cp "$TAURI_MSI" "$BUILD_DIR/$MSI_NAME"
                echo "Windows MSI ($ARCH_LABEL) found in Tauri output, copied as: $MSI_NAME"
                FOUND_MSI=true
            fi
        done
    fi
    if [ "$FOUND_MSI" = false ]; then
        echo ""
        echo "NOTE: No Windows MSI found."
        echo "  Place them in build/ as: TranscriptStudio_${VERSION}_x64.msi / TranscriptStudio_${VERSION}_arm64.msi"
    fi

else
    # Windows (or Linux): Tauri build → MSI
    WINDOWS_DIR="$ROOT_DIR/transcript-studio-windows"

    if [ ! -d "$WINDOWS_DIR" ]; then
        echo "ERROR: transcript-studio-windows directory not found"
        exit 1
    fi

    cd "$WINDOWS_DIR"

    # Build targets: --x64-only or --arm64-only for single arch, default builds both
    TARGETS=()
    if [ "$1" = "--x64-only" ]; then
        TARGETS=("x86_64-pc-windows-msvc")
    elif [ "$1" = "--arm64-only" ]; then
        TARGETS=("aarch64-pc-windows-msvc")
    else
        TARGETS=("x86_64-pc-windows-msvc" "aarch64-pc-windows-msvc")
    fi

    for TARGET_ARCH in "${TARGETS[@]}"; do
        if [ "$TARGET_ARCH" = "x86_64-pc-windows-msvc" ]; then
            ARCH_LABEL="x64"
            MSI_NAME="TranscriptStudio_${VERSION}_x64.msi"
        else
            ARCH_LABEL="arm64"
            MSI_NAME="TranscriptStudio_${VERSION}_arm64.msi"
        fi

        echo ""
        echo "Building for $ARCH_LABEL ($TARGET_ARCH)..."
        npm run tauri build -- --target "$TARGET_ARCH"

        # Find the MSI in the Tauri output
        MSI_SOURCE=$(find src-tauri/target/"$TARGET_ARCH"/release/bundle -name "*.msi" -type f 2>/dev/null | head -1)
        if [ -z "$MSI_SOURCE" ]; then
            MSI_SOURCE=$(find src-tauri/target/release/bundle -name "*.msi" -type f 2>/dev/null | head -1)
        fi
        if [ -z "$MSI_SOURCE" ]; then
            echo "ERROR: MSI not found for $ARCH_LABEL"
            exit 1
        fi

        cp "$MSI_SOURCE" "$BUILD_DIR/$MSI_NAME"
        echo "Built: $BUILD_DIR/$MSI_NAME ($(du -h "$BUILD_DIR/$MSI_NAME" | cut -f1))"
    done

    echo ""
    echo "Windows build complete!"
    ls -lh "$BUILD_DIR"/TranscriptStudio_${VERSION}_*.msi 2>/dev/null
fi
