#!/bin/bash
# Publish signed artifacts only. Website pages belong to the website project.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
if [ -f "$BUILD_DIR/$MSI_X64_NAME" ] || [ -f "$BUILD_DIR/$MSI_ARM64_NAME" ]; then
    python3 "$SCRIPT_DIR/check-windows-design.py"
fi
STAGING=$(ssh "$SERVER" "mktemp -d $REMOTE_DIR/.upload.XXXXXXXX")
trap 'ssh "$SERVER" "rm -rf $STAGING"' EXIT
FOUND=false
for NAME in "$DMG_NAME" "$MSI_X64_NAME" "$MSI_ARM64_NAME" "$APK_NAME"; do
    if [ -f "$BUILD_DIR/$NAME" ]; then
        scp "$BUILD_DIR/$NAME" "$SERVER:$STAGING/$NAME"
        if [[ "$NAME" == *.msi ]]; then scp "$BUILD_DIR/$NAME.sig" "$SERVER:$STAGING/$NAME.sig"; fi
        if [[ "$NAME" == *.dmg ]]; then scp "$BUILD_DIR/$NAME.sparkle.json" "$SERVER:$STAGING/$NAME.sparkle.json"; fi
        FOUND=true
    fi
done
[ "$FOUND" = true ] || { echo "No artifacts for $VERSION"; exit 1; }
scp "$SCRIPT_DIR/publish-release.py" "$SERVER:$STAGING/publish-release.py"
ssh "$SERVER" "python3 $STAGING/publish-release.py --directory $REMOTE_DIR --staging $STAGING --version $VERSION --channel $BUILD_CHANNEL"
echo "Published: https://thoughtvault.yinga.ai/releases/releases.json"
