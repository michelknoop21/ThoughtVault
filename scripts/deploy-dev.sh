#!/bin/bash
# Dispatch the existing ThoughtVault Windows workflow for a verified GitHub source ref.
set -euo pipefail
REF="${1:-}"
if [ -z "$REF" ]; then
    echo "Usage: bash scripts/deploy-dev.sh <verified-github-ref>" >&2
    echo "See docs/WINDOWS-BUILD-WORKFLOW.md; Gitea origin is not the build runner." >&2
    exit 1
fi
gh workflow run build-windows.yml --repo michelknoop21/ThoughtVault --ref "$REF" -f channel=dev
echo "ThoughtVault Windows build dispatched: https://github.com/michelknoop21/ThoughtVault/actions"
