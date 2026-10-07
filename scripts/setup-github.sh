#!/bin/bash
# Verify the existing ThoughtVault build service; do not create repositories/remotes or upload personal SSH keys.
set -euo pipefail
gh repo view michelknoop21/ThoughtVault --json nameWithOwner,url
gh workflow view build-windows.yml --repo michelknoop21/ThoughtVault
echo "Source: Gitea origin. Build service: michelknoop21/ThoughtVault."
echo "See docs/WINDOWS-BUILD-WORKFLOW.md for a verified source ref and required CI secrets."
