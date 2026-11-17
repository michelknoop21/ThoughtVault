# Woordenboek, voorwaardelijke koppen en PDF-export

Implemented in the isolated SSD worktree `thoughtvault-woordenboek-koppen-pdf`,
branch `feat/woordenboek-koppen-pdf-20261117`, based on fetched `origin/main`
`f9ff3e1e`. The original checkout and other worktrees were preserved.

## Implementation

- Integrated the glossary editor/learned spellings (`89a8a16f`) and automatic
  matching (`ba418b0b`), resolving conflicts in favor of main's newer fallback,
  audit, provider, request logging and usage-meter code. Audio changes from the
  glossary branch were excluded; main's removal of Whisper vocabulary prompts stays.
- Manual corrections update title, notule and transcript through the existing
  save route. SwiftData saves all three together and rolls them back on failure;
  Windows persists one patch and updates both stores before export. Existing
  server records use the existing per-field API calls and retain their errors.
- Fixed variants match in hyphenated compounds; Unicode dash variants share a
  spelling key. Links, code, markup, disabled rules and profile boundaries remain
  protected. No bulk migration of existing notes was added.
- Automatic matching includes two-to-four-letter uppercase abbreviations and
  separated letters. Every occurrence is checked in bounded prompts (at most
  twelve candidates and 1,500 UTF-16 units). The specific occurrence is marked
  in its sentence, including when the same spelling has two meanings in one
  sentence. A failed batch changes none of its occurrences. Only individually
  confirmed occurrences change; learned spellings still need context next time.
- Corrected transcription is persisted before generation, including when the
  generation subsequently fails. Learned spellings are excluded from the
  generator's global correction instructions. New spellings of known terms can
  remain suggestions; existing rejection keys continue to suppress them.
- Updated the shared profile source, both bundled profile files and the existing
  generator. Open/risk/blocker/research sections are explicitly conditional in
  prompts and examples; the condition never becomes an actual output heading.
  The existing audit alone appends `Even nalopen`, only when warnings exist.
- Integrated PDF fix `8726e42d` unchanged: both macOS entitlement files retain
  sandboxing and enable printing; both entry points use the shared async printer.

The existing generator also refreshed the generated local sibling-backend file
`../transcript-studio-backend/src/insanely_fast_whisper_api/app/profile_templates.py`.
That checkout has unrelated active work; no backend commit or deployment was made.

## Verification

Evidence: `/Volumes/SSD/Projects/task-evidence/thoughtvault-woordenboek-koppen-pdf/`.

- `macos-tests-final.log`: **TEST SUCCEEDED**, 137 tests across personal
  corrections, shared automatch fixtures, context suggestions, audit/long audit
  and sync/persistence. Includes a real SwiftData disk close/reopen test.
- `windows-focused.log`: 154 tests passed in nine files. Includes shared fixtures,
  individual meanings across batches, correction dialog title propagation,
  persistence/reload, correction before failed generation, providers and audits.
- `typescript.log`: TypeScript check passed. `windows-build.log`: Vite frontend
  production build passed (existing large-bundle warning). No Windows Rust/MSI
  build was required by these frontend-only changes.
- `tests/test_profile_templates.py`: four tests passed; all seven built-in
  profiles have matching generated files, conditional section rules and no
  model-generated audit heading in their templates. Generator `--check` passes.
- `ios-build-final.log`: **BUILD SUCCEEDED**, generic iOS Simulator target.
- `appstore-build-final.log`: **BUILD SUCCEEDED**, signed macOS AppStore target.
  The actual app has both `com.apple.security.app-sandbox=true` and
  `com.apple.security.print=true`; deep/strict signature verification passed.
- `pdf-recheck.json`: rechecked the original PDF-fix evidence: three and seven
  pages, text on every page, required final headings and absent cancelled file.
  The print helper, result entry point and both entitlements are byte-identical
  to `8726e42d`. The original table/cancellation UI evidence is documented in
  `2026-11-17-macos-pdf-print.md`.
- `git diff --check` passed.

## Acceptance still open

No new interactive PDF session, physical Windows/iPhone acceptance, native MSI
build, per-profile live-model evaluation or TestFlight upload/acceptance was
performed. Profile checks prove prompt/template construction, not compliance by
all models. The only local Ollama model is an embedding model; no new model was
downloaded or paid-provider evaluation started. Uncertain short spellings remain
context-sensitive and may need the user's confirmation through suggestions.

All work, build products and evidence are on the external SSD. The task-owned npm
error log was removed: 2,055 bytes, 4,096 allocated bytes reclaimed. Shared npm and
SwiftPM caches were preserved for concurrent sessions (see `internal-storage-audit.json`
and `cleanup.json`). No other exclusively task-owned internal leftovers were found.
No push, merge, release/version bump or production data change was performed.
