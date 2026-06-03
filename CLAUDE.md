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
scripts/deploy-dev.sh             # dev-v* tag → GitLab CI (macOS + Android + Windows + deploy)
scripts/deploy-production.sh      # v* tag → GitLab CI (macOS + Android + Windows + deploy)

# Release lokaal (fallback)
scripts/release.sh                # volledige pipeline
scripts/release.sh --no-upload    # alleen build
scripts/sync-version.sh           # alleen versie sync naar platform configs
```

## Werkprincipes (Karpathy)
IMPORTANT: werk in dit project volgens deze vier principes — boven snelheid.
- **Denk eerst.** Benoem aannames expliciet; twijfel = vragen, niet gokken. Meerdere interpretaties → leg ze voor. Simpeler pad bestaat → zeg het.
- **Simpelste oplossing.** Minimale code die het probleem oplost. Geen speculatieve features, abstracties voor eenmalig gebruik, of "flexibiliteit" die niemand vroeg. 200 regels die 50 kunnen zijn → herschrijf.
- **Chirurgische wijzigingen.** Raak alleen wat moet. Geen ongevraagde refactors/herformattering van omliggende code; volg bestaande stijl. Eigen rommel (orphan imports/vars) opruimen; bestaande dead code benoemen, niet stilletjes verwijderen. Elke gewijzigde regel traceert naar de opdracht.
- **Doelgericht + verifieer.** Vertaal taken naar toetsbare doelen ("voeg X toe" → "test/bewijs dat X werkt"). Claim NOOIT "klaar" zonder bewijs-output (BUILD/ARCHIVE SUCCEEDED, test-output, draaiende app). Kun je het niet verifiëren, zeg dat.

## IMPORTANT: macOS Code Patterns
- Gebruik `@Observable` — NOOIT `ObservableObject/@Published`
- `async/await` overal — geen Combine, geen completion handlers
- ViewModels: `@MainActor class`, Services: `actor`
- UI strings Nederlands via `Localizable.strings`, code/comments in het Engels
- Design tokens: `TS.Spacing`, `TS.Font`, `TS.Radius` (Theme.swift)
- Kleuren: `Color.brandPrimary`, `Color.labelPrimary` (Color+Brand.swift)

## Backend (productie)
FastAPI op AWS EC2 GPU `michelk@3.69.205.209`, container `n8n_transcript_studio` (bind-mount → deploy = file sync + restart, geen rebuild). Lokale repo: `../transcript-studio-backend/`. **Deploy-commando's + server-paden: lees docs/BACKEND.md.**

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
- **Notule titels**: Backend extraheert titels via `_extract_title_from_html()` in `transcription.py`. Sectiekoppen (bijv. "Kernargumenten") worden gefilterd via `_SECTION_WORDS`. Titel-extractie gebeurt in twee codepaths: `/callback/notule` route EN `app.py` queue callback — beide moeten in sync blijven.

## Credentials & Environment Variables
Beheerd door Claude Vault (automatisch geïnjecteerd bij sessiestart). Volledige lijst met required/optional: zie `.env.example`.
