# ThoughtVault brand visibility — 7 October 2026

Code on Gitea main: `638a8eb` (local startup and Yinga credit), following the website and icon commits.
Windows release source: `3eb688b` on `release/brand-visibility-260`, based on the previously verified Windows recovery branch to retain its existing repairs.

## Verified

- Public website deployed at https://thoughtvault.yinga.ai/; previous Docker image retained.
- Website UI checks pass at 320, 375 and 1440 pixels: result-first layout, AA contrast, 44px navigation targets, Escape focus restoration, profiles, platform table, original logo and loaded images.
- `scripts/check-website.py` passes SEO, protected downloads, noindex and range-download checks.
- Signed macOS 1.0.260 debug build: `BUILD SUCCEEDED`; deep signature verification and sandbox entitlement confirmed. Compiled bundle contains `AppIcon.icns`.
- `swift scripts/check-brand-assets.swift` passes macOS dimensions, opaque iOS artwork and all seven Windows ICO resolutions.
- Local-start regression test passes on the main source and Windows release source; main route-access tests also pass.
- Visible BuildMind footers replaced by Yinga. Bundle IDs and Keychain identities retained.
- Windows release pipeline: https://github.com/michelknoop21/ThoughtVault/actions/runs/37658898025 — succeeded: frontend/native tests, MSI build, upgrade, two launches, saved-note preservation and publication. Live updater feed confirms signed Windows 1.0.260; protected installer range download passes.
- Previous release manifests backed up on the release server under `.rollback-brand-20261007`; previous installers retained.

## Remaining distribution limits

- macOS publication requires a Developer ID Application certificate; this machine has Apple Development and Apple Distribution identities only. No public macOS release uploaded.
- iOS Simulator build fails on the existing macOS-only Sparkle binary package dependency. Changed iOS view files pass Swift parsing; complete iOS compilation and distribution remain unverified.
- Android source is absent from this checkout; no Android build or publication performed.
