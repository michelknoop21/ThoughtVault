#!/bin/bash
cd "$(dirname "$0")/.."
echo "=== TranscriptStudio: Build Release ==="
echo ""
./scripts/sync-version.sh
echo ""
./scripts/build.sh
echo ""
echo "Druk op een toets om te sluiten..."
read -n 1
