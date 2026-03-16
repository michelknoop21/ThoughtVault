# TranscriptStudio — Architecture

_Last updated: 2026-03-16_

---

## Overview

TranscriptStudio is a cross-platform meeting transcription system consisting of:

- **macOS client** — Swift 6+ / SwiftUI native app (`/macos/`)
- **Windows client** — Tauri 2.10 / React 19 / TypeScript desktop app (`/windows/`)
- **Android client** — Kotlin 2.x / Jetpack Compose / Material 3 (`/transcript-studio-android/`)
- **iOS Widget** — SwiftUI Live Activity (`/ios-widget/`)
- **Web app** — Server-rendered Jinja2 templates with vanilla JS (`../transcript-studio-backend/templates/`, `../transcript-studio-backend/static/`)
- **Backend** — FastAPI (Python) with GPU-accelerated Whisper transcription and n8n workflow orchestration

All clients share a common REST + SSE API and are deployed independently.

---

## Backend

**Stack:** FastAPI · insanely-fast-whisper · n8n · SQLAlchemy · PostgreSQL (productie) / SQLite (development fallback) · Redis (optional)

**Deployment:** Docker Compose on AWS EC2 GPU instance (Tesla T4) at `https://n8n.prezent.nl`
- **Server:** `michelk@3.69.205.209`
- **Path:** `/home/michelk/n8n/Transcript Studio/`
- **Container:** `n8n_transcript_studio` (nvidia runtime, source bind-mounted via `.:/app`)
- **Local repo:** `../transcript-studio-backend/` (relative to native app root)
- **Deploy:** `rsync` code to server + `docker restart n8n_transcript_studio` (no rebuild needed)
- **Nginx:** `n8n_nginx` container proxies `/tstudio/` to the backend container on port 5000

**Data model:** `User`, `Task`, `Note`, `Profile`, `InviteCode`, `Setting`, `ApiKey`

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
| POST | `/tstudio/api/transcribe-youtube` | Transcribe YouTube video; accepts optional `X-Google-Token` header for Captions API (instant), falls back to yt-dlp + Whisper |
| GET | `/tstudio/api/features` | Feature flags + OAuth config (`{"youtube_transcription": bool, "google_oauth_configured": bool, "google_oauth_client_id_macos": str}`); no auth required |
| GET | `/tstudio/api/admin/features` | Admin: list all feature flags with status |
| POST | `/tstudio/api/admin/features/{key}` | Admin: toggle feature on/off |
| GET | `/tstudio/api/tasks` | List all tasks for authenticated user |
| PATCH | `/tstudio/api/tasks/{id}` | Update task metadata (tags, title) |
| DELETE | `/tstudio/api/tasks/{id}` | Delete task and associated data |
| POST | `/tstudio/api/task/{id}/cancel` | Cancel in-progress task (ownership check, admin bypass) |
| DELETE | `/tstudio/api/task/{id}` | Delete task; active tasks cancelled first |
| GET | `/tstudio/api/transcripts` | Returns `{items: Transcript[], total: int}` — paginate with `?page=N&limit=100` |

**Authentication:** Three auth methods, checked in order:
1. `X-User-Token: <token>` (macOS) or `Authorization: Bearer <token>` (Windows/Android) — session tokens from login
2. `X-API-Key: tskey_<32 hex>` — per-user API keys for external integrations (two scopes: `full` and `read`)
3. `X-Admin-API-Key: <key>` — server-to-server (n8n callbacks)

Login sends `username` field (which accepts email addresses as value).

**Field name notes (verified against backend source):**
- `/auth/me` returns `user_id` and `username` (not `id` / `email`)
- `/auth/login` returns `requires_2fa` (not `requires_two_factor`) and `temp_token` — both omitted on standard login
- `/transcripts` returns `{"items": [...], "total": N}` — both clients paginate with `?page=N&limit=100` until all items loaded

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

**YouTube captions pipeline (primary):** `transcribed → processingWebhook → completed` (~1 second, no GPU). When `X-Google-Token` header is present and captions exist, the backend fetches caption text via YouTube Data API v3 (`captions.list` + `captions.download`), skips Whisper entirely, and feeds text into the notule pipeline. Caption track priority: nl standard > nl ASR > en standard > en ASR > any. Response includes `source_type: "youtube_captions"` and `captions_available: true`. See DEC-041.

**YouTube yt-dlp pipeline (fallback):** `pending → downloading → converting → transcribing → transcribed → processingWebhook → completed`. Used when no captions available or no Google token provided.

**YouTube infrastructure (yt-dlp fallback):** yt-dlp invoked via `python3 -m yt_dlp` (avoids conda/pip PATH conflicts). Requires three components on server: (1) browser cookies at `/app/cookies.txt` for YouTube auth (exported from Firefox, must be refreshed periodically), (2) Node.js 20+ at `/usr/local/bin/node` for EJS challenge solving, (3) `yt-dlp-ejs` package (installed via `pip install yt-dlp[default]`). Config: `YOUTUBE_COOKIES_FILE` env var (default `/app/cookies.txt`). See DEC-038.

**Google OAuth (YouTube):** Admin configures `google_oauth_client_id_macos` via Admin > Instellingen. Client ID exposed via `/features` endpoint. macOS uses `GoogleAuthService` (actor, PKCE, `ASWebAuthenticationSession`) with scope `youtube.force-ssl`. Refresh token persisted in Keychain (key: `googleRefreshToken`). See DEC-041.

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
macos/
├── App/
│   ├── TranscriptStudioApp.swift       # App entry point, window configuration (1100×750, min 900×600)
│   ├── ContentView.swift               # Root view, NavigationSplitView + TabView (Home, Opnemen, Taken, Notulen, Instellingen, Admin)
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
│   ├── MeetingNotificationService.swift # UNUserNotificationCenter delegate, OS notification scheduling
│   ├── BiometricService.swift          # LAContext Face ID / Touch ID evaluation
│   ├── KeychainService.swift           # Secure token storage (Secure Enclave)
│   ├── Analytics.swift                 # Usage event tracking
│   ├── CrashReporter.swift             # Crash capture and reporting
│   ├── DebugLogger.swift               # Structured debug logging
│   ├── VideoCallDetectionService.swift # KVO camera + running app detection for ad-hoc video calls
│   ├── GoogleAuthService.swift        # Google OAuth PKCE for YouTube Captions API access
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
│   ├── ProfilesView.swift              # Profile CRUD with style picker (Zakelijk/Informeel/Technisch) + single opdracht field
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
| `APIService` | `actor` | REST calls, SSE streaming, retry with exponential backoff, field mapping, upload progress via `UploadProgressDelegate` |
| `AudioRecorder` | `@Observable class` | AVFoundation mic capture, 16 kHz WAV, 60 Hz level metering, pause/resume, 7-day cleanup |
| `SystemAudioCapture` | `@Observable class` | ScreenCaptureKit system audio, `SCStreamConfiguration` audio-only mode |
| `OnDeviceTranscriber` | `actor` | SFSpeechRecognizer on-device transcription, optional whisper-rs GGML |
| `LLMService` | `protocol` | Local AI note generation (multiple provider implementations) |
| `LLMServiceFactory` | `struct` | Selects LLM provider: N8N cloud / Ollama / LM Studio / Apple Foundation Models |
| `NetworkMonitor` | `@Observable class` | `NWPathMonitor` reachability, triggers OfflineQueue processing on reconnect |
| `OfflineQueue` | `actor` | Disk-persisted JSON queue, atomic file writes, cleanup-safe references |
| `CalendarService` | `@Observable class` | EventKit meeting fetch, `EKEventStoreChangedNotification`, call-start alerts |
| `MeetingNotificationService` | `class` (singleton) | `UNUserNotificationCenter` delegate, schedules OS notifications for upcoming meetings, handles notification actions |
| `VideoCallDetectionService` | `@Observable class` | KVO camera monitoring + running app detection, posts `.videoCallDetected` with synthetic `CalendarEvent` |
| `BiometricService` | `actor` | `LAContext` biometric evaluation, Secure Enclave access |
| `KeychainService` | `actor` | `SecItemAdd`/`SecItemCopyMatching` with `kSecAttrAccessibleWhenUnlocked` |
| `Analytics` | `actor` | Session event recording, privacy-safe usage metrics |
| `CrashReporter` | `actor` | Uncaught exception capture and structured crash log submission |
| `DebugLogger` | `actor` | Structured log levels (debug/info/warning/error), in-app log viewer |
| `GoogleAuthService` | `actor` | Google OAuth PKCE flow, token refresh, Keychain persistence for YouTube Captions API |
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
| Main window | `NavigationSplitView` (collapsible sidebar + detail), default 1100×750, minimum 900×600. Sidebar collapses to 52px icon column with expand button; Shift+Cmd+S toggle. |
| MenuBarExtra | `MenuBarExtra("TranscriptStudio", systemImage:)` — recording controls, live duration, task progress |
| FloatingWidgetPanel | `NSPanel` overlay (non-activating, always on top) shown during active recording |
| iOS Live Activity | `RecordingActivityWidget` target — Dynamic Island + lock screen progress via ActivityKit |

---

## Windows Client

**Stack:** Tauri 2.10 · React 19 · TypeScript · Vite · Tailwind CSS · Zustand · Fluent UI icons

**Rust backend commands:** audio (WASAPI), auth (keyring), filesystem, HTTP proxy, SSE streaming, process detection, system utilities

**Audio pipeline:**
- **Microphone mode:** WASAPI input → 16 kHz mono 16-bit PCM WAV → `AppData/Recordings`
- **Combined mode:** Mic writes to `recording_{ts}.wav`, WASAPI loopback (system audio) writes to `recording_{ts}.loopback.wav` → after recording stops, `mix_wav_files()` merges both using element-wise max → temp loopback file deleted
- **Upload:** Tauri FS plugin reads WAV → browser `FormData` + `fetch()` → SSE progress

**Upload path:** File upload uses browser-native `FormData` + `fetch()` instead of Rust reqwest. The Tauri FS plugin (`@tauri-apps/plugin-fs`) reads the WAV file from disk into a `Uint8Array`, which is wrapped in a `Blob` and appended to `FormData`. This ensures multipart encoding is identical to an HTML form upload. Other API calls (JSON REST) still use the Rust `proxy_request` command to bypass CORS.

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
│   ├── api.ts              # All backend REST calls + field mapping boundary (uses Tauri proxy_request)
│   ├── llm.ts              # Local LLM provider abstraction
│   ├── microsoftGraph.ts   # M365 calendar via Microsoft Graph API (all calls via Tauri proxy_request, DEC-027)
│   ├── tauriCommands.ts    # TypeScript wrappers for Tauri IPC commands (audio, filesystem, system)
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
    ├── HomePage.tsx, LoginPage.tsx, RecordingPage.tsx
    ├── TranscriptsPage.tsx, TasksPage.tsx, SettingsPage.tsx, AdminPage.tsx
    ├── AccountPage.tsx     # GDPR export/delete
    └── ProfilesPage.tsx    # Profile management
```

**Data persistence:**
- OS keychain — auth token and credentials (via `keyring` Rust crate, migrated from localStorage in v1.0.22)
- `localStorage` — UI preferences, onboarding state
- `sessionStorage` — OAuth state parameter (temporary, cleared after callback)
- `Tauri plugin-store` — offline queue persistence
- `AppData/Recordings` — audio files (7-day cleanup)

**External integrations:**
- TranscriptStudio API at `n8n.prezent.nl` (configurable endpoint)
- Microsoft Graph — M365 calendar access + OAuth PKCE for meeting detection. All Microsoft API calls (token exchange, user profile, calendar events) route through Tauri `proxy_request` command to bypass browser CORS restrictions (see DEC-027)
- Ollama / LM Studio — local LLM generation (configurable HTTP endpoint)

---

## Android Client

**Stack:** Kotlin 2.x · Jetpack Compose · Material 3 · Hilt · Room · OkHttp + Retrofit · Kotlin Serialization

**Architecture:** MVVM with Hilt dependency injection, Repository pattern, single-activity Compose navigation

**Minimum deployment:** Android 9 (API 28) · Target SDK: 36

**Status:** Active development (UI screens implemented, recording integration in progress)

### Directory Structure

```
transcript-studio-android/app/src/main/java/nl/prezent/transcriptstudio/
├── TranscriptStudioApp.kt              # @HiltAndroidApp entry point
├── MainActivity.kt                     # Single activity, edge-to-edge, Compose host
│
├── data/
│   ├── local/
│   │   ├── AppDatabase.kt              # Room database (QueuedUpload table)
│   │   ├── QueuedUpload.kt             # Offline queue entity
│   │   └── QueuedUploadDao.kt          # Room DAO for queued uploads
│   ├── model/
│   │   ├── Admin.kt                    # Admin data models (users, invite codes, metrics)
│   │   ├── Auth.kt                     # Login request/response, 2FA models
│   │   ├── Profile.kt                  # Transcription profile model
│   │   ├── Task.kt                     # Task model with status pipeline
│   │   └── Transcript.kt              # Transcript model with HTML notes
│   ├── remote/
│   │   ├── ApiService.kt               # Retrofit interface — all REST endpoints
│   │   ├── AuthInterceptor.kt          # OkHttp interceptor — adds Authorization header
│   │   ├── DynamicBaseUrlInterceptor.kt # Configurable server URL
│   │   └── SSEClient.kt               # OkHttp-based SSE streaming client
│   └── repository/
│       ├── AdminRepository.kt          # Admin operations (users, invite codes)
│       ├── AuthRepository.kt           # Login, 2FA, token management
│       ├── ProfileRepository.kt        # Profile CRUD
│       ├── TaskRepository.kt           # Task operations + SSE streaming
│       └── TranscriptRepository.kt     # Transcript list, detail, export
│
├── di/                                  # Hilt dependency injection modules
│   ├── AuthModule.kt                   # Token store, biometric service
│   ├── DatabaseModule.kt              # Room database singleton
│   └── NetworkModule.kt               # OkHttp client, Retrofit, API service
│
├── service/
│   ├── AudioRecorderService.kt         # MediaRecorder audio capture
│   ├── BiometricService.kt            # AndroidX Biometric prompt
│   ├── NetworkMonitor.kt              # ConnectivityManager reachability
│   ├── OfflineQueueManager.kt         # Room-backed upload queue with retry
│   ├── RecordingForegroundService.kt   # Foreground service for background recording
│   ├── SecureTokenStore.kt            # EncryptedSharedPreferences (Tink)
│   └── SettingsRepository.kt          # DataStore preferences
│
└── ui/
    ├── navigation/
    │   ├── AppNavigation.kt            # NavHost with type-safe routes
    │   └── Routes.kt                   # Route definitions
    ├── theme/
    │   ├── Color.kt, Spacing.kt, Theme.kt, Type.kt  # Material 3 theme + design tokens
    ├── components/                      # Reusable composables (TSCard, TSButton, StatusBadge, etc.)
    ├── login/                           # LoginScreen + LoginViewModel
    ├── home/                            # HomeScreen + HomeViewModel
    ├── recording/                       # RecordingScreen + RecordingViewModel + WaveformVisualizer
    ├── tasks/                           # TasksScreen + TasksViewModel (SSE real-time)
    ├── transcripts/                     # TranscriptsScreen + TranscriptDetailScreen + ViewModels
    ├── settings/                        # SettingsScreen + SettingsViewModel
    └── admin/                           # AdminScreen + AdminViewModel (6 management tabs)
```

### Key Patterns

| Pattern | Implementation |
|---------|---------------|
| DI | Hilt with `@HiltAndroidApp`, `@AndroidEntryPoint`, `@HiltViewModel` |
| Networking | Retrofit + OkHttp with `AuthInterceptor` for token injection |
| Local storage | Room (offline queue), DataStore (preferences), EncryptedSharedPreferences (tokens) |
| SSE | Custom `SSEClient` using OkHttp streaming response |
| State | `StateFlow` in ViewModels, `collectAsStateWithLifecycle()` in composables |
| Navigation | Compose Navigation with type-safe routes |
| Strings | All UI text in `res/values/strings.xml` (Dutch) |
| Auth header | `Authorization: Bearer <token>` (same as Windows) |
| Build | AGP 9.1, Gradle 9.x, version read from root `VERSION` file at build time |

---

## Web App

**Stack:** Jinja2 templates · vanilla JavaScript · CSS · HTMX (partial page loading)

**Architecture:** Server-rendered HTML with progressive enhancement. Backend serves pages via `routes/pages.py`, templates extend `base.html`. JavaScript modules handle interactivity (recording, SSE streaming, admin actions). No build step — static assets served directly.

**Location:** `../transcript-studio-backend/templates/` (templates) + `../transcript-studio-backend/static/` (JS/CSS)

### Directory Structure

```
templates/
├── base.html                      # HTML shell, nav, theme toggle, HTMX partial loading
├── app.html                       # Authenticated app wrapper
├── auth/                          # Login, register, password reset, 2FA pages
├── components/                    # Reusable Jinja2 macros (modals, forms)
├── pages/
│   ├── upload.html                # Recording + file upload + YouTube transcription card
│   ├── transcripts.html           # Transcript library with search/filter
│   ├── notes.html                 # Note detail view with HTML rendering + export
│   ├── settings.html              # User settings + profile selector
│   ├── landing.html               # Public landing/download page
│   ├── admin.html                 # Admin dashboard (includes tab partials below)
│   └── admin/
│       ├── dashboard.html         # Metrics overview (users, notes, errors)
│       ├── users.html             # User management (CRUD, 2FA reset)
│       ├── profiles.html          # Profile/prompt management
│       ├── invites.html           # Invite code management
│       ├── modules.html           # Feature flag toggles (YouTube etc.)
│       ├── logs.html              # Error + activity log viewer
│       ├── feedback.html          # User feedback management
│       └── modals.html            # Modal dialogs (edit user, edit profile)

static/
├── css/
│   ├── main.css                   # App styles, component styles, responsive layout
│   ├── landing.css                # Public landing page styles
│   └── registration.css           # Auth page styles
└── js/
    ├── admin.js                   # Admin tab management, CRUD operations, module toggles
    ├── auth.js                    # Login, registration, 2FA flows
    ├── upload.js                  # File upload, recording controls, SSE task tracking
    ├── transcripts.js             # Transcript list, search, filtering
    ├── notes.js                   # Note viewer, export actions
    ├── recorder.js                # MediaRecorder audio capture
    ├── settings.js                # Settings form handling
    ├── theme.js                   # Dark/light mode toggle
    └── utils.js                   # Shared helpers (auth token, fetch wrappers)
```

### Key Patterns

| Pattern | Implementation |
|---------|---------------|
| Auth | Token stored in `localStorage`, sent as `X-User-Token` header |
| Page loading | HTMX `hx-get` for partial page swaps within `app.html` shell |
| Feature flags | `fetch('/tstudio/api/features')` at page load, conditionally show/hide UI |
| SSE | Native `EventSource` for real-time task status updates |
| Admin tabs | `data-tab` attribute toggling `display: none/block` on content divs |
| File upload | `FormData` + `fetch()` with progress tracking |

---

## Cross-Platform Conventions

| Convention | Detail |
|-----------|--------|
| Configuration | No environment variables — all config via Settings UI |
| Offline first | `OfflineQueue` on all platforms retries uploads on reconnect |
| Real-time status | SSE stream used on all platforms, not polling |
| UI language | Dutch (nl_NL) throughout all clients |
| Audio format | 16 kHz mono 16-bit PCM WAV on all platforms |
| Field mapping | Backend field names normalized at API boundary on each client |
| Auth headers | `X-User-Token` (macOS), `Authorization: Bearer` (Windows/Android), `X-API-Key` (external integrations) — all accepted by backend |

---

## Deployment

| Component | Location |
|-----------|---------|
| Backend | AWS EC2 GPU instance, Docker Compose |
| Backend URL | `https://n8n.prezent.nl` (configurable) |
| macOS app | DMG via `https://n8n.prezent.nl/tstudio/download/` |
| Windows app | MSI via `https://n8n.prezent.nl/tstudio/download/` |
| Android app | APK via `https://n8n.prezent.nl/tstudio/download/` |
| iOS widget | App Store (bundled with macOS app) |
| Release manifest | `https://n8n.prezent.nl/tstudio/download/releases.json` |

### Build & Release Pipeline

Version is managed via the `VERSION` file (auto-bumped on commits to `main` by `.githooks/post-commit`). Two deployment paths:

**GitHub Actions (primary):** Triggered by tags (`v*` for production, `dev-v*` for dev). Builds all three platforms in parallel (macOS DMG, Windows MSI, Android APK), uploads to server, updates `releases.json`, and creates a GitHub Release with changelog-based release notes.

```bash
./scripts/deploy-dev.sh         # Create dev-v* tag → GitHub Actions
./scripts/deploy-production.sh  # Create v* tag → GitHub Actions
```

**Local build (fallback):**
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

See [RELEASE.md](RELEASE.md) for detailed pipeline documentation.
