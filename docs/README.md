# TranscriptStudio — Developer Documentation

Cross-platform audio transcription app with native macOS (Swift 6) and Windows (Tauri 2) clients sharing a FastAPI + Whisper backend.

---

## Prerequisites

### macOS App
- macOS 14 Sonoma or later
- Xcode 16 or later
- Configure code signing: open `TranscriptStudio.xcodeproj`, go to Signing & Capabilities, set your own Team identity
- Required entitlements (already configured in `TranscriptStudio.entitlements`):
  - `com.apple.security.device.audio-input`
  - `com.apple.security.personal-information.calendars`
  - ScreenCaptureKit (system audio capture)

### Windows App
- Node.js 20+
- Rust toolchain via [rustup](https://rustup.rs)
- Tauri CLI: `cargo install tauri-cli`
- **Must be developed on a Windows machine** (WASAPI audio capture, native window effects)

### Backend
- Docker + Docker Compose
- NVIDIA GPU with current drivers (required for Whisper GPU transcription)

---

## First-time setup

### Git hooks (required)
```bash
git config core.hooksPath .githooks
```
This enables automatic patch version bumping on commits to `main`.

### macOS
```bash
open TranscriptStudio.xcodeproj
# Build & run from Xcode, or via CLI (without code signing):
xcodebuild -project TranscriptStudio.xcodeproj -scheme TranscriptStudio -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

### Windows
```bash
cd windows
npm install          # must run inside Windows environment
npm run tauri dev    # starts Vite dev server + Tauri window
```

### Android
```bash
cd transcript-studio-android
./gradlew assembleDebug
# Or open in Android Studio
```

### Backend (separate repo)
```bash
# See ../transcript-studio-backend/ for Docker Compose configuration
docker compose up
```

---

## Configuration

Both clients default to `https://n8n.prezent.nl` as the backend server. The URL is configurable in the app's Settings screen — no environment variables or `.env` files required on the client side.

### Microsoft 365 Calendar (Windows)
Requires Azure AD App Registration with:
- Redirect URI: `transcript-studio://auth/callback` (type: Mobile and desktop applications)
- API permissions: `User.Read`, `Calendars.Read`
- Admin configures `ms365_client_id` and `ms365_tenant_id` via the admin settings panel

---

## Version

Current version: **1.0.77** (tracked in `VERSION` file, auto-bumped on commits to `main`).

Repository: [gitlab.prezent.nl/michelk/transcript-studio-native](https://gitlab.prezent.nl/michelk/transcript-studio-native)

---

## Building & Releasing

Release builds are deployed via GitHub Actions. Two deploy scripts handle the full flow:

```bash
./scripts/deploy-dev.sh           # Dev build → GitHub Actions → download page (beta section)
./scripts/deploy-production.sh    # Production build → GitHub Actions → download page
```

Local builds (without GitHub Actions):
```bash
./scripts/release.sh              # Dev build + upload (default)
./scripts/release.sh --production # Production build + upload
./scripts/release.sh --no-upload  # Build without uploading
```

Downloads hosted at: `https://n8n.prezent.nl/tstudio/download/`

See [RELEASE.md](RELEASE.md) for the complete guide.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| macOS build fails with signing error | Add `CODE_SIGNING_ALLOWED=NO` flag, or set your Team in Xcode |
| Windows `npm install` fails | Must run on Windows, not macOS — native WASAPI bindings require Windows |
| Version not bumping on commit | Run `git config core.hooksPath .githooks` to activate the post-commit hook |
| OAuth callback not working (Windows) | Verify `transcript-studio://auth/callback` is registered in Azure AD as "Mobile and desktop" redirect URI (NOT SPA type) |
| Upload 422 error (Windows) | Upload uses browser `FormData` + `fetch()` — ensure CORS allows Tauri origins (`https://tauri.localhost`, `http://localhost:1420`) |
| macOS sidebar appears stuck/collapsed | Press `Shift+Cmd+S` to toggle sidebar expand/collapse, or click the expand arrow at the bottom of the icon column |

---

## Documentation Index

| File | Purpose |
|------|---------|
| `README.md` | This file — developer onboarding, prerequisites, build commands |
| `PRD.md` | Product Requirements Document: target users, features, technical requirements, out of scope |
| `ARCHITECTURE.md` | System design: dual-platform overview, backend data flow, macOS service layer, directory structure |
| `API.md` | Complete backend API reference: all endpoints, auth flows, data models, rate limits |
| `DECISIONS.md` | Architectural Decision Records (ADRs): rationale for key technical choices |
| `CHANGELOG.md` | Version history and release notes |
| `RELEASE.md` | Build & release pipeline: scripts, shortcuts, server-side setup |
