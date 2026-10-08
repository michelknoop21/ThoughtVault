# ThoughtVault

Windows MSI builds draaien in GitHub Actions op een expliciete bronref. Lees
`docs/WINDOWS-BUILD-WORKFLOW.md` voor tests, installatie en publicatie.
De actuele Windows-bron staat op Gitea; gebruik geen oudere GitHub-defaultbranch.

## Stack
Native macOS/iOS (Swift 6, SwiftUI, `@Observable`) + Windows (Tauri 2, React/TypeScript).
Windows: lokale opslag/transcriptie, lokale of rechtstreeks geconfigureerde cloud-AI.
Geen ThoughtVault-account/backend nodig voor Windows of lokale MCP.
Historische opslag-ID’s blijven compatibel.

## Commands
```bash
# macOS build (lokaal, signed → TCC-rechten blijven behouden over rebuilds)
xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug -allowProvisioningUpdates build

# macOS build (CI / geen cert beschikbaar → ad-hoc, TCC vraagt elke build opnieuw)
xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Tests
xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVaultTests

# Windows dev
cd windows && npm run tauri dev

# Release via CI (aanbevolen)
scripts/deploy-dev.sh <github-ref>         # expliciete Windows-dev-build
scripts/deploy-production.sh <github-ref>  # expliciete Windows-production-build

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
- macOS TCC/rechten: lokaal **signed** bouwen (`-allowProvisioningUpdates`, cert `Apple Development: info@michelknoop.nl`, team `XL9KN38ATX`). Ad-hoc builds (`CODE_SIGNING_ALLOWED=NO`) hebben geen stabiele designated requirement → macOS vraagt rechten elke build opnieuw. Signed = stabiele identity → **mic / spraak / agenda / documenten blijven behouden** (deze TCC-grants zijn op bundle-ID gekeyed in de user-db). **Uitzondering: Screen Recording** (`kTCCServiceScreenCapture`, via ScreenCaptureKit) re-prompt blijft op macOS 26 Tahoe: die grant leeft in de SIP-protected system-db, is pad/cdhash-gevoelig en wordt door macOS bij elke binary-wijziging + periodiek opnieuw gevraagd — ongeacht stabiele signing. Mitigatie: app altijd vanaf **hetzelfde vaste pad** draaien (`/Applications/ThoughtVault.app`), nooit vanuit roterende DerivedData-pad en nooit meerdere kopieën tegelijk (elke kopie/rebuild = andere cdhash → TCC ziet "andere app").
- **SwiftData store-divergentie (notulen "ineens kwijt")**: de app is **gesandboxed** (`com.apple.security.app-sandbox`). `URL.applicationSupportDirectory` (zie `LocalTranscriptStore.storeURL`) wijst dan naar de container `~/Library/Containers/nl.prezent.ThoughtVault/Data/Library/Application Support/ThoughtVault/Local.store`. Een **niet-gesandboxde** build schrijft naar `~/Library/Application Support/ThoughtVault/Local.store` — een andere store. Wissel je tussen sandboxed/non-sandboxed builds, dan lijken notulen verdwenen (app leest de verkeerde store; een sandboxed app kán de non-sandbox map niet eens lezen). **Altijd gesandboxed bouwen/draaien.** Herstel = store-bestand handmatig naar de container kopiëren (app eerst afsluiten i.v.m. open WAL).
- Versioning: elke commit op `main` bumpt automatisch patch via `.githooks/post-commit`
- Na version bump: `scripts/sync-version.sh` draaien om VERSION naar alle platform configs te syncen
- Downloads: `https://n8n.prezent.nl/tstudio/download/` — lees docs/RELEASE.md voor infra details
- **CI/CD**: GitLab CI (`.gitlab-ci.yml`) voor macOS + Android + Windows + deploy. Mac runner (shell executor) voor macOS/Android, self-hosted Windows PC (tag `windows`) voor MSI builds. GitHub Actions als fallback voor Windows. Windows runner draait als SYSTEM — `useLocalToolsDir: true` in tauri.conf.json is vereist. Zie DEC-055, DEC-056, DEC-058.
- **Multi-instance deployment** — Lees docs/PLAN-MULTI-INSTANCE.md en DEC-033 wanneer relevant
- **n8n notule flow**: `handleiding` profiel → Claude proxy (`n8n_claude_code:3100`), overige → Ollama. Backend stuurt `profile_id` mee in webhook payload. Zie docs/ARCHITECTURE.md "n8n Notule Generation Flow" (DEC-057)
- **HTMLWebView + eigen CSS**: Als notule-HTML een `<style>` block bevat (handleiding-profiel), dan `extractStyles()` gebruiken om CSS naar `<head>` te verplaatsen. WKWebView past counters/grid/pseudo-elements niet toe vanuit `<style>` in `<body>`.
- **Notule titels**: Backend extraheert titels via `_extract_title_from_html()` in `transcription.py`. Sectiekoppen (bijv. "Kernargumenten") worden gefilterd via `_SECTION_WORDS`. Titel-extractie gebeurt in twee codepaths: `/callback/notule` route EN `app.py` queue callback — beide moeten in sync blijven.

## Credentials & Environment Variables
Beheerd door Claude Vault: vrijgave via `/grant NAAM`, gebruik via `vault-exec` (zie globale instructies). Vereiste variabelen: zie `.env.example`.

## gstack (REQUIRED — global install)

**Before doing ANY work, verify gstack is installed:**

```bash
test -d ~/.claude/skills/gstack/bin && echo "GSTACK_OK" || echo "GSTACK_MISSING"
```

If GSTACK_MISSING: STOP. Do not proceed. Tell the user:

> gstack is required for all AI-assisted work in this repo.
> Install it:
> ```bash
> git clone --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
> cd ~/.claude/skills/gstack && ./setup --team
> ```
> Then restart your AI coding tool.

Do not skip skills, ignore gstack errors, or work around missing gstack.

Using gstack skills: After install, skills like /qa, /ship, /review, /investigate,
and /browse are available. Use /browse for all web browsing.
Use ~/.claude/skills/gstack/... for gstack file paths (the global path).

## GBrain Search Guidance (configured by /setup-gbrain)
<!-- gstack-gbrain-search-guidance:start -->

GBrain is set up and synced on this machine, with semantic embeddings via local
Ollama. Prefer gbrain over Grep when the question is semantic or you don't know
the exact identifier yet:
- "Where is X handled?" / semantic intent: `gbrain search "<terms>"` or `gbrain query "<question>"`
- "Where is symbol Y defined / used?": `gbrain code-def <symbol>` / `gbrain code-refs <symbol>`
- "What calls Y?": `gbrain code-callers <symbol>` / `gbrain code-callees <symbol>`

Grep stays right for known exact strings, regex, and file globs. Refresh the
index with `gbrain embed --stale` after large changes.

<!-- gstack-gbrain-search-guidance:end -->
