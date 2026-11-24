# macOS PDF export — 17 November 2026

Branch: `fix/macos-pdf-print-entitlement`, based on current origin/main
`f9ff3e1e69a7cfe60cb08af51c841966b050b7b7`. Separate SSD worktree:
`/Volumes/SSD/Projects/thoughtvault-pdf-print`. Existing worktrees were preserved.

## Change and reproduced failure

Both macOS entitlement files now enable `com.apple.security.print` and retain
`com.apple.security.app-sandbox`. Debug/Release use the ordinary entitlement file;
the AppStore target uses the AppStore file. iOS and Windows are unchanged.

The installed app reproduced the unsupported-printing alert with Cmd-P.
The entitlement-only signed build opened the print panel, but saving produced
three blank pages (1,531 bytes) despite a populated preview. A seven-page sample
was also blank. Retaining the web view longer or setting the print-view frame
alone did not fix this; those experimental changes were discarded.

The shared printer now uses AppKit's window-modal print operation instead of
synchronously calling `run()` inside the main-actor Task. The owning view retains
the WKWebView for asynchronous printing. The result screen delegates to the same
printer, replacing its duplicate synchronous implementation. HTML, CSS, margins,
and A4 sizing are unchanged. This additional change addresses a rendering defect
established by the approved plan's practical test.

## Evidence

Local private evidence (PDFs contain existing meeting content; not committed):
`/Volumes/SSD/Projects/task-evidence/thoughtvault-pdf-print/`.

- `build-modal.log`: **BUILD SUCCEEDED**, signed Debug macOS build.
- `signed-entitlements.plist`: actual app contains printing=true and sandbox=true.
- `codesign --verify --deep --strict`: passed for the final tested app.
- Source plist validation and comparison: only printing permission added.
- Deel → PDF: opens without the unsupported-printing alert; saved short sample.
- Cmd-P: opens without the alert; saved long sample.
- `short-note-fixed.pdf`: 3 A4 pages, 28,785 bytes.
- `long-note.pdf`: 7 A4 pages, 47,250 bytes.
- `verify-pdfs.py` / `pdf-checks.json`: every page has text; all main headings,
  including the final section, are present. The initial all-blank output fails
  these checks. Run with `python3 <evidence-directory>/verify-pdfs.py`.
- Visual inspection of short page 2 and long page 6 confirmed readable tables,
  wrapped cells, margins, and bullet lists (`short-table.png`, `long-table.png`).
  Page counts and text presence checked on every page; not every page visually reviewed.
- Cancelled the print panel, then cancelled Save PDF as `cancel-proof.pdf` and
  cancelled the print panel: no error appeared, and that file does not exist.
- Test app closed; `/Applications/ThoughtVault.app` restored and its process path
  verified. Installed app was not replaced.

Build uses `development.xcconfig` in the evidence directory to select the existing
`ThoughtVault iCloud MAC_APP_DEVELOPMENT 20261116` profile for the app target only.
Automatic signing selected an obsolete profile without iCloud/push; a subsequent
global profile override also affected package bundles. Both failed attempts are
retained in the evidence logs. Neither workaround changes project configuration.

## Limits and storage

No release, push, merge, TestFlight upload, physical paper print, or AppStore
archive was performed. The result-screen call site compiled but was not separately
exercised through a new transcription; the shared helper was exercised through
both notule-detail entry points. The existing 800 ms HTML render delay remains;
slow-loading external content was not covered by these local samples.

Worktree, build products, logs, PDF outputs and render images are on the external
SSD. The default Xcode DerivedData path already points to the SSD. The shared
internal SwiftPM cache had approximately 26 MB of recently touched files; ownership
is shared with other sessions, so these were left intact. No task-owned replaceable
internal artifact was identified for deletion; measured reclaimed space: 0 bytes.
Unrelated earlier artifacts and active/shared queue files were left intact.
