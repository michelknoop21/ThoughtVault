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

At the initial implementation checkpoint no new interactive PDF session,
physical Windows/iPhone acceptance, native MSI build, per-profile live-model
evaluation or TestFlight upload/acceptance had been performed. The follow-up
below supersedes the Mac PDF and native Windows status. Profile checks prove prompt/template construction, not compliance by
all models. The only local Ollama model is an embedding model; no new model was
downloaded or paid-provider evaluation started. Uncertain short spellings remain
context-sensitive and may need the user's confirmation through suggestions.

All work, build products and evidence are on the external SSD. The task-owned npm
error log was removed: 2,055 bytes, 4,096 allocated bytes reclaimed. Shared npm and
SwiftPM caches were preserved for concurrent sessions (see `internal-storage-audit.json`
and `cleanup.json`). No other exclusively task-owned internal leftovers were found.
No push, merge, release/version bump or production data change was performed.


## Native Windows/macOS follow-up (17 November)

Requested after the implementation: actual desktop acceptance, beyond the earlier
Mac-hosted frontend checks. Evidence is in the `praktijk/` subdirectory.

- Dalf38 was checked over the existing SSH/central-management route. The candidate
  has its own identifier `nl.prezent.thoughtvault.woordenboek20261117`, QA window
  title and version. No production installation, publication or public source push.
- Full tests executed on Windows: **829 frontend tests passed**, two skipped;
  **69 native Rust tests passed**, three ignored. Native Tauri release build
  succeeded (central build job `243761622e5c4dd1ae29fc7bf937f942`, exit 0).
- The native build exposed an existing root lock-entry version of 1.0.310 against
  Cargo.toml/VERSION 1.0.329. Corrected that entry and extended the existing sync
  script to keep it current. A regression test verifies that dependency versions
  remain unchanged.
- A signed, sandboxed Mac QA app used a separate `.screens` bundle/container and
  fictitious fixture records. The QA-only seed/startup/plist/entitlement changes
  are recorded separately; product logic matches the implementation worktree.
- Real Mac clicks confirmed title, every paragraph, table cells and transcript;
  the unrelated `AE` meaning remained unchanged. A normal app quit/restart showed
  the corrected title and transcript again.
- Real GUI testing exposed a stale Recent title. Local saves now notify the
  sidebar, Home and Notulen list after successful persistence. The unit test
  verifies notifications for all nine save mutations. **137 Mac tests passed**
  after this fix, and the sidebar correction was repeated successfully in the UI.
- New PDFs saved by the Mac app: `mac-short.pdf` (one A4 page) and `mac-long.pdf`
  (thirteen A4 pages). Text is present on every page; all 130 table rows and the
  final marker/warning are present. The short PDF contains corrected AI text.
  The final table page was rendered and visually checked. Cancelling PDF save
  and then cancelling the print panel produced no file or error.
- The QA Mac app was closed. Its six durable fixture-store files were copied to
  the SSD and SHA-256 verified. The exclusively task-owned sandbox container was
  removed: 2,570,652 file bytes / 2,867,200 allocated bytes reclaimed. Shared caches
  and other sessions' temporary test directories were preserved.

Windows GUI acceptance also passed on Dalf38 in Michel's standard interactive
session: final central job `713961fd14924287919a07ec8bff5790`, exit 0, empty stderr.
The real WebView2/Tauri UI corrected title, all paragraphs, table and transcript,
updated the list and sidebar, and retained everything after terminating and
relaunching the QA process. Native file snapshots were compared after both
phases; `AE is een andere afkorting` stayed unchanged. No browser reload or
navigation-guard relaxation was used. The test's fixture settings were loaded by
an actual app process restart. The native identifier was asserted before test
settings were written. Earlier harness setup/readiness errors remain in the
central job history and are not counted as product passes.

All eighteen final Windows UI artifacts were SHA-256/length verified after
transfer to the external SSD; the reopened screen was visually inspected. The
native EXE SHA-256 is
`8ae859d314a15557fb37ca8f6426306110e96c65bde7c6be62dbf5b97ce58317`.
The QA process and debug port were closed. Only its isolated appdata folders were
removed, after comparing the persisted transcript/glossary against the retained
artifacts; see `windows-cleanup.json`. The installed Windows app/data and Mac app
were not replaced. Build/job history and shared build caches were retained.

Live provider/profile evaluation, TestFlight, MSI/update installation and new
audio/hardware acceptance remain separate checks. Five Windows tests were
intentionally skipped/ignored by the existing suites (two frontend, three Rust).
