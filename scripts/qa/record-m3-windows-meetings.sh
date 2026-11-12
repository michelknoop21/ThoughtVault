#!/bin/bash
# Records the three fictional M3 meetings with the production Windows generator and updates
# ThoughtVaultTests/Fixtures/M3LiveContentGate.json. At most 9 requests to Ollama Cloud, no retries.
#   vault-exec OLLAMA_CLOUD_API -- <repo>/scripts/qa/record-m3-windows-meetings.sh   (live)
#   <repo>/scripts/qa/record-m3-windows-meetings.sh --dry-run                       (no network, prints hashes)
#   ... --only <meeting> <directory name>   re-records one meeting (3 requests) into its own directory
# The key arrives as VAULT_VALUE and only goes to the Authorization header; evidence never contains it.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE=record
ONLY=""
DIR_NAME="kimi-k26-notuletitels"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=dry-run; shift ;;
    # Re-record one meeting into its own evidence directory: --only <meeting> <directory name>
    --only) ONLY="$2"; DIR_NAME="$3"; shift 3 ;;
    *) echo "Usage: $0 [--dry-run] [--only <meeting> <directory name>]" >&2; exit 2 ;;
  esac
done
if [ "$MODE" = record ] && [ -z "${VAULT_VALUE:-}" ]; then
  echo "VAULT_VALUE is empty: start via vault-exec OLLAMA_CLOUD_API" >&2
  exit 2
fi
if [ ! -d "$ROOT/windows/node_modules" ]; then
  echo "windows/node_modules missing: run npm ci in $ROOT/windows first" >&2
  exit 2
fi
cd "$ROOT/windows"
TV_M3_MODE="$MODE" \
TV_M3_FIXTURE="$ROOT/ThoughtVaultTests/Fixtures/M3LiveContentGate.json" \
TV_M3_DIR="$ROOT/docs/qa/colleague-rollout-2026-11-09/content/$DIR_NAME" \
TV_M3_ONLY="$ONLY" \
  exec npx --no-install vitest run src/services/__tests__/qa-short-quality/m3-meetings.test.ts
