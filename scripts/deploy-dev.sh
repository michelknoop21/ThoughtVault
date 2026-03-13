#!/bin/bash
# Deploy a dev build via GitHub Actions
# Usage: ./scripts/deploy-dev.sh
#
# Creates a dev-v{version} tag and pushes it to GitHub,
# which triggers the Release Build workflow with channel=dev.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
TAG="dev-v${VERSION}"

echo "=== Deploy Dev Build ==="
echo "  Version: $VERSION"
echo "  Tag:     $TAG"
echo ""

# Check if tag already exists
if git tag -l "$TAG" | grep -q "$TAG"; then
    echo "Tag $TAG already exists. Deleting and recreating..."
    git tag -d "$TAG"
    git push github ":refs/tags/$TAG" 2>/dev/null || true
fi

# Ensure github remote is up to date
echo "Pushing latest commits to GitHub..."
git push github main

# Create and push tag
echo "Creating tag $TAG..."
git tag "$TAG"
git push github "$TAG"

echo ""
echo "Dev build triggered!"
echo "  Monitor: https://github.com/michelknoop21/transcript-studio-native/actions"
echo ""
echo "Once complete, the dev build will be available at:"
echo "  https://n8n.prezent.nl/tstudio/download/"
