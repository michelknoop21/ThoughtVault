#!/bin/bash
# Build release artifacts for the current platform
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

OS=$(uname -s)

mkdir -p "$BUILD_DIR"

echo "Building $APP_DISPLAY_NAME $VERSION ($BUILD_CHANNEL) for $OS..."

if [ "$OS" = "Darwin" ]; then
    exec "$SCRIPT_DIR/build-macos-release.sh"

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
        cp "$MSI_SOURCE.sig" "$BUILD_DIR/$MSI_DEST.sig"
        echo "Built: $BUILD_DIR/$MSI_DEST ($(du -h "$BUILD_DIR/$MSI_DEST" | cut -f1))"
    done

    echo ""
    echo "Windows build complete!"
    ls -lh "$BUILD_DIR"/${MSI_PREFIX}_${VERSION}_*.msi 2>/dev/null
fi
