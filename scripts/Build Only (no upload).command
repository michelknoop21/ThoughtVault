#!/bin/bash
cd "$(dirname "$0")/.."
echo "=== ThoughtVault: Build (no upload) ==="
echo ""
./scripts/release.sh --no-upload
echo ""
echo "Druk op een toets om te sluiten..."
read -n 1
