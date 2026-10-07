#!/bin/bash
# Public releases require stable Developer ID signing, notarization and Sparkle signatures.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
: "${APPLE_NOTARY_PROFILE:?Set APPLE_NOTARY_PROFILE to a stored notarytool Keychain profile}"
security find-identity -v -p codesigning | grep -q 'Developer ID Application:' || { echo 'Developer ID Application certificate is missing'; exit 1; }
mkdir -p "$BUILD_DIR"
xcodebuild archive -project "$ROOT_DIR/ThoughtVault.xcodeproj" -scheme ThoughtVault \
    -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$BUILD_DIR/ThoughtVault.xcarchive" -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
    -allowProvisioningUpdates CODE_SIGN_IDENTITY='Developer ID Application' ENABLE_HARDENED_RUNTIME=YES \
    SKIP_INSTALL=NO PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID_MACOS"
cat > "$BUILD_DIR/export-options.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>method</key><string>developer-id</string><key>teamID</key><string>XL9KN38ATX</string><key>signingStyle</key><string>automatic</string></dict></plist>
PLIST
EXPORT="$BUILD_DIR/export-$BUILD_CHANNEL"
mkdir -p "$EXPORT"
xcodebuild -exportArchive -archivePath "$BUILD_DIR/ThoughtVault.xcarchive" -exportPath "$EXPORT" -exportOptionsPlist "$BUILD_DIR/export-options.plist" -allowProvisioningUpdates
APP="$EXPORT/ThoughtVault.app"
if [ "$APP_DISPLAY_NAME" != ThoughtVault ]; then mv "$APP" "$EXPORT/$APP_DISPLAY_NAME.app"; APP="$EXPORT/$APP_DISPLAY_NAME.app"; fi
codesign --verify --deep --strict "$APP"
# Notarize the app before packaging and staple its ticket so it also works offline.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/notary-$BUILD_CHANNEL.zip"
xcrun notarytool submit "$BUILD_DIR/notary-$BUILD_CHANNEL.zip" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
ln -sfn /Applications "$EXPORT/Applications"
hdiutil create -volname "$APP_DISPLAY_NAME $VERSION" -srcfolder "$EXPORT" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"
xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
xcrun stapler validate "$BUILD_DIR/$DMG_NAME"
SIGN_UPDATE=$(find "$BUILD_DIR/SourcePackages/artifacts" -path '*/bin/sign_update' -type f | head -1)
[ -n "$SIGN_UPDATE" ] || { echo 'Sparkle signing tool not found'; exit 1; }
SIGNATURE=$("$SIGN_UPDATE" --account ThoughtVault -p "$BUILD_DIR/$DMG_NAME")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
python3 - "$BUILD_DIR/$DMG_NAME.sparkle.json" "$SIGNATURE" "$BUILD_NUMBER" <<'PY'
import json,sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({'signature':sys.argv[2], 'build_number':sys.argv[3], 'notarized':True})+'\n')
PY
