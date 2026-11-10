#!/usr/bin/env bash
# Gate M3 of the macOS GO report: the Windows content gate (6 audit cases, 3 fictional
# meetings) against Ollama Cloud, model kimi-k2.6, through the production macOS services.
#
# Start it with the key from the vault; the key is never typed, printed or written:
#   vault-exec OLLAMA_CLOUD_API -- scripts/run-m3-live-gate.sh
# vault-exec only allows fixed --env-var names, so the key arrives as VAULT_VALUE.
#
# xcodebuild strips the TEST_RUNNER_ prefix, so the test reads TV_M3_OLLAMA_KEY.
# Without the key M3LiveContentGateTests skips. At most 21 requests, no retries.
# Evidence (requests without credentials, raw responses, summary.json, xcodebuild.log)
# is copied to docs/qa/macos-go-2026-11-09/M3/<run>.
set -euo pipefail
cd "$(dirname "$0")/.."

export TEST_RUNNER_TV_M3_OLLAMA_KEY="${TEST_RUNNER_TV_M3_OLLAMA_KEY:-${VAULT_VALUE:-}}"
unset VAULT_VALUE

if [ -z "${TEST_RUNNER_TV_M3_OLLAMA_KEY:-}" ]; then
  echo "TEST_RUNNER_TV_M3_OLLAMA_KEY is not set; start this script via vault-exec (see header)." >&2
  exit 2
fi

# True when the file or directory contains the key; printf is a builtin, so the key never lands in argv.
contains_key() {
  grep -rqFf <(printf '%s\n' "$TEST_RUNNER_TV_M3_OLLAMA_KEY") "$1"
}

log="$(mktemp -t m3-live-gate)"
trap 'rm -f "$log"' EXIT

set +e
heavy run --label m3-gate -- xcodebuild test \
  -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS' -allowProvisioningUpdates \
  -only-testing:ThoughtVaultTests/M3LiveContentGateTests 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

if contains_key "$log"; then
  echo "xcodebuild output contains the key; log discarded, nothing copied." >&2
  exit 3
fi

run_dir="$(grep -o 'M3_EVIDENCE_DIR=.*' "$log" | tail -1 | cut -d= -f2- || true)"
# The test host's stdout does not reach xcodebuild, so fall back to the newest evidence
# directory the sandboxed host wrote during this run.
if [ -z "$run_dir" ]; then
  host_tmp="$HOME/Library/Containers/com.buildmind.ThoughtVault/Data/tmp"
  run_dir="$(find "$host_tmp" -maxdepth 1 -type d -name 'M3-*' -newer "$log" 2>/dev/null | sort | tail -1)"
fi
if [ -z "$run_dir" ] || [ ! -d "$run_dir" ]; then
  echo "No M3 evidence directory found (did the live test skip or crash?). xcodebuild exit: $status" >&2
  exit "$(( status == 0 ? 4 : status ))"
fi
if contains_key "$run_dir"; then
  echo "Evidence in $run_dir contains the key; not copied." >&2
  exit 3
fi

dest="docs/qa/macos-go-2026-11-09/M3/$(basename "$run_dir")"
mkdir -p "$dest"
cp -R "$run_dir"/. "$dest"/
cp "$log" "$dest/xcodebuild.log"
echo "M3 evidence copied to $dest"
grep -E 'Test Case .*M3LiveContentGateTests|TEST (SUCCEEDED|FAILED)|Executed [0-9]+ test' "$log" | tail -5 || true
exit "$status"
