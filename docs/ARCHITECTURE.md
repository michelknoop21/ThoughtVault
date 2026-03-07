# TranscriptStudio — Architecture

_Last updated: 2026-03-07 (session 4)_

---

## Overview

TranscriptStudio is a cross-platform meeting transcription system consisting of:

- **macOS client** — Swift 6+ / SwiftUI native app (`/TranscriptStudio/`)
- **Windows client** — Tauri 2.10 / React 19 / TypeScript desktop app (`/transcript-studio-windows/`)
- **iOS Widget** — SwiftUI Live Activity (`/RecordingActivityWidget/`)
- **Backend** — FastAPI (Python) with GPU-accelerated Whisper transcription and n8n workflow orchestration

Both desktop clients share a common REST + SSE API and are deployed independently.

---

## Backend

**Stack:** FastAPI · insanely-fast-whisper · n8n · SQLAlchemy · PostgreSQL (productie) / SQLite (development fallback) · Redis (optional)

**Deployment:** Docker Compose on AWS EC2 GPU instance at `https://n8n.prezent.nl`

**Data model:** `User`, `Task`, `Note`, `Profile`, `InviteCode`, `Setting`

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/tstudio/api/auth/login` | Login with `username` + `password`; returns `{token, requires_2fa?, temp_token?}` |
| POST | `/tstudio/api/auth/verify-2fa` | Verify TOTP code with `temp_token`; returns `{token}` |
| GET | `/tstudio/api/auth/me` | Returns `{user_id, username, role}` for the authenticated user |
| POST | `/tstudio/api/upload` | Upload audio file; creates Task with status `pending` |
| GET | `/tstudio/api/task/{id}` | Get task detail |
| GET | `/tstudio/api/task/{id}/stream` | SSE stream of task status transitions |
| POST | `/tstudio/api/transcribe` | Transcribe audio (internal) |
| POST | `/tstudio/api/transcribe-text` | Generate notes from existing transcript text |
| GET | `/tstudio/api/tasks` | List all tasks for authenticated user |
| PATCH | `/tstudio/api/tasks/{id}` | Update task metadata (tags, title) |
| DELETE | `/tstudio/api/tasks/{id}` | Delete task and associated data |
| GET | `/tstudio/api/transcripts` | Returns `{items: Transcript[]}` — no pagination keys |

**Authentication:** All requests require `X-User-Token: <token>` header (not `Authorization: Bearer`). Login sends `username` field (which accepts email addresses as value).

**Field name notes (verified against backend source):**
- `/auth/me` returns `user_id` and `username` (not `id` / `email`)
- `/auth/login` returns `requires_2fa` (not `requires_two_factor`) and `temp_token` — both omitted on standard login
- `/transcripts` returns `{"items": [...]}` only — `total`/`page`/`limit` are not currently returned

### Transcription Data Flow

```
Client                    Backend                    n8n / Claude
  |                          |                            |
  |-- POST /upload --------> |                            |
  |                          |-- Queue Whisper job        |
  |-- GET /task/{id}/stream  |                            |
  |<- SSE: pending --------- |                            |
  |<- SSE: uploading -------- |                            |
  |<- SSE: converting ------- |                            |
  |<- SSE: transcribing ------ |                           |
  |<- SSE: transcribed ------- |-- Trigger webhook ------> |
  |                           |                           |-- Claude pipeline
  |<- SSE: processingWebhook  |<-- Note HTML ------------ |
  |<- SSE: completed --------- |                           |
```

**Status pipeline:** `pending → uploading → converting → transcribing → transcribed → processingWebhook → completed`

**Field mapping:** `Task.result` → `notuleHtml` (macOS Swift) / `notule_html` (Windows TypeScript)

**Authentication:** Token-based with `X-User-Token` header. Tokens remain valid until server-side `SESSION_INACTIVITY_DAYS` expiry.

**Database:** PostgreSQL 15 in productie. SQLite ondersteund als development fallback. Optional Redis voor caching.

---

## macOS Client

**Stack:** Swift 6+ · SwiftUI · @Observable · AVFoundation · ScreenCaptureKit · EventKit · LocalAuthentication

**Architecture:** MVVM with @MainActor ViewModels and actor-based services

**Minimum deployment:** macOS 14 Sonoma

### Directory Structure

```
TranscriptStudio/
├── App/
│   ├── TranscriptStudioApp.swift       # App entry point, window configuration (1100×750, min 900×600)
│   ├── ContentView.swift               # Root view, NavigationSplitView + TabView
│   └── AppDelegate.swift               # MenuBarExtra, FloatingWidgetController
│
├── Models/
│   ├── Models.swift                    # All Codable structs: TranscriptTask, Profile, User, etc.
│   ├── TaskStatus.swift                # 10-state pipeline enum
│   ├── RecordingMode.swift             # microphone / systemAudio / combined
│   └── QueuedItem.swift                # OfflineQueue persistence model
│
├── Services/
│   ├── APIService.swift                # actor; REST calls, SSE streaming, field mapping
│   ├── AudioRecorder.swift             # AVFoundation mic capture, 60 Hz metering, pause/resume
│   ├── SystemAudioCapture.swift        # ScreenCaptureKit system audio capture
│   ├── OnDeviceTranscriber.swift       # SFSpeechRecognizer / whisper-rs local transcription
│   ├── LLMService.swift                # LLMService protocol + implementations
│   ├── LLMServiceFactory.swift         # Selects provider (N8N / Ollama / LMStudio / AppleAI)
│   ├── NetworkMonitor.swift            # NWPathMonitor reachability
│   ├── OfflineQueue.swift              # Disk-persisted upload queue with retry
│   ├── CalendarService.swift           # EventKit + EKEventStoreChangedNotification
│   ├── BiometricService.swift          # LAContext Face ID / Touch ID evaluation
│   ├── KeychainService.swift           # Secure token storage (Secure Enclave)
│   ├── Analytics.swift                 # Usage event tracking
│   ├── CrashReporter.swift             # Crash capture and reporting
│   ├── DebugLogger.swift               # Structured debug logging
│   └── FloatingWidgetController.swift  # NSPanel overlay during recording
│
├── ViewModels/
│   ├── AuthViewModel.swift             # @Observable; login, biometric, token lifecycle
│   ├── RecordingViewModel.swift        # @Observable; recording state machine, upload, queue
│   └── TranscriptsViewModel.swift      # @Observable; search, filter, tag, sort, bulk ops
│
├── Views/
│   ├── HomeView.swift                  # Landing screen, quick-start recording
│   ├── LoginView.swift                 # Email/password + biometric login
│   ├── RecordingView.swift             # Dual-state: idle setup vs. active recording with waveform
│   ├── TranscriptsView.swift           # Transcript library with search, filter, tags
│   ├── ProcessingView.swift            # SSE progress display during transcription
│   ├── NotuleResultView.swift          # Rendered HTML notes + export actions
│   ├── SettingsView.swift              # App preferences, server URL, on-device toggle
│   ├── ProfilesView.swift              # Profile CRUD
│   ├── AccountView.swift               # GDPR: data export, account deletion
│   └── Components/
│       ├── WaveformView.swift          # Animated level meter waveform
│       ├── TranscriptCard.swift        # List cell: title, date, status badge, tags
│       ├── StatusBadge.swift           # Colour-coded TaskStatus indicator
│       ├── RecordingWidgetView.swift   # MenuBarExtra + FloatingWidget shared UI
│       └── CallAlertView.swift         # Calendar call-start overlay
│
├── Extensions/
│   ├── Color+Brand.swift              # Color.brandPrimary, Color.labelPrimary, etc.
│   └── Theme.swift                    # TS.Spacing, TS.Font, TS.Radius design tokens
│
└── Resources/
    ├── nl.lproj/Localizable.strings   # Primary Dutch strings
    ├── en.lproj/Localizable.strings   # English fallback strings
    └── TranscriptStudio.entitlements  # Sandbox, audio-input, calendars, ScreenCaptureKit
```

### Services Layer (15+ services)

| Service | Type | Responsibility |
|---------|------|---------------|
| `APIService` | `actor` | REST calls, SSE streaming, retry with exponential backoff, field mapping |
| `AudioRecorder` | `@Observable class` | AVFoundation mic capture, 16 kHz WAV, 60 Hz level metering, pause/resume, 7-day cleanup |
| `SystemAudioCapture` | `@Observable class` | ScreenCaptureKit system audio, `SCStreamConfiguration` audio-only mode |
| `OnDeviceTranscriber` | `actor` | SFSpeechRecognizer on-device transcription, optional whisper-rs GGML |
| `LLMService` | `protocol` | Local AI note generation (multiple provider implementations) |
| `LLMServiceFactory` | `struct` | Selects LLM provider: N8N cloud / Ollama / LM Studio / Apple Foundation Models |
| `NetworkMonitor` | `@Observable class` | `NWPathMonitor` reachability, triggers OfflineQueue processing on reconnect |
| `OfflineQueue` | `actor` | Disk-persisted JSON queue, atomic file writes, cleanup-safe references |
| `CalendarService` | `@Observable class` | EventKit meeting fetch, `EKEventStoreChangedNotification`, call-start alerts |
| `BiometricService` | `actor` | `LAContext` biometric evaluation, Secure Enclave access |
| `KeychainService` | `actor` | `SecItemAdd`/`SecItemCopyMatching` with `kSecAttrAccessibleWhenUnlocked` |
| `Analytics` | `actor` | Session event recording, privacy-safe usage metrics |
| `CrashReporter` | `actor` | Uncaught exception capture and structured crash log submission |
| `DebugLogger` | `actor` | Structured log levels (debug/info/warning/error), in-app log viewer |
| `FloatingWidgetController` | `class` | `NSPanel` floating overlay during active recording |

### State Management

- `@Observable` throughout — no Combine, no `@Published`.
- ViewModels are `@MainActor` classes instantiated in `TranscriptStudioApp.swift`.
- Services expose mutable state as regular `var` properties; `@Observable` macro instruments them.
- `RecordingViewModel` orchestrates: `AudioRecorder` → `SystemAudioCapture` → `APIService` → `OfflineQueue` → SSE stream → `TranscriptsViewModel`.

### Audio Pipeline (macOS)

```
AVFoundation (mic)          ScreenCaptureKit (system)
       |                              |
  AudioRecorder                SystemAudioCapture
  16kHz WAV buffer             16kHz PCM buffer
       |                              |
       +------- RecordingViewModel ---+
                      |
              mixAudioFiles() (combined mode)
                      |
             Local WAV file on disk
                      |
               APIService.upload()
                      |
               OfflineQueue (if offline)
```

### UI Surfaces

| Surface | Description |
|---------|-------------|
| Main window | `NavigationSplitView` (sidebar + detail), default 1100×750, minimum 900×600 |
| MenuBarExtra | `MenuBarExtra("TranscriptStudio", systemImage:)` — recording controls, live duration, task progress |
| FloatingWidgetPanel | `NSPanel` overlay (non-activating, always on top) shown during active recording |
| iOS Live Activity | `RecordingActivityWidget` target — Dynamic Island + lock screen progress via ActivityKit |

---

## Windows Client

**Stack:** Tauri 2.10 · React 19 · TypeScript · Vite · Tailwind CSS · Zustand · Fluent UI icons

**Rust backend commands:** audio (WASAPI), auth (keyring), filesystem, HTTP proxy, OAuth PKCE, process detection, system utilities

**Audio pipeline:** WASAPI capture → 16 kHz mono 16-bit PCM WAV → `AppData/Recordings` → upload / offline queue → SSE progress

### Frontend Structure

```
src/
├── components/
│   ├── calendar/           # Call alert overlay, meeting list
│   ├── layout/             # Sidebar, header, navigation
│   ├── onboarding/         # First-run setup flow
│   ├── recording/          # RecordingPanel, WaveformVisualizer, SavedRecordings, RecordingWidget
│   ├── settings/           # Settings tabs (server, LLM, audio, account)
│   ├── transcripts/        # TranscriptCard, TranscriptList, NotesViewer
│   └── FeedbackWidget.tsx  # Bug reporting and feedback submission
├── services/
│   ├── api.ts              # All backend REST calls + field mapping boundary
│   ├── llm.ts              # Local LLM provider abstraction
│   ├── microsoftGraph.ts   # M365 calendar via Microsoft Graph API
│   ├── offlineQueue.ts     # Tauri plugin-store backed queue
│   ├── sse.ts              # EventSource SSE wrapper
│   └── crashReporter.ts    # Crash capture and structured logging
├── stores/
│   ├── auth.ts             # User, token, biometric state (Zustand)
│   ├── calendar.ts         # Meeting list, call-alert state
│   ├── profiles.ts         # Profile CRUD
│   ├── recording.ts        # Recording state machine, background task tracking
│   ├── settings.ts         # App configuration
│   └── transcripts.ts      # Transcript list, search, filters
└── pages/
    ├── Home.tsx, Login.tsx, Recording.tsx
    ├── Transcripts.tsx, Settings.tsx, Admin.tsx
    ├── AccountPage.tsx     # GDPR export/delete
    └── ProfilesPage.tsx    # Profile management
```

**Data persistence:**
- `localStorage` — auth token, UI preferences
- `Tauri plugin-store` — offline queue persistence
- OS keychain — credentials (via Tauri `plugin-stronghold` / `keyring` crate)
- `AppData/Recordings` — audio files (7-day cleanup)

**External integrations:**
- TranscriptStudio API at `n8n.prezent.nl` (configurable endpoint)
- Microsoft Graph — M365 calendar access + OAuth PKCE for meeting detection
- Ollama / LM Studio — local LLM generation (configurable HTTP endpoint)

---

## Cross-Platform Conventions

| Convention | Detail |
|-----------|--------|
| Configuration | No environment variables — all config via Settings UI |
| Offline first | `OfflineQueue` on both platforms retries uploads on reconnect |
| Real-time status | SSE stream used on both platforms, not polling |
| UI language | Dutch (nl_NL) throughout both clients |
| Audio format | 16 kHz mono 16-bit PCM WAV on both platforms |
| Field mapping | Backend field names normalized at API boundary on each client |
| Auth headers | Both `X-User-Token` and `Authorization: Bearer` accepted by backend; macOS uses `X-User-Token`, Windows uses `Authorization: Bearer` |

---

## Deployment

| Component | Location |
|-----------|---------|
| Backend | AWS EC2 GPU instance, Docker Compose |
| Backend URL | `https://n8n.prezent.nl` (configurable) |
| macOS app | DMG via `https://n8n.prezent.nl/tstudio/download/` |
| Windows app | MSI via `https://n8n.prezent.nl/tstudio/download/` |
| iOS widget | App Store (bundled with macOS app) |
| Release manifest | `https://n8n.prezent.nl/tstudio/download/releases.json` |

### Build & Release Pipeline

Version is managed via the `VERSION` file (auto-bumped on commits to `main` by `.githooks/post-commit`). Release scripts in `scripts/` handle the full pipeline:

```
VERSION file (source of truth)
       ↓
 sync-version.sh  →  Xcode pbxproj + tauri.conf.json + Cargo.toml
       ↓
   build.sh       →  DMG (macOS) or MSI (Windows) in build/
       ↓
  upload.sh       →  scp to server + releases.json manifest update
```

**Server-side hosting:** The `n8n_nginx` container serves static files from `/home/michelk/tstudio-releases/` at `/tstudio/download/` via an `alias` directive. The volume is mounted read-only in `docker-compose.yml`.

See [RELEASE.md](RELEASE.md) for detailed usage instructions and clickable Finder shortcuts.
