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

### Backend
- Docker + Docker Compose
- NVIDIA GPU with current drivers (required for Whisper GPU transcription)

---

## Development

### macOS
```bash
open TranscriptStudio.xcodeproj
# Build & run from Xcode, or via CLI:
xcodebuild -scheme TranscriptStudio -sdk macosx build CODE_SIGNING_ALLOWED=NO
```

### Windows
```bash
cd transcript-studio-windows
npm install          # must run inside Windows VM (see .npmrc)
npm run tauri dev
```

### Backend
```bash
# See backend repo / Docker Compose configuration
docker compose up
```

---

## Configuration

Both clients default to `https://n8n.prezent.nl` as the backend server. The URL is configurable in the app's Settings screen — no environment variables or `.env` files required on the client side.

---

## Version

Current version: **1.0.3** (tracked in `VERSION` file, auto-bumped on commits to `main`).

Repository: [gitlab.prezent.nl/michelk/transcript-studio-native](https://gitlab.prezent.nl/michelk/transcript-studio-native)

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
