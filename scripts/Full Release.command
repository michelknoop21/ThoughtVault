#!/bin/bash
cd "$(dirname "$0")/.."
echo "=== TranscriptStudio: Full Release ==="
echo ""
./scripts/release.sh
echo ""
echo "Druk op een toets om te sluiten..."
read -n 1
