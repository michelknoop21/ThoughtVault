# TranscriptStudio — Build & Release Pipeline

## Overzicht

De release pipeline synchroniseert de versie uit het `VERSION` bestand naar alle platform-configuraties, bouwt release artifacts (DMG/MSI), en uploadt ze naar de downloadserver.

```
VERSION bestand (bron van waarheid)
        ↓
  sync-version.sh  →  Xcode pbxproj + tauri.conf.json + Cargo.toml
        ↓
    build.sh       →  DMG (macOS) of MSI (Windows) in build/
        ↓
   upload.sh       →  scp naar server + releases.json manifest
```

## Snel starten

### Via snelkoppelingen (dubbelklik in Finder)

In de `scripts/` map staan `.command` bestanden die je dubbelklikt om te starten:

| Bestand | Wat het doet |
|---------|-------------|
| `Sync Version.command` | Synchroniseert VERSION naar alle platform configs |
| `Build Release.command` | Synct versie + bouwt DMG/MSI |
| `Full Release.command` | Synct versie + bouwt + uploadt naar server |
| `Build Only (no upload).command` | Synct versie + bouwt, zonder upload |

### Via Terminal

```bash
# Alleen versie synchroniseren
./scripts/sync-version.sh

# Alleen bouwen (synct eerst automatisch)
./scripts/build.sh

# Alleen uploaden (na een eerdere build)
./scripts/upload.sh

# Volledige pipeline: sync → build → upload
./scripts/release.sh

# Volledige pipeline zonder upload
./scripts/release.sh --no-upload
```

## Scripts in detail

### `sync-version.sh` — Versie synchronisatie

Leest de versie uit `VERSION` en past deze aan in:

| Bestand | Wat wordt aangepast |
|---------|-------------------|
| `TranscriptStudio.xcodeproj/project.pbxproj` | `MARKETING_VERSION` (4x) + `CURRENT_PROJECT_VERSION` (patch als integer) |
| `transcript-studio-windows/src-tauri/tauri.conf.json` | `"version"` veld |
| `transcript-studio-windows/src-tauri/Cargo.toml` | eerste `version = "..."` onder `[package]` |

### `build.sh` — Release artifact bouwen

Detecteert automatisch het besturingssysteem:

**macOS:**
1. `xcodebuild archive` (Release configuratie, zonder code signing)
2. Extraheert `.app` uit het archief
3. Maakt DMG via `hdiutil create`
4. Output: `build/TranscriptStudio-{version}.dmg`

**Windows:**
1. `npm run tauri build` in `transcript-studio-windows/`
2. Kopieert MSI uit Tauri output
3. Output: `build/TranscriptStudio-{version}.msi`

### `upload.sh` — Upload naar server

1. Uploadt het artifact via `scp` naar `michelk@3.69.205.209:/home/michelk/tstudio-releases/`
2. Update `releases.json` manifest op de server

### `release.sh` — Orchestrator

Voert alle stappen sequentieel uit. Met `--no-upload` wordt de upload overgeslagen.

## Download URLs

| URL | Beschrijving |
|-----|-------------|
| `https://n8n.prezent.nl/tstudio/download/releases.json` | Manifest met laatste versie-info |
| `https://n8n.prezent.nl/tstudio/download/TranscriptStudio-{version}.dmg` | macOS installer |
| `https://n8n.prezent.nl/tstudio/download/TranscriptStudio-{version}.msi` | Windows installer |

### releases.json formaat

```json
{
  "latest_version": "1.0.20",
  "macos": {
    "url": "/tstudio/download/TranscriptStudio-1.0.20.dmg",
    "version": "1.0.20",
    "filename": "TranscriptStudio-1.0.20.dmg"
  },
  "windows": {
    "url": "/tstudio/download/TranscriptStudio-1.0.20.msi",
    "version": "1.0.20",
    "filename": "TranscriptStudio-1.0.20.msi"
  }
}
```

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
4. Draai `./scripts/release.sh` (of dubbelklik `Full Release.command`)
5. Artifact is beschikbaar op `https://n8n.prezent.nl/tstudio/download/`
