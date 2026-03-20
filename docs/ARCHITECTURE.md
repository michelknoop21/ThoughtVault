# TranscriptStudio — Architecture

_Last updated: 2026-03-20_

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
| POST | `/tstudio/api/transcribe-youtube` | Transcribe YouTube video; tries anonymous captions first (no auth), then Google Captions API (if `X-Google-Token` present), falls back to yt-dlp + Whisper |
| GET | `/tstudio/api/features` | Feature flags + OAuth config (`{"youtube_transcription": bool, "google_oauth_configured": bool, "google_oauth_client_id_macos": str}`); no auth required |
| GET | `/tstudio/api/admin/features` | Admin: list all feature flags with status |
| POST | `/tstudio/api/admin/features/{key}` | Admin: toggle feature on/off |
| GET | `/tstudio/api/tasks` | List all tasks for authenticated user |
| PATCH | `/tstudio/api/tasks/{id}` | Update task metadata (tags, title) |
| DELETE | `/tstudio/api/tasks/{id}` | Delete task and associated data |
| POST | `/tstudio/api/task/{id}/cancel` | Cancel in-progress task (ownership check, admin bypass) |
| DELETE | `/tstudio/api/task/{id}` | Delete task; active tasks cancelled first |
| GET | `/tstudio/api/transcripts` | Returns `{items: Transcript[]}` — all transcripts in single response. Optional `?search=&tags=tag1,tag2` filters |

**Authentication:** Three auth methods, checked in order:
1. `X-User-Token: <token>` (macOS) or `Authorization: Bearer <token>` (Windows/Android) — session tokens from login
2. `X-API-Key: tskey_<32 hex>` — per-user API keys for external integrations (two scopes: `full` and `read`)
3. `X-Admin-API-Key: <key>` — server-to-server (n8n callbacks)

Login sends `username` field (which accepts email addresses as value).

**Field name notes (verified against backend source):**
- `/auth/me` returns `user_id` and `username` (not `id` / `email`)
- `/auth/login` returns `requires_2fa` (not `requires_two_factor`) and `temp_token` — both omitted on standard login
- `/transcripts` returns `{"items": [...]}` — single-request, no pagination needed (both clients load all transcripts at once)

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

**YouTube captions pipeline (primary):** `transcribed → processingWebhook → completed` (~1 second, no GPU). Three-step priority: (1) anonymous captions via `youtube-transcript-api` (no auth needed), (2) Google API captions via YouTube Data API v3 if `X-Google-Token` header present, (3) yt-dlp + Whisper fallback. Caption track priority: nl manual > nl ASR > en manual > en ASR > any. Response includes `source_type: "youtube_captions"` and `captions_available: true`. See DEC-044, DEC-041.

**YouTube yt-dlp pipeline (fallback):** `pending → downloading → converting → transcribing → transcribed → processingWebhook → completed`. Used when no captions available from either anonymous or Google API sources.

**YouTube infrastructure (yt-dlp fallback):** yt-dlp invoked via `python3 -m yt_dlp` (avoids conda/pip PATH conflicts). Requires three components on server: (1) browser cookies at `/app/cookies.txt` for YouTube auth (exported from Firefox, must be refreshed periodically), (2) Node.js 20+ at `/usr/local/bin/node` for EJS challenge solving, (3) `yt-dlp-ejs` package (installed via `pip install yt-dlp[default]`). Config: `YOUTUBE_COOKIES_FILE` env var (default `/app/cookies.txt`). Optional SOCKS5/HTTP proxy via `youtube_proxy` admin setting — applied to both yt-dlp (`--proxy`) and `youtube-transcript-api`. Metadata fallback: when yt-dlp `--dump-json` fails due to bot detection, oEmbed API (`noembed.com`) provides title and duration. See DEC-038, DEC-047.

**Google OAuth (YouTube):** Admin configures `google_oauth_client_id_macos` via Admin > Instellingen. Client ID exposed via `/features` endpoint. macOS uses `GoogleAuthService` (actor, PKCE, `ASWebAuthenticationSession`) with scope `youtube.force-ssl`. Refresh token persisted in Keychain (key: `googleRefreshToken`). See DEC-041.

**Field mapping:** `Task.result` → `notuleHtml` (macOS Swift) / `notule_html` (Windows TypeScript)

**Authentication:** Token-based with `X-User-Token` header. Tokens remain valid until server-side `SESSION_INACTIVITY_DAYS` expiry (365 days). **Never auto-logout**: both macOS and Windows clients keep the token on 401 errors. Windows retries 401 once after 2s; macOS logs and ignores `.authDidInvalidate`. See DEC-048. **Auto-login (Windows)**: "Onthoud mij" checkbox saves email + password in OS keyring (`saved_email`, `saved_password`, `remember_me` keys). On startup, `authStore.loadTokenFromKeyring()` validates existing token, then auto-logs in if remember-me is set. 2FA accounts auto-submit credentials and show only the code input. Network errors preserve credentials for next attempt. See DEC-050.

**Error handling:** Centralized error module (`app/errors.py`) with `raise_api_error()` replacing all direct `HTTPException` calls. Standard JSON response format: `{"error_code": "auth_required", "message": "Inloggen is vereist.", "detail": "..."}`. 11 structured error codes with Dutch user-facing messages. 500 errors log the real exception but only return generic message to client. Audio upload validates file extension against allowlist. File size limit: 500 MB on backend (`config.py`), 250 MB on clients (macOS/Windows). See DEC-049.

**Database:** PostgreSQL 15 in productie. SQLite ondersteund als development fallback. Optional Redis voor caching.

### Large File Pipeline Capacity

The entire backend pipeline is designed to handle files up to 500 MB without modification. Analysis per component:

| Component | Setting | Value | Notes |
|-----------|---------|-------|-------|
| **Nginx** | `client_max_body_size` | 500M | Maximum request body |
| **Nginx** | `proxy_read_timeout` | 3600s (1 hour) | Sufficient for long transcriptions |
| **Nginx** | `proxy_send_timeout` | 3600s (1 hour) | Sufficient for large uploads |
| **Nginx** | `proxy_buffering` | off | Streaming, no buffer issues |
| **Uvicorn** | Workers | 1 | Sequential processing |
| **Uvicorn** | Body size limit | Unlimited | Backend `config.py` does validation |
| **Upload endpoint** | Chunk size | 1 MB | Streaming in 1 MB chunks to disk |
| **Upload endpoint** | Storage | `/tmp/whisper_uploads/` | Server has sufficient disk |
| **Transcription queue** | Base timeout | 30 min | Files >50 MB get timeout ×2 = 60 min |
| **Transcription queue** | Watchdog interval | 5 min | Checks for stuck tasks |
| **Transcription queue** | Max retries | 2 | Retry on transient errors |
| **FFmpeg conversion** | Timeout | None explicit | FFmpeg is fast even for 500 MB (seconds) |
| **FFmpeg conversion** | Output | 16 kHz mono PCM | Output smaller than input |
| **Whisper** | GPU | CUDA 12.1 | GPU accelerated |
| **Whisper** | Memory optimization | Files >50 MB get optimized settings | Prevents OOM |
| **SSE streaming** | Heartbeat | 30s | Keeps connection alive during processing |

**Client-side limits:** macOS and Windows clients enforce 250 MB client-side. Backend accepts up to 500 MB (configurable in `config.py:max_upload_size`). The web interface has no client-side limit and relies on the backend limit.

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
│       ├── ProcessingBar.swift         # Global upload/processing status bar (all tabs)
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
| `APIService` | `actor` | REST calls, SSE streaming, retry with exponential backoff, field mapping, upload progress via `UploadProgressDelegate`, structured error parsing (`extractErrorInfo()` for `error_code` + `message`) |
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

### Background Upload Pipeline (macOS)

Uploads run in the background — `recordingState` returns to `.idle` immediately after recording stops. A temporary `TranscriptTask` (ID prefixed `upload-`) is added to `activeTasks` with `.uploading` status and updated with progress. On success, replaced with the real server task; SSE takes over. On failure, task shows error inline. `ProcessingBar` (`macos/Views/Components/ProcessingBar.swift`) renders `activeTasks` globally in `ContentView.detailView`, visible on all tabs. Same pattern as Windows `backgroundTasks` + `ProcessingBar.tsx`.

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
- **Microphone mode:** WASAPI input → `StreamingResampler` (device rate → 16 kHz in real-time callback) → mono 16-bit PCM WAV → `AppData/Recordings`
- **Combined mode:** Mic writes to `recording_{ts}.wav`, WASAPI loopback (system audio) writes to `recording_{ts}.loopback.wav` — both streams resample to 16 kHz in their callbacks via independent `StreamingResampler` instances → after recording stops, `mix_wav_files()` merges both using element-wise max → temp loopback file deleted
- **Resampling:** Windows devices typically run at 48 kHz (WASAPI doesn't support 16 kHz directly). `StreamingResampler` uses linear interpolation with `fractional_pos` state carried across callbacks for gapless chunk-boundary resampling. See DEC-051.
- **Upload:** Rust `proxy_upload` command streams WAV file in 64 KB chunks via reqwest multipart

**Upload path:** File upload goes through the Rust `proxy_upload` Tauri command (`commands/http.rs`), which streams the WAV file from disk using `tokio_util::io::ReaderStream` with 64 KB chunks. The file is never fully loaded into memory — `reqwest::multipart::Part::stream_with_length()` sends chunks directly to the server. Client-side file size validation (250 MB limit) uses file metadata before opening. All other API calls (JSON REST) use the Rust `proxy_request` command to bypass CORS.

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
│   ├── authStore.ts        # User, token, rememberMe, auto-login, pendingTwoFactor (Zustand + keyring)
│   ├── calendar.ts         # Meeting list, call-alert state
│   ├── profiles.ts         # Profile CRUD
│   ├── recording.ts        # Recording state machine, background task tracking
│   ├── settings.ts         # App configuration
│   ├── transcripts.ts      # Transcript list, search, filters
│   └── uploadQueueStore.ts # Offline queue upload progress (current item, %, speed) + permanently failed items tracking
└── pages/
    ├── HomePage.tsx, LoginPage.tsx, RecordingPage.tsx
    ├── TranscriptsPage.tsx, TasksPage.tsx, SettingsPage.tsx, AdminPage.tsx
    ├── AccountPage.tsx     # GDPR export/delete
    └── ProfilesPage.tsx    # Profile management
```

**Data persistence:**
- OS keychain — auth token, saved credentials for auto-login (`saved_email`, `saved_password`, `remember_me`), via `keyring` Rust crate
- `localStorage` — UI preferences, onboarding state, `rememberMe` checkbox state (via Zustand persist)
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
| Theme | `theme.js` IIFE sets `data-theme="dark"` on `<html>` based on `prefers-color-scheme` or `localStorage` override. CSS uses `[data-theme="dark"]` selectors. Login page has dedicated dark mode styles (not forced-light). |

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

Version is managed via the `VERSION` file (auto-bumped on commits to `main` by `.githooks/post-commit`). Two CI systems:

**GitLab CI (primary — `.gitlab-ci.yml`):** Self-hosted shell executor on Michel's Mac (runner "Michel-Mac", tags: `shell,macos,xcode`). Triggered by tags (`v*` for production, `dev-v*` for dev) or manual pipeline. Builds macOS DMG + Android APK, uploads to EC2 server via SSH, updates `releases.json`, and creates a GitLab Release with changelog-based release notes. Mac acts as sole runner and intermediary to EC2 (EC2 cannot reach GitLab due to security group).

**GitHub Actions (Windows only — `.github/workflows/build-windows.yml`):** Windows MSI builds remain on GitHub Actions (`windows-latest` runner) to avoid the 10x macOS billing multiplier. Triggered on `v*`/`dev-v*` tags pushed to GitHub. Uploads MSI to EC2 server and updates `releases.json` Windows entries.

```bash
./scripts/deploy-dev.sh         # Create dev-v* tag → GitLab CI (macOS + Android + deploy)
./scripts/deploy-production.sh  # Create v* tag → GitLab CI (macOS + Android + deploy)
# Windows MSI: push same tag to GitHub → GitHub Actions
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
