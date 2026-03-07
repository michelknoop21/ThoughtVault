#!/bin/bash
# Full release pipeline: sync version → build → upload
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPLOAD=true

# Parse arguments
for arg in "$@"; do
    case $arg in
        --no-upload) UPLOAD=false ;;
        *) echo "Unknown option: $arg"; echo "Usage: $0 [--no-upload]"; exit 1 ;;
    esac
done

VERSION=$(cat "$(dirname "$SCRIPT_DIR")/VERSION" | tr -d '[:space:]')
echo "=== TranscriptStudio Release Pipeline v$VERSION ==="
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
echo "=== Release $VERSION complete ==="
