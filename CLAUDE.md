# TranscriptStudio

## Stack
Native macOS/iOS (Swift 6, SwiftUI, `@Observable`) + Windows (Tauri 2, React/TypeScript).
Backend: FastAPI op `https://n8n.prezent.nl/tstudio/api/` — lees docs/API.md bij API-werk.

## Commands
```bash
# macOS build (zonder signing)
xcodebuild -project TranscriptStudio.xcodeproj -scheme TranscriptStudio -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Tests
xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests

# Windows dev
cd windows && npm run tauri dev

# Release via CI (aanbevolen)
scripts/deploy-dev.sh             # dev-v* tag → GitLab CI (macOS + Android + deploy)
scripts/deploy-production.sh      # v* tag → GitLab CI (macOS + Android + deploy)
# Windows MSI: push tag naar GitHub → GitHub Actions (.github/workflows/build-windows.yml)

# Release lokaal (fallback)
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

## Gotchas
- `notifications(named:)` gebruiken, NIET `notifications(for:)` in AuthViewModel
- Sidebar: custom collapsible sidebar (52px icon column ↔ full sidebar), toggle via `Shift+Cmd+S`. Niet meer `columnVisibility` gebruiken (DEC-029)
- Combined recording: `mixAudioFiles()` in RecordingViewModel (element-wise max over PCM)
- Auth header: macOS → `X-User-Token`, Windows → `Authorization: Bearer` (beide geaccepteerd)
- Backend `username` veld is het e-mailadres (niet `email`)
- Versioning: elke commit op `main` bumpt automatisch patch via `.githooks/post-commit`
- Na version bump: `scripts/sync-version.sh` draaien om VERSION naar alle platform configs te syncen
- Downloads: `https://n8n.prezent.nl/tstudio/download/` — lees docs/RELEASE.md voor infra details
- **CI/CD**: GitLab CI (`.gitlab-ci.yml`) voor macOS + Android + deploy (self-hosted Mac runner). GitHub Actions alleen voor Windows MSI builds (`.github/workflows/build-windows.yml`). Zie DEC-055, DEC-056.
- **Multi-instance deployment** — Lees docs/PLAN-MULTI-INSTANCE.md en DEC-033 wanneer relevant

## Credentials & Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `JIRA_URL` | Yes | Jira Cloud instance URL |
| `JIRA_EMAIL` | Yes | Atlassian account email |
| `JIRA_TOKEN` | Yes | Jira API token |
| `N8N_API_KEY` | Yes | n8n API key for workflow access |
| `N8N_URL` | Yes | n8n instance URL |
| `TELEGRAM_BOT_TOKEN` | Yes | Telegram bot token from BotFather |
| `CHAT_ALLOWED_USERS` | No | Comma-separated list of allowed Telegram user IDs |
| `CHAT_MAX_HISTORY` | No | Maximum chat history length |
| `ZAI_API_KEY` | Yes | ZAI API key |
| `ZAI_BASE_URL` | Yes | ZAI API base URL |
| `PRIMARY_PROVIDER` | No | Primary AI provider identifier |

Real values are in `.env` (not committed). See `.env.example` for template.
