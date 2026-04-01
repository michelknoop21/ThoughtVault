# TranscriptStudio — Build & Release Pipeline

## Overzicht

De release pipeline ondersteunt twee channels: **dev** (standaard) en **production**. Dev builds hebben een eigen bundle ID en app naam, zodat ze naast productie-builds geinstalleerd kunnen worden.

```
BUILD_CHANNEL (dev | production)
        ↓
  env.sh           →  Channel-afhankelijke variabelen (bundle ID, app naam, artifact namen)
        ↓
  sync-version.sh  →  Xcode pbxproj + tauri.conf.json + Cargo.toml
        ↓
  build.sh         →  DMG (macOS) of MSI (Windows) in build/ met build-time overrides
        ↓
  upload.sh        →  scp naar server + releases.json manifest (dev_* of productie velden)
```

## Channels

| | Dev (standaard) | Productie (`--production`) |
|---|---|---|
| App naam | TranscriptStudio Dev | TranscriptStudio |
| Bundle ID (macOS) | `nl.prezent.TranscriptStudio.dev` | `nl.prezent.TranscriptStudio` |
| Bundle ID (Windows) | `nl.prezent.transcript-studio-dev` | `nl.prezent.transcript-studio` |
| DMG naam | `TranscriptStudio-Dev-{version}.dmg` | `TranscriptStudio-{version}.dmg` |
| MSI naam | `TranscriptStudio-Dev_{version}_x64.msi` | `TranscriptStudio_{version}_x64.msi` |
| Side-by-side installeerbaar | Ja (eigen bundle ID + app data) | Ja |
| releases.json velden | `dev_latest_version`, `dev_macos`, `dev_windows_x64` | `latest_version`, `macos`, `windows_x64` |

## Snel starten

### Via deploy scripts (aanbevolen)

```bash
# Dev build deployen via GitLab CI
./scripts/deploy-dev.sh

# Productie build deployen via GitLab CI
./scripts/deploy-production.sh
```

Deze scripts pushen commits naar GitLab, maken een tag aan (`dev-v{version}` of `v{version}`), en GitLab CI doet de rest: build → upload naar server → update releases.json → GitLab Release met release notes.

### Via GitLab CI (handmatig)

| Trigger | Channel | Hoe |
|---------|---------|-----|
| Push `v*` tag | Production | `./scripts/deploy-production.sh` of `git tag v1.0.50 && git push origin v1.0.50` |
| Push `dev-v*` tag | Dev | `./scripts/deploy-dev.sh` of `git tag dev-v1.0.50 && git push origin dev-v1.0.50` |
| Manual pipeline | Dev (default) | GitLab → CI/CD → Pipelines → Run pipeline |
| Manual pipeline | Production | GitLab → CI/CD → Pipelines → Run pipeline → Variable: CHANNEL=production |

### Via Terminal (lokale build)

```bash
# Dev build + upload (standaard)
./scripts/release.sh

# Productie build + upload
./scripts/release.sh --production

# Dev build, geen upload
./scripts/release.sh --no-upload

# Productie build, geen upload
./scripts/release.sh --production --no-upload

# Alleen versie synchroniseren
./scripts/sync-version.sh

# Alleen bouwen (synct eerst automatisch)
./scripts/build.sh

# Alleen uploaden (na een eerdere build)
./scripts/upload.sh
```

## Scripts in detail

### `env.sh` — Gedeelde configuratie

Wordt gesourced door alle andere scripts. Leest `BUILD_CHANNEL` (default `dev`) en zet:

| Variabele | Dev waarde | Productie waarde |
|-----------|-----------|-----------------|
| `APP_DISPLAY_NAME` | TranscriptStudio Dev | TranscriptStudio |
| `BUNDLE_ID_MACOS` | nl.prezent.TranscriptStudio.dev | nl.prezent.TranscriptStudio |
| `BUNDLE_ID_WINDOWS` | nl.prezent.transcript-studio-dev | nl.prezent.transcript-studio |
| `DMG_NAME` | TranscriptStudio-Dev-{version}.dmg | TranscriptStudio-{version}.dmg |
| `MSI_PREFIX` | TranscriptStudio-Dev | TranscriptStudio |

Plus gedeelde variabelen: `VERSION`, `BUILD_DIR`, `SERVER`, `REMOTE_DIR`, `ROOT_DIR`, `SCRIPT_DIR`.

### `sync-version.sh` — Versie synchronisatie

Leest de versie uit `VERSION` en past deze aan in:

| Bestand | Wat wordt aangepast |
|---------|-------------------|
| `TranscriptStudio.xcodeproj/project.pbxproj` | `MARKETING_VERSION` (4x) + `CURRENT_PROJECT_VERSION` (patch als integer) |
| `windows/src-tauri/tauri.conf.json` | `"version"` veld |
| `windows/src-tauri/Cargo.toml` | eerste `version = "..."` onder `[package]` |

### `build.sh` — Release artifact bouwen

Sources `env.sh` voor channel-configuratie. Detecteert automatisch het besturingssysteem.

**macOS:**
1. `xcodebuild archive` met build-time overrides: `PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID_MACOS`, `PRODUCT_NAME=$APP_DISPLAY_NAME`
2. Extraheert `.app` uit het archief
3. Ad-hoc code signing
4. Maakt DMG via `hdiutil create` met volume name `$APP_DISPLAY_NAME $VERSION`
5. Output: `build/$DMG_NAME`

**Windows:**
1. Zet `TAURI_CONFIG` env var met channel-specifieke `identifier` en `productName`
2. `npm run tauri build` in `windows/`
3. Kopieert MSI uit Tauri output
4. Output: `build/$MSI_X64_NAME`

### `upload.sh` — Upload naar server

1. Uploadt artifacts via `scp` naar `michelk@3.69.205.209:/home/michelk/tstudio-releases/`
2. Uploadt `download-page.html` als `index.html` en `features-page.html` als `features.html`
3. Update `releases.json` manifest:
   - **Dev channel**: schrijft naar `dev_latest_version`, `dev_macos`, `dev_windows_x64`, `dev_windows_arm64`
   - **Productie channel**: schrijft naar `latest_version`, `macos`, `windows_x64`, `windows_arm64`, `windows`

### `release.sh` — Orchestrator (lokale build)

Voert alle stappen sequentieel uit. Accepteert flags:
- `--production` — zet `BUILD_CHANNEL=production` (standaard: `dev`)
- `--no-upload` — slaat de upload stap over

### `deploy-dev.sh` — Dev deploy via GitLab

One-command dev deploy:
1. Pusht laatste commits naar `origin` remote (GitLab)
2. Maakt `dev-v{version}` tag aan (verwijdert bestaande tag als nodig)
3. Pusht tag naar GitLab → triggert CI pipeline met channel=dev

### `deploy-production.sh` — Productie deploy via GitLab

One-command productie deploy:
1. Pusht laatste commits naar `origin` remote (GitLab)
2. Maakt `v{version}` tag aan (faalt als tag al bestaat — bump VERSION eerst)
3. Pusht tag naar GitLab → triggert CI pipeline met channel=production

## GitLab CI Pipeline

Bestand: `.gitlab-ci.yml`

**Triggers:**
- Push `v*` tag → automatisch productie build
- Push `dev-v*` tag → automatisch dev build
- Handmatige pipeline → met optionele CHANNEL variabele (default: dev)

**Runner:** Michel's Mac (shell executor, gitlab-runner 18.10.0). Alle jobs draaien op dezelfde machine. Mac bereikt EC2 server via SSH voor deploys (EC2 kan GitLab niet bereiken — security group beperking).

| Job tag | Gebruikt door |
|---------|--------------|
| `shell` | prepare, build-android, deploy |
| `macos,xcode` | build-macos |
| `windows` | build-windows (self-hosted Windows PC) |

**Jobs:**
1. `prepare` — bepaalt versie en channel uit tag of variabele, zet artifact namen via dotenv
2. `build-macos` — bouwt DMG op Mac runner met channel-specifieke overrides
3. `build-windows` — bouwt MSI op self-hosted Windows PC (shell executor, `allow_failure: true`). Gebruikt `useLocalToolsDir: true` in `tauri.conf.json` voor WiX tools (zie DEC-058). Runner draait als LocalSystem — Rust/SSH paden vallen terug naar `C:\Users\michel\`.
4. `build-android` — bouwt APK met lokale JDK 21 + Android SDK op Mac
5. `deploy` — uploadt artifacts naar server via SSH, update releases.json, maakt GitLab Release via `scripts/create-gitlab-release.py`

**Windows MSI (fallback):** GitHub Actions (`.github/workflows/build-windows.yml`) op `windows-latest` runner is beschikbaar als fallback. Primaire Windows build draait nu op GitLab CI. Zie DEC-056, DEC-058.

**GitLab Releases:**
- Release notes worden automatisch uit de eerste entry van `docs/CHANGELOG.md` geëxtraheerd
- Release asset links verwijzen naar de server download URLs
- Releases worden aangemaakt via de GitLab API met `CI_JOB_TOKEN`

## Download URLs

| URL | Beschrijving |
|-----|-------------|
| `https://n8n.prezent.nl/tstudio/download/releases.json` | Manifest met productie + dev versie-info |
| `https://n8n.prezent.nl/tstudio/download/TranscriptStudio-{version}.dmg` | macOS productie installer |
| `https://n8n.prezent.nl/tstudio/download/TranscriptStudio-Dev-{version}.dmg` | macOS dev installer |
| `https://n8n.prezent.nl/tstudio/download/TranscriptStudio_{version}_x64.msi` | Windows productie installer |
| `https://n8n.prezent.nl/tstudio/download/TranscriptStudio-Dev_{version}_x64.msi` | Windows dev installer |

### releases.json formaat

```json
{
  "latest_version": "1.0.49",
  "macos": {
    "url": "/tstudio/download/TranscriptStudio-1.0.49.dmg",
    "version": "1.0.49",
    "filename": "TranscriptStudio-1.0.49.dmg"
  },
  "windows_x64": {
    "url": "/tstudio/download/TranscriptStudio_1.0.49_x64.msi",
    "version": "1.0.49",
    "filename": "TranscriptStudio_1.0.49_x64.msi"
  },
  "dev_latest_version": "1.0.50",
  "dev_macos": {
    "url": "/tstudio/download/TranscriptStudio-Dev-1.0.50.dmg",
    "version": "1.0.50",
    "filename": "TranscriptStudio-Dev-1.0.50.dmg"
  },
  "dev_windows_x64": {
    "url": "/tstudio/download/TranscriptStudio-Dev_1.0.50_x64.msi",
    "version": "1.0.50",
    "filename": "TranscriptStudio-Dev_1.0.50_x64.msi"
  }
}
```

## Download page

Het bestand `scripts/download-page.html` bevat de download pagina met:
- Productie downloads bovenaan (macOS + Windows cards met OS-detectie)
- "Ontwikkelversie (Beta)" sectie onderaan met oranje badge
- Beta sectie wordt automatisch verborgen als er geen `dev_*` velden in releases.json staan

## Server-side infrastructuur

De download route wordt bediend door de `n8n_nginx` container:

- **Nginx config**: `/home/michelk/n8n-prezent/nginx/default.conf`
- **Location block**: `/tstudio/download/` → alias `/srv/tstudio-releases/`
- **Volume mount**: `/home/michelk/tstudio-releases/` → `/srv/tstudio-releases/:ro`
- **Docker compose**: `/home/michelk/n8n-prezent/docker-compose.yml`

## Versie workflow

1. Ontwikkel op een feature branch
2. Merge naar `main` → post-commit hook bumpt `VERSION` automatisch (patch)
3. Voor major/minor: pas `VERSION` handmatig aan
4. **Dev release**: `./scripts/deploy-dev.sh` (maakt `dev-v*` tag, triggert GitLab CI)
5. **Productie release**: `./scripts/deploy-production.sh` (maakt `v*` tag, triggert GitLab CI)
6. GitLab CI bouwt, uploadt naar server, en maakt GitLab Release met release notes
7. Download page op `https://n8n.prezent.nl/tstudio/download/` toont automatisch de juiste versies
