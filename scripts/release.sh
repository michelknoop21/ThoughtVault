#!/bin/bash
# Full release pipeline: sync version → build → upload
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPLOAD=true

# Parse arguments
for arg in "$@"; do
    case $arg in
        --no-upload) UPLOAD=false ;;
        --production) export BUILD_CHANNEL=production ;;
        *) echo "Unknown option: $arg"; echo "Usage: $0 [--production] [--no-upload]"; exit 1 ;;
    esac
done

source "$SCRIPT_DIR/env.sh"

CHANNEL_LABEL=$(echo "$BUILD_CHANNEL" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
echo "=== TranscriptStudio $CHANNEL_LABEL Release Pipeline v$VERSION ==="
if [ "$BUILD_CHANNEL" = "dev" ]; then
    echo "    Channel: DEV (use --production for production builds)"
fi
echo ""

# Step 1: Sync version
echo "--- Step 1: Sync version ---"
"$SCRIPT_DIR/sync-version.sh"
echo ""

# Step 2: Build
echo "--- Step 2: Build ---"
"$SCRIPT_DIR/build.sh"
echo ""

# Step 3: Upload (optional)
if [ "$UPLOAD" = true ]; then
    echo "--- Step 3: Upload ---"
    "$SCRIPT_DIR/upload.sh"
else
    echo "--- Step 3: Upload (skipped with --no-upload) ---"
fi

echo ""
echo "=== $CHANNEL_LABEL Release $VERSION complete ==="
