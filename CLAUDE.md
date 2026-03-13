# TranscriptStudio

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
cd windows && npm run tauri dev

# Release (sync version → build → upload)
scripts/release.sh                # volledige pipeline
scripts/release.sh --no-upload    # alleen build
scripts/sync-version.sh           # alleen versie sync naar platform configs
```

## IMPORTANT: macOS Code Patterns
- Gebruik `@Observable` — NOOIT `ObservableObject/@Published`
- `async/await` overal — geen Combine, geen completion handlers
- ViewModels: `@MainActor class`, Services: `actor`
- UI strings Nederlands via `Localizable.strings`, code/comments in het Engels
- Design tokens: `TS.Spacing`, `TS.Font`, `TS.Radius` (Theme.swift)
- Kleuren: `Color.brandPrimary`, `Color.labelPrimary` (Color+Brand.swift)

## Backend (productie)
- **Server:** AWS EC2 GPU instance `michelk@3.69.205.209`
- **Pad op server:** `/home/michelk/n8n/Transcript Studio/`
- **Lokale repo:** `../transcript-studio-backend/` (zelfde parent directory)
- **Container:** `n8n_transcript_studio` (Docker, nvidia runtime, bind-mount `.:/app`)
- **API URL:** `https://n8n.prezent.nl/tstudio/api/` (nginx reverse proxy)
- **Deployment:** code is bind-mounted, geen rebuild nodig — alleen file sync + restart:
```bash
# Sync alle code naar server
rsync -avz --exclude '__pycache__' --exclude '*.pyc' --exclude 'data/' \
  ../transcript-studio-backend/ michelk@3.69.205.209:"/home/michelk/n8n/Transcript Studio/"

# Of één bestand
scp ../transcript-studio-backend/path/to/file.py \
  michelk@3.69.205.209:"/home/michelk/n8n/Transcript Studio/path/to/file.py"

# Restart container (herlaadt uvicorn met nieuwe code)
ssh michelk@3.69.205.209 "docker restart n8n_transcript_studio"

# Logs bekijken
ssh michelk@3.69.205.209 "docker logs n8n_transcript_studio --tail 50"
```

## Roadmap
- **Multi-instance deployment** — Meerdere klanten bedienen met dezelfde codebase. Zie @docs/PLAN-MULTI-INSTANCE.md en DEC-033.

## Gotchas
- `notifications(named:)` gebruiken, NIET `notifications(for:)` in AuthViewModel
- Sidebar: custom collapsible sidebar (52px icon column ↔ full sidebar), toggle via `Shift+Cmd+S`. Niet meer `columnVisibility` gebruiken (DEC-029)
- Combined recording: `mixAudioFiles()` in RecordingViewModel (element-wise max over PCM)
- Auth header: macOS → `X-User-Token`, Windows → `Authorization: Bearer` (beide geaccepteerd)
- Backend `username` veld is het e-mailadres (niet `email`)
- Versioning: elke commit op `main` bumpt automatisch patch via `.githooks/post-commit`
- Na version bump: `scripts/sync-version.sh` draaien om VERSION naar alle platform configs te syncen
- Downloads: `https://n8n.prezent.nl/tstudio/download/` — zie @docs/RELEASE.md voor infra details
