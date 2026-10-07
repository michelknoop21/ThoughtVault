#!/bin/bash
cd "$(dirname "$0")/.."
echo "=== ThoughtVault: Full Release ==="
echo ""
./scripts/release.sh
echo ""
echo "Druk op een toets om te sluiten..."
read -n 1
