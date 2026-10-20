#!/bin/bash
# Build iOS + macOS archives and upload them to TestFlight (App Store Connect).
# Uses the ASC API key configured in ~/.appstoreconnect/config.json.
#
# Usage: scripts/testflight.sh            # both platforms
#        scripts/testflight.sh ios        # iOS only
#        scripts/testflight.sh macos      # macOS only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

# App Store Connect API key (identifiers, not secrets — the .p8 is the secret).
ASC_CONFIG="$HOME/.appstoreconnect/config.json"
KEY_ID="$(/usr/bin/python3 -c "import json,os;print(json.load(open(os.path.expanduser('$ASC_CONFIG')))['api_key_id'])")"
ISSUER_ID="$(/usr/bin/python3 -c "import json,os;print(json.load(open(os.path.expanduser('$ASC_CONFIG')))['api_issuer_id'])")"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"

AUTH_ARGS=(-allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$KEY_ID"
  -authenticationKeyIssuerID "$ISSUER_ID")

WHAT="${1:-all}"
mkdir -p "$BUILD_DIR"

# Export options are generated in the ignored build directory, so a fresh
# checkout can be uploaded without machine-specific plist files.
write_export_options() {
    local path="$1" destination="$2"
    cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>XL9KN38ATX</string>
</dict></plist>
EOF
}

write_export_options "$BUILD_DIR/ExportOptions-iOS-TestFlight.plist" upload
write_export_options "$BUILD_DIR/ExportOptions-macOS-TestFlight.plist" export

archive_and_ship() {
    local platform="$1" destination="$2" archive="$3" exportopts="$4" altool_type="$5"

    echo "=== [$platform] Archiving $VERSION ==="
    rm -rf "$archive"
    xcodebuild archive \
        -project "$ROOT_DIR/ThoughtVault.xcodeproj" \
        -scheme ThoughtVault \
        -configuration Release \
        -destination "$destination" \
        -archivePath "$archive" \
        "${AUTH_ARGS[@]}"

    local exportdir="$BUILD_DIR/tf-export-$platform"
    rm -rf "$exportdir"
    echo "=== [$platform] Exporting/uploading ==="
    xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist "$exportopts" \
        -exportPath "$exportdir" \
        "${AUTH_ARGS[@]}"

    # macOS ExportOptions uses destination=export → upload the resulting .pkg separately.
    if [ -n "$altool_type" ]; then
        local pkg
        pkg="$(find "$exportdir" -name '*.pkg' | head -1)"
        [ -n "$pkg" ] || { echo "ERROR: no .pkg produced for $platform"; exit 1; }
        echo "=== [$platform] altool upload $pkg ==="
        xcrun altool --upload-app -f "$pkg" -t "$altool_type" \
            --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
    fi
    echo "=== [$platform] done ==="
}

if [ "$WHAT" = "ios" ] || [ "$WHAT" = "all" ]; then
    archive_and_ship ios "generic/platform=iOS" \
        "$BUILD_DIR/ThoughtVault-ios.xcarchive" \
        "$BUILD_DIR/ExportOptions-iOS-TestFlight.plist" ""
fi

if [ "$WHAT" = "macos" ] || [ "$WHAT" = "all" ]; then
    archive_and_ship macos "generic/platform=macOS" \
        "$BUILD_DIR/ThoughtVault-macos.xcarchive" \
        "$BUILD_DIR/ExportOptions-macOS-TestFlight.plist" "macos"
fi

echo "All requested TestFlight uploads submitted for $VERSION."
