# TranscriptStudio — Changelog

All notable changes to the TranscriptStudio macOS and Windows applications are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2026-03-05] — Admin panel API alignment, entitlements, biometric fixes (v1.0.3)

### macOS

#### Fixed
- **Admin stats endpoint**: Changed from undocumented `/admin/stats` to correct
  `/admin/dashboard/metrics` endpoint per backend API documentation.
- **Admin user creation**: Added missing `password` parameter and corrected field naming from
  `"email"` to `"username"` in `createUser` API call.
- **Invitation system overhaul**: Replaced email-based invitation model with backend's invite
  code system using `max_uses`/`expires_hours` parameters. Corrected endpoint paths from
  `/admin/invitations` to `/admin/invites`. Added `deleteInvitation` method.
- **macOS entitlements**: Repaired sandboxing and device permission entitlements for audio
  input, calendar access, and ScreenCaptureKit.
- **Biometric token persistence**: Fixed token not being cleared from Keychain on logout,
  preventing stale biometric sessions.
- **Duplicate UI elements**: Removed duplicate sidebar toggle, title bar, and logo elements
  from macOS app navigation.
- **Login HTTP 422 error**: `APIService.login()` was sending `"email"` as the JSON field name
  but the backend expects `"username"`. Fixed by updating the request body dictionary key while
  keeping the Swift parameter named `email` for semantic clarity (see DEC-015).
- **`LoginResponse` decoding error**: On a standard login (no 2FA), the server returns only
  `token` — not `requires_two_factor`. Both fields are now `Optional` in `LoginResponse` and
  `AuthViewModel` uses `?? ""` + `guard !token.isEmpty` instead of `guard let` to handle both
  optional and non-optional compiler interpretations during incremental builds.
- **`TSUserInfo` decoding error**: `/tstudio/api/auth/me` returns `user_id` and `username`
  (not `id` and `email`). Added `CodingKeys` to `TSUserInfo` mapping `id ← "user_id"` and
  `email ← "username"`.
- **`TranscriptsResponse` decoding error**: `GET /tstudio/api/transcripts` returns
  `{"items": [...]}` — the server does not include `transcripts`, `total`, `page`, or `limit`
  keys. Removed incorrect `CodingKeys` mapping, corrected key to `items`, and made
  `total`/`page`/`limit` optional (`Int?`) to avoid decoding failure.
- **`TranscriptsViewModel`**: Updated `hasMore` calculation to handle optional `response.total`
  using `.map { $0 > count } ?? true` pattern.

#### Changed
- **Swift compilation errors on incremental build**: Compiler saw stale `String` (non-optional)
  for `response.token` due to derived data cache. Resolved by rewriting binding as
  `let token = response.token ?? ""` which is valid regardless of optionality.

#### Added
- **Git repository**: Initialized with automatic semantic versioning system via post-commit
  hook. Version tracked in `VERSION` file, auto-bumped on commits to `main`.
- **GitLab remote**: Connected to `gitlab.prezent.nl/michelk/transcript-studio-native`.

---

## [Unreleased]

### macOS

- ActivityKit Live Activity support with Dynamic Island waveform widget
- RecordingActivityAttributes model for real-time recording state propagation
- LiveActivityManager service for activity lifecycle control (start / update / end)
- Minimum window size constraint added to TranscriptStudioApp window configuration
- Sidebar toggle fix: restored NavigationSplitView sidebar show/hide button
- Home screen redesigned with Quick-Start recording card and live task progress list

---

## [2026-03-04] — Biometric auth, GDPR, combined recording, design tokens

### macOS

#### Added
- **Biometric login** (`BiometricService`): Face ID / Touch ID via `LocalAuthentication`
  framework. Auth token stored in Keychain under a `SecAccessControl` entry protected by
  `.biometryCurrentSet`. Falls back to password on biometric failure.
- **GDPR compliance** (`AccountView`): data export (JSON download of all transcripts) and
  account deletion with confirmation dialog. Backend endpoints called via `APIService`.
- **Force update mechanism**: `APIService.checkMinimumVersion()` compares the server's
  `minimum_version` field against the installed `CFBundleShortVersionString`. When the
  installed version is unsupported a `ForceUpdateView` blocks access to the rest of the app.
- **Combined recording mode**: `RecordingViewModel` now orchestrates simultaneous
  `AudioRecorder` (microphone) and `SystemAudioCapture` (ScreenCaptureKit system audio)
  sessions. Mixed PCM frames are written to a single output file before upload.
- **7-day audio retention**: `AudioRecorder.cleanupOldRecordings()` deletes local audio files
  older than seven days on startup. Files referenced by a queued `OfflineQueue` task are
  protected from deletion.
- **Design token migration**: `Color+Brand.swift` replaced all hard-coded `Color(hex:)`
  values with semantic design tokens (`brand.primary`, `surface.background`,
  `text.secondary`, etc.) backed by Asset Catalog color sets. Enables full Dark Mode support.
- **`@Observable` migration**: `AudioRecorder` and `SystemAudioCapture` migrated from
  `ObservableObject` / `@Published` / Combine to the Swift 5.9+ `@Observable` macro,
  eliminating Combine import and reducing boilerplate.
- **`CalendarService`**: reads `EKCalendar` for upcoming video calls (Zoom, Teams, Google
  Meet, Webex) and fires a `CallAlertView` banner one minute before the meeting start.

#### Changed
- `RecordingViewModel` (1221 lines): `audioLevels: [Float]` computed from active recorder;
  `duration: TimeInterval` exposed for menu bar timer; recording states: `idle → preparing →
  recording → paused → stopping → uploading → idle / error`.
- `TranscriptsViewModel`: `@Observable` class; paginated load via `APIService.getTranscripts`;
  local `filteredTranscripts` computed property applies `searchQuery`, `DateFilter`, and tag
  multi-select without additional network calls.
- `OnDeviceTranscriber` updated to SFSpeechRecognizer streaming API with live
  `liveTranscriptText` property published via `@Observable`.

#### Fixed
- Ellipsis menu buttons on `TranscriptCard` and `HomeSessionCard` were non-functional due to
  hit-testing conflict with a transparent overlay; resolved by restructuring `ZStack` layering.

### Windows (Tauri 2 + React 19)

#### Added
- OS keychain credential storage via `keyring` Rust crate with automatic migration from
  plain JSON credential files.
- Rich text note editor (`contentEditable`) with formatting toolbar (bold, italic, underline,
  ordered list, unordered list), replacing the plain `<textarea>`.
- Local LLM generation integrated into the recording flow: when `NotulenProvider` is
  `ollama` or `lmStudio`, notes are generated post-transcription with streaming output via
  Server-Sent Events and polling fallback.
- Call alert overlay: floating notification appears one minute before detected video calls;
  Windows native notifications via Tauri notification plugin.
- Five-step onboarding wizard (Welcome → Server URL → Microphone → Calendar → Complete),
  shown once and persisted via settings store.
- Custom profiles CRUD in Settings: create, edit, and delete note-taking profiles; server-
  managed profiles are marked read-only.
- GDPR compliance: JSON data export of all transcripts, and account deletion with
  confirmation dialog.
- Keyboard shortcuts `Ctrl+1`–`Ctrl+5` for rapid navigation (Home, Recording, Notes,
  Settings, Admin).
- Offline queue banner on `HomePage` showing visual indicator for queued items or network
  failures.
- Admin panel: per-user password reset and 2FA reset with confirmation dialogs.
- 2FA backup code regeneration with password confirmation requirement.
- Microphone device selector dropdown on recording page (visible when multiple devices are
  available).

---

## [2026-03-03] — Windows app initial release (Tauri 2 foundation)

### Windows

#### Added
- Tauri 2 + React 19 + TypeScript application scaffold.
- Login with 2FA (TOTP) support; mandatory password change on first login.
- WASAPI microphone recording (via Tauri Rust backend).
- Cloud upload with Server-Sent Events task status tracking.
- Note export in five formats: PDF, DOCX, TXT, Markdown, HTML.
- Microsoft 365 OAuth PKCE calendar integration for meeting detection.
- Offline upload queue with automatic retry on reconnect.
- WinUI 3 design system: Mica acrylic effects, Fluent icons, responsive layout.
- Admin panel: user management, role assignment, 2FA reset.
- Settings pages: server URL, microphone, recording mode, profile management.

---

## [2026-02-27 – 2026-03-01] — macOS app foundational work

### macOS

#### Added
- Swift 6.2 / macOS 14+ target; SwiftUI, strict concurrency (`Sendable`, `actor`).
- `APIService` (`actor`): HTTPS-only validation, JWT via `X-User-Token` header, retry with
  exponential backoff, streaming multipart upload for audio files.
- `KeychainService`: generic `SecItem` wrapper for reading, writing, and deleting secrets.
- `AudioRecorder`: AVFoundation microphone capture, WAV output, 7-day cleanup.
- `SystemAudioCapture`: ScreenCaptureKit system audio tap (macOS 13+).
- `OnDeviceTranscriber`: SFSpeechRecognizer offline recognition with live streaming.
- `OfflineQueue`: `Codable`-backed persistent queue with network monitor integration.
- `NetworkMonitor`: NWPathMonitor wrapper published via `@Observable`.
- `LLMService` + factory: `AppleFoundationModelService` (macOS 26 on-device) and
  `OpenAICompatibleLLMService` (Ollama / LM Studio / cloud).
- `AuthViewModel`: login, 2FA verify, session restoration from Keychain, logout.
- `RecordingViewModel`: central recording state machine.
- `TranscriptsViewModel`: paginated transcript list with search, filter, sort, pagination.
- `HomeView`, `RecordingView`, `TranscriptsView`, `SettingsView`, `ProcessingView`,
  `NotuleResultView`, `LoginView`, `OnboardingView`.
- Component library: `WaveformView`, `TranscriptCard`, `StatusBadge`, `RecordingWidgetView`,
  `CallAlertView`, `ProfilePicker`, `FloatingWidgetPanel`.
- `MenuBarExtra` with real-time recording duration timer and upload icon.
- `FloatingWidgetController` overlay shown during active recording.
- Custom URL scheme `transcriptstudio://` for deep linking.
- Dutch (`nl`) as primary language; English (`en`) localization parity.
- `Analytics`, `CrashReporter`, `DebugLogger` observability services.

---

## Architecture decisions

See `docs/DECISIONS.md` for Architectural Decision Records (ADRs) covering:

- `@Observable` migration rationale over `ObservableObject` + Combine
- Field mapping strategy between API snake_case and Swift camelCase
- Audio retention policy (7 days, queue protection)
- Keychain access group configuration
- ScreenCaptureKit permission flow for system audio
- Design token structure and Asset Catalog color set naming convention
