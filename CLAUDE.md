# TranscriptStudioApp

## Stack
Native macOS/iOS (Swift 6, SwiftUI, `@Observable`) + Windows (Tauri 2, React/TypeScript).
Backend: FastAPI op `https://n8n.prezent.nl/tstudio/api/` — zie @docs/API.md.
Projectstructuur: @README.md

## Commands
```bash
# macOS build (zonder signing)
xcodebuild -project TranscriptStudio.xcodeproj -scheme TranscriptStudio -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Tests
xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests

# Windows dev
cd transcript-studio-windows && npm run tauri dev
```

## IMPORTANT: macOS Code Patterns
- Gebruik `@Observable` — NOOIT `ObservableObject/@Published`
- `async/await` overal — geen Combine, geen completion handlers
- ViewModels: `@MainActor class`, Services: `actor`
- UI strings Nederlands via `Localizable.strings`, code/comments in het Engels
- Design tokens: `TS.Spacing`, `TS.Font`, `TS.Radius` (Theme.swift)
- Kleuren: `Color.brandPrimary`, `Color.labelPrimary` (Color+Brand.swift)

## Gotchas
- `notifications(named:)` gebruiken, NIET `notifications(for:)` in AuthViewModel
- Sidebar toggle: `.toolbar(removing: .sidebarToggle)` op ELKE individuele NavigationStack tab
- Combined recording: `mixAudioFiles()` in RecordingViewModel (element-wise max over PCM)
- Auth header: macOS → `X-User-Token`, Windows → `Authorization: Bearer` (beide geaccepteerd)
- Backend `username` veld is het e-mailadres (niet `email`)
- Versioning: elke commit op `main` bumpt automatisch patch via `.githooks/post-commit`
- Na version bump: `scripts/sync-version.sh` draaien om VERSION naar alle platform configs te syncen

## Build & Release Pipeline
```bash
# Sync VERSION naar Xcode pbxproj, tauri.conf.json, Cargo.toml
scripts/sync-version.sh

# Build release artifact (DMG op macOS, MSI op Windows)
scripts/build.sh

# Upload artifact naar server + update releases.json manifest
scripts/upload.sh

# Volledige pipeline (sync → build → upload)
scripts/release.sh
scripts/release.sh --no-upload   # zonder upload
```

Artifacts worden gehost op `https://n8n.prezent.nl/tstudio/download/`
Manifest: `https://n8n.prezent.nl/tstudio/download/releases.json`

### Server-side infra
- Nginx (`n8n_nginx` container) serveert static files via `/tstudio/download/` → `/srv/tstudio-releases/`
- Host directory: `/home/michelk/tstudio-releases/` (volume mount in n8n-prezent docker-compose)
- Config: `/home/michelk/n8n-prezent/nginx/default.conf`
