#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:?Usage: document-webkit-smoke.sh /path/on/external/SSD}
mkdir -p "$output"
output=$(cd "$output" && pwd)
app="$output/DocumentCheck.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$output/ModuleCache"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump({'CFBundleIdentifier':'nl.yinga.document-check','CFBundleExecutable':'DocumentCheck','CFBundleName':'DocumentCheck','CFBundlePackageType':'APPL'},f)
PY
cp -R "$root/macos/Resources/Document" "$app/Contents/Resources/"
swiftc -swift-version 6 "$root/macos/Services/DocumentBranding.swift" "$root/macos/Services/DocumentExporter.swift" "$root/macos/Services/ExportFile.swift" "$root/scripts/tests/document-webkit-smoke.swift" -module-cache-path "$output/ModuleCache" -o "$app/Contents/MacOS/DocumentCheck"
"$app/Contents/MacOS/DocumentCheck" "$root/macos/Resources/Document" "$output" "$root/shared/document/test/fixtures.json"
