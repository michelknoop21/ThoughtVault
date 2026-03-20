#!/bin/bash
# Deploy a production build via GitLab CI
# Usage: ./scripts/deploy-production.sh
#
# Creates a v{version} tag and pushes it to origin (GitLab),
# which triggers the CI pipeline with channel=production.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
TAG="v${VERSION}"

echo "=== Deploy Production Build ==="
echo "  Version: $VERSION"
echo "  Tag:     $TAG"
echo ""

# Check if tag already exists
if git tag -l "$TAG" | grep -q "$TAG"; then
    echo "ERROR: Tag $TAG already exists."
    echo "  This version has already been released."
    echo "  Bump VERSION first, then try again."
    exit 1
fi

# Ensure origin remote is up to date
echo "Pushing latest commits..."
git push origin main

# Create and push tag
echo "Creating tag $TAG..."
git tag "$TAG"
git push origin "$TAG"

echo ""
echo "Production build triggered!"
echo "  Monitor: https://gitlab.prezent.nl/ai-coding/transcript-studio-native/-/pipelines"
echo ""
echo "Once complete, the production build will be available at:"
echo "  https://n8n.prezent.nl/tstudio/download/"
