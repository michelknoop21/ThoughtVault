# ThoughtVault

## Stack
Native macOS/iOS (Swift 6, SwiftUI, `@Observable`) + Windows (Tauri 2, React/TypeScript).
Lokale opslag en transcriptie; lokale of cloud-AI voor notulen. Geen eigen account/backend nodig.
Bron: Gitea `origin`. Windows MSI: GitHub Actions `michelknoop21/ThoughtVault`.
Lees docs/WINDOWS-BUILD-WORKFLOW.md en docs/RELEASE.md voor builds/publicatie.

## Commands
```bash
# macOS build (lokaal, signed → TCC-rechten blijven behouden over rebuilds)
xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug -allowProvisioningUpdates build

# macOS build (CI / geen cert beschikbaar → ad-hoc, TCC vraagt elke build opnieuw)
xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Tests
xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS'

# Windows dev
cd windows && npm run tauri dev

# Windows CI — expliciete, gecontroleerde GitHub-bronref
bash scripts/deploy-dev.sh <github-ref>
bash scripts/deploy-production.sh <github-ref>

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

## Build en distributie

Gitea is de bronrepository, GitHub Actions bouwt Windows MSI's. Een Gitea-push
start geen GitHub-workflow. Gebruik de actuele gecontroleerde bronref; RDP is
niet nodig. De website leest gepubliceerde artifacts, niet de git-werkboom.
De updater-/downloadroute staat onder `https://thoughtvault.yinga.ai/releases/`.
Mac-release lokaal: Developer ID + notarization, zie docs/RELEASE.md.
Historische opslag-ID's en OAuth-callbacks blijven voor bestaande gebruikers
compatibel; zij vormen geen instructie om een ander project te deployen.

## Gotchas
- `notifications(named:)` gebruiken, NIET `notifications(for:)` in AuthViewModel
- Sidebar: custom collapsible sidebar (52px icon column ↔ full sidebar), toggle via `Shift+Cmd+S`. Niet meer `columnVisibility` gebruiken (DEC-029)
- Combined recording: `mixAudioFiles()` in RecordingViewModel (element-wise max over PCM)
- Backend `username` veld is het e-mailadres (niet `email`)
- macOS TCC/rechten: lokaal **signed** bouwen (`-allowProvisioningUpdates`, cert `Apple Development: info@michelknoop.nl`, team `XL9KN38ATX`). Ad-hoc builds (`CODE_SIGNING_ALLOWED=NO`) hebben geen stabiele designated requirement → macOS vraagt rechten elke build opnieuw. Signed = stabiele identity → **mic / spraak / agenda / documenten blijven behouden** (deze TCC-grants zijn op bundle-ID gekeyed in de user-db). **Uitzondering: Screen Recording** (`kTCCServiceScreenCapture`, via ScreenCaptureKit) re-prompt blijft op macOS 26 Tahoe: die grant leeft in de SIP-protected system-db, is pad/cdhash-gevoelig en wordt door macOS bij elke binary-wijziging + periodiek opnieuw gevraagd — ongeacht stabiele signing. Mitigatie: app altijd vanaf **hetzelfde vaste pad** draaien (`/Applications/ThoughtVault.app`), nooit vanuit roterende DerivedData-pad en nooit meerdere kopieën tegelijk (elke kopie/rebuild = andere cdhash → TCC ziet "andere app").
- **SwiftData store-divergentie (notulen "ineens kwijt")**: de app is **gesandboxed** (`com.apple.security.app-sandbox`). `URL.applicationSupportDirectory` (zie `LocalTranscriptStore.storeURL`) wijst dan naar de container `~/Library/Containers/nl.prezent.ThoughtVault/Data/Library/Application Support/ThoughtVault/Local.store`. Een **niet-gesandboxde** build schrijft naar `~/Library/Application Support/ThoughtVault/Local.store` — een andere store. Wissel je tussen sandboxed/non-sandboxed builds, dan lijken notulen verdwenen (app leest de verkeerde store; een sandboxed app kán de non-sandbox map niet eens lezen). **Altijd gesandboxed bouwen/draaien.** Herstel = store-bestand handmatig naar de container kopiëren (app eerst afsluiten i.v.m. open WAL).
- Versioning: elke commit op `main` bumpt automatisch patch via `.githooks/post-commit`
- Na version bump: `scripts/sync-version.sh` draaien om VERSION naar alle platform configs te syncen
- **HTMLWebView + eigen CSS**: Als notule-HTML een `<style>` block bevat (handleiding-profiel), dan `extractStyles()` gebruiken om CSS naar `<head>` te verplaatsen. WKWebView past counters/grid/pseudo-elements niet toe vanuit `<style>` in `<body>`.

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


## Windows visual release gate

Windows moet de **huidige** ThoughtVault-presentatie dragen; de verouderde
Windows-indeling is geen visuele referentie. Naam/logo, een succesvolle build en een MSI-starttest
bewijzen geen visuele overeenkomst. Bij een wijziging aan Mac- of Windows-opmaak:
lees `docs/design/windows/README.md`, vergelijk de echte schermen en actualiseer
het beoordeelde bewijs. `scripts/check-windows-design.py` moet slagen voordat een
Windows-installer openbaar wordt gemaakt. Zet reviewstatus/hashes nooit op groen
zonder de daadwerkelijke visuele controle. Behoud alle bestaande functies/data.
