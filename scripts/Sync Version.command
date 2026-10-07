#!/bin/bash
cd "$(dirname "$0")/.."
echo "=== ThoughtVault: Sync Version ==="
echo ""
./scripts/sync-version.sh
echo ""
echo "Druk op een toets om te sluiten..."
read -n 1
