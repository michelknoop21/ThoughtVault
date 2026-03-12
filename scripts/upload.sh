#!/bin/bash
# Upload build artifact to server and update releases.json manifest
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
BUILD_DIR="$ROOT_DIR/build"

SERVER="michelk@3.69.205.209"
REMOTE_DIR="/home/michelk/tstudio-releases"

OS=$(uname -s)
if [ "$OS" = "Darwin" ]; then
    ARTIFACT="TranscriptStudio-${VERSION}.dmg"
    PLATFORM="macos"
else
    ARTIFACT="TranscriptStudio-${VERSION}.msi"
    PLATFORM="windows"
fi

ARTIFACT_PATH="$BUILD_DIR/$ARTIFACT"

if [ ! -f "$ARTIFACT_PATH" ]; then
    echo "ERROR: Artifact not found at $ARTIFACT_PATH"
    echo "Run scripts/build.sh first."
    exit 1
fi

DOWNLOAD_PAGE="$SCRIPT_DIR/download-page.html"

echo "Uploading $ARTIFACT to server..."

# Ensure remote directory exists
ssh "$SERVER" "mkdir -p $REMOTE_DIR"

# Upload artifact
scp "$ARTIFACT_PATH" "$SERVER:$REMOTE_DIR/$ARTIFACT"
echo "  Uploaded: $ARTIFACT"

# Upload download page
if [ -f "$DOWNLOAD_PAGE" ]; then
    scp "$DOWNLOAD_PAGE" "$SERVER:$REMOTE_DIR/index.html"
    echo "  Updated: download page"
fi

# Update releases.json manifest on server
echo "Updating releases.json..."
ssh "$SERVER" "python3 -c \"
import json, os

manifest_path = '$REMOTE_DIR/releases.json'
try:
    with open(manifest_path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

data['latest_version'] = '$VERSION'
data['$PLATFORM'] = {
    'url': '/tstudio/download/$ARTIFACT',
    'version': '$VERSION',
    'filename': '$ARTIFACT'
}

with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2)

print('  Updated releases.json')
\""

echo ""
echo "Upload complete."
echo "  Artifact:  https://n8n.prezent.nl/tstudio/download/$ARTIFACT"
echo "  Manifest:  https://n8n.prezent.nl/tstudio/download/releases.json"
echo "  Downloads: https://n8n.prezent.nl/tstudio/download/"
