#!/bin/bash
# Build release artifacts for the current platform
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

OS=$(uname -s)

mkdir -p "$BUILD_DIR"

echo "Building $APP_DISPLAY_NAME $VERSION ($BUILD_CHANNEL) for $OS..."

if [ "$OS" = "Darwin" ]; then
    # macOS: xcodebuild archive → export .app → create DMG
    ARCHIVE_PATH="$BUILD_DIR/TranscriptStudio.xcarchive"
    DMG_PATH="$BUILD_DIR/$DMG_NAME"
    EXPORT_DIR="$BUILD_DIR/export"

    # Determine app name from bundle — xcodebuild uses PRODUCT_NAME for the .app filename
    if [ "$BUILD_CHANNEL" = "production" ]; then
        APP_NAME="TranscriptStudio"
    else
        APP_NAME="TranscriptStudio Dev"
    fi

    echo "Step 1/4: Archiving..."
    xcodebuild archive \
        -project "$ROOT_DIR/TranscriptStudio.xcodeproj" \
        -scheme TranscriptStudio \
        -configuration Release \
        -destination "platform=macOS,arch=arm64" \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGNING_ALLOWED=NO \
        SKIP_INSTALL=NO \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID_MACOS" \
        PRODUCT_NAME="$APP_DISPLAY_NAME" \
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

    echo "Step 4/4: Creating styled DMG..."
    rm -f "$DMG_PATH"

    # Generate background image
    python3 "$SCRIPT_DIR/create-dmg-background.py"
    BG_IMG="$SCRIPT_DIR/dmg-background.png"

    # Add Applications symlink
    ln -sf /Applications "$EXPORT_DIR/Applications"

    # Create writable DMG
    DMG_TEMP="$BUILD_DIR/tmp_rw.dmg"
    rm -f "$DMG_TEMP"
    hdiutil create \
        -volname "$APP_DISPLAY_NAME $VERSION" \
        -srcfolder "$EXPORT_DIR" \
        -ov \
        -format UDRW \
        -fs HFS+ \
        "$DMG_TEMP"

    # Mount writable DMG
    MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" | awk '/Apple_HFS/ {for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
    echo "  Mounted at: $MOUNT_DIR"

    # Copy background image into DMG (hidden folder)
    mkdir -p "$MOUNT_DIR/.background"
    cp "$BG_IMG" "$MOUNT_DIR/.background/background.png"

    # Use AppleScript to set Finder window appearance
    VOLNAME="$APP_DISPLAY_NAME $VERSION"
    osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 500}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.png"
        -- Position app icon on the left, Applications on the right
        set position of item "$APP_NAME.app" of container window to {165, 200}
        set position of item "Applications" of container window to {495, 200}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

    # Unmount
    sync
    hdiutil detach "$MOUNT_DIR" -quiet

    # Convert to compressed read-only DMG
    hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
    rm -f "$DMG_TEMP"

    # Clean up intermediate files
    rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

    echo ""
    echo "Build complete: $DMG_PATH"
    echo "Size: $(du -h "$DMG_PATH" | cut -f1)"

    # Check for Windows MSIs in build/ for upcoming upload
    FOUND_MSI=false
    for ARCH in x64 arm64; do
        MSI_CHECK="${MSI_PREFIX}_${VERSION}_${ARCH}.msi"
        MSI_PATH="$BUILD_DIR/$MSI_CHECK"
        if [ -f "$MSI_PATH" ]; then
            echo "Windows MSI ($ARCH) ready: $MSI_PATH ($(du -h "$MSI_PATH" | cut -f1))"
            FOUND_MSI=true
        fi
    done
    # Also check Tauri output directory in case target/ was synced from Windows
    if [ "$FOUND_MSI" = false ]; then
        for TARGET_ARCH in x86_64-pc-windows-msvc aarch64-pc-windows-msvc; do
            if [ "$TARGET_ARCH" = "x86_64-pc-windows-msvc" ]; then ARCH_LABEL="x64"; else ARCH_LABEL="arm64"; fi
            TAURI_MSI=$(find "$ROOT_DIR/windows/src-tauri/target/$TARGET_ARCH/release/bundle" -name "*.msi" -type f 2>/dev/null | head -1)
            if [ -n "$TAURI_MSI" ]; then
                MSI_DEST="${MSI_PREFIX}_${VERSION}_${ARCH_LABEL}.msi"
                cp "$TAURI_MSI" "$BUILD_DIR/$MSI_DEST"
                echo "Windows MSI ($ARCH_LABEL) found in Tauri output, copied as: $MSI_DEST"
                FOUND_MSI=true
            fi
        done
    fi
    if [ "$FOUND_MSI" = false ]; then
        echo ""
        echo "NOTE: No Windows MSI found."
        echo "  Place them in build/ as: ${MSI_PREFIX}_${VERSION}_x64.msi / ${MSI_PREFIX}_${VERSION}_arm64.msi"
    fi

else
    # Windows (or Linux): Tauri build → MSI
    WINDOWS_DIR="$ROOT_DIR/windows"

    if [ ! -d "$WINDOWS_DIR" ]; then
        echo "ERROR: windows directory not found"
        exit 1
    fi

    cd "$WINDOWS_DIR"

    # Build-time config override for Tauri (bundle ID + product name)
    export TAURI_CONFIG="{\"identifier\":\"$BUNDLE_ID_WINDOWS\",\"productName\":\"$TAURI_PRODUCT_NAME\"}"

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
            MSI_DEST="$MSI_X64_NAME"
        else
            ARCH_LABEL="arm64"
            MSI_DEST="$MSI_ARM64_NAME"
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

        cp "$MSI_SOURCE" "$BUILD_DIR/$MSI_DEST"
        echo "Built: $BUILD_DIR/$MSI_DEST ($(du -h "$BUILD_DIR/$MSI_DEST" | cut -f1))"
    done

    echo ""
    echo "Windows build complete!"
    ls -lh "$BUILD_DIR"/${MSI_PREFIX}_${VERSION}_*.msi 2>/dev/null
fi
