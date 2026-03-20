#!/bin/bash
# Deploy a dev build via GitLab CI
# Usage: ./scripts/deploy-dev.sh
#
# Creates a dev-v{version} tag and pushes it to origin (GitLab),
# which triggers the CI pipeline with channel=dev.
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
    git push origin ":refs/tags/$TAG" 2>/dev/null || true
fi

# Ensure origin remote is up to date
echo "Pushing latest commits..."
git push origin main

# Create and push tag
echo "Creating tag $TAG..."
git tag "$TAG"
git push origin "$TAG"

echo ""
echo "Dev build triggered!"
echo "  Monitor: https://gitlab.prezent.nl/ai-coding/transcript-studio-native/-/pipelines"
echo ""
echo "Once complete, the dev build will be available at:"
echo "  https://n8n.prezent.nl/tstudio/download/"
