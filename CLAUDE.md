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
- **CI/CD**: GitLab CI (`.gitlab-ci.yml`) voor macOS + Android + Windows + deploy. Mac runner (shell executor) voor macOS/Android, self-hosted Windows PC (tag `windows`) voor MSI builds. GitHub Actions als fallback voor Windows. Windows runner draait als SYSTEM — `useLocalToolsDir: true` in tauri.conf.json is vereist. Zie DEC-055, DEC-056, DEC-058.
- **Multi-instance deployment** — Lees docs/PLAN-MULTI-INSTANCE.md en DEC-033 wanneer relevant
- **n8n notule flow**: `handleiding` profiel → Claude proxy (`n8n_claude_code:3100`), overige → Ollama. Backend stuurt `profile_id` mee in webhook payload. Zie docs/ARCHITECTURE.md "n8n Notule Generation Flow" (DEC-057)
- **HTMLWebView + eigen CSS**: Als notule-HTML een `<style>` block bevat (handleiding-profiel), dan `extractStyles()` gebruiken om CSS naar `<head>` te verplaatsen. WKWebView past counters/grid/pseudo-elements niet toe vanuit `<style>` in `<body>`.

## Credentials & Environment Variables

Beheerd door Claude Vault (automatisch geïnjecteerd bij sessiestart). Zie `.env.example` voor template.

| Variable | Required | Description |
|----------|----------|-------------|
| `N8N_API_KEY` | Yes | n8n API key for workflow access |
| `N8N_URL` | Yes | n8n instance URL |
| `JIRA_URL` | Yes | Jira Cloud instance URL |
| `JIRA_EMAIL` | Yes | Atlassian account email |
| `JIRA_TOKEN` | Yes | Jira API token |
| `TELEGRAM_BOT_TOKEN` | Yes | Telegram bot token from BotFather |
| `CHAT_ALLOWED_USERS` | No | Comma-separated list of allowed Telegram user IDs |
| `CHAT_MAX_HISTORY` | No | Maximum chat history length |
| `ZAI_API_KEY` | Yes | ZAI API key |
| `ZAI_BASE_URL` | Yes | ZAI API base URL |
| `PRIMARY_PROVIDER` | No | Primary AI provider identifier |
