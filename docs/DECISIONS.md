# TranscriptStudio — Architectural Decision Records

_Append-only log. Each entry records context, decision, and consequences._

---

## DEC-001 — @Observable Replaces ObservableObject + Combine

**Date:** 2026-03
**Status:** Accepted

**Context:** The original codebase used `ObservableObject` + `@Published` + Combine throughout ViewModels and services. This required ~70 lines of subscription bridging code and introduced Combine-specific complexity (sink, cancellables, AnyCancellable storage) that added no meaningful value over direct observation.

**Decision:** Migrate `AudioRecorder`, `SystemAudioCapture`, and all ViewModels (`AuthViewModel`, `RecordingViewModel`, `TranscriptsViewModel`) to Swift 6's `@Observable` macro.

**Consequences:**
- SwiftUI automatically tracks only the specific properties accessed by each view — eliminating over-rendering.
- Combine removed entirely from the macOS app.
- Simpler, more readable ViewModel code with no `@Published` boilerplate.
- Requires iOS 17+ / macOS 14+ (acceptable given minimum deployment targets).
- `notifications(named:)` must be used for async NotificationCenter — `notifications(for:)` is unavailable in this pattern.

---

## DEC-002 — WAV 16 kHz Mono 16-bit as Recording Format

**Date:** 2026-03
**Status:** Accepted

**Context:** Multiple audio formats were considered for recording. Whisper (the transcription engine) is trained on and performs best with 16 kHz mono audio. Higher sample rates or stereo provide no transcription benefit and increase file size and upload time.

**Decision:** Record and store all audio as 16 kHz, mono, 16-bit PCM WAV files on both macOS (AVFoundation) and Windows (WASAPI).

**Consequences:**
- Optimal Whisper transcription accuracy without format conversion overhead on the backend.
- Manageable file size (~1.9 MB/minute) suitable for mobile hotspot uploads.
- WAV container avoids lossy codec artefacts that can degrade transcription quality.
- No re-encoding step required before upload.

---

## DEC-003 — 7-Day Audio Retention with Queue Protection

**Date:** 2026-03
**Status:** Accepted

**Context:** Users requested the ability to re-transcribe recordings (e.g. after a transcription failure or to switch to a different model). Storing audio indefinitely would consume significant device storage.

**Decision:** Retain audio files for 7 days from the recording timestamp. The cleanup routine skips any file currently referenced by the `OfflineQueue`.

**Consequences:**
- Re-transcription is supported within the 7-day window.
- Queued uploads are never accidentally deleted before they have been sent.
- Storage impact is bounded: a heavy user recording 3 hours/day generates ~340 MB maximum.
- After 7 days, re-transcription is no longer possible from the original audio.

---

## DEC-004 — Actor-Based APIService for Thread Safety

**Date:** 2026-03
**Status:** Accepted

**Context:** Network calls from multiple ViewModels and background queue processing created potential data races on shared state (token storage, retry counters, active task dictionary) when using a class-based service.

**Decision:** Implement `APIService` as a Swift `actor`. All internal mutable state is protected by the actor's serial executor without explicit locks.

**Consequences:**
- Thread safety guaranteed by the Swift concurrency runtime with no manual locking.
- Callers use `await` naturally — no completion handlers or callbacks needed.
- Retry logic with exponential backoff is straightforward to implement as async functions.
- SSE streaming exposed as `AsyncStream<TaskStatus>` for clean consumption in ViewModels.
- Slightly more verbose call sites due to `await` requirements on every method call.

---

## DEC-005 — On-Device Transcription as Offline Fallback

**Date:** 2026-03
**Status:** Accepted

**Context:** Two separate requirements converged: (1) users in offline environments still need transcription; (2) privacy-conscious users (legal, HR, board meetings) need an option to keep audio and transcript entirely on-device.

**Decision:** Implement `OnDeviceTranscriber` service backed by Apple Speech framework (SFSpeechRecognizer) on macOS/iOS. The user can toggle on-device mode in Settings. `RecordingViewModel` routes to on-device or server transcription based on this setting and current network availability.

**Consequences:**
- Full offline capability: recordings can be transcribed without any server connection.
- Privacy guarantee for sensitive content: audio never leaves the device in on-device mode.
- On-device accuracy is lower than GPU Whisper for Dutch speech — user is informed of the trade-off.
- `whisper-rs` (GGML) integration path exists as a higher-accuracy on-device option (not enabled by default pending binary size evaluation).

---

## DEC-006 — ScreenCaptureKit for System Audio Capture

**Date:** 2026-03
**Status:** Accepted

**Context:** Capturing system audio (the remote participant's audio in a call) on macOS requires a mechanism beyond standard AVFoundation microphone input. Several approaches were evaluated: CoreAudio virtual tap (requires SIP disable on some macOS versions), third-party virtual audio drivers (install burden), and ScreenCaptureKit.

**Decision:** Use `ScreenCaptureKit` (available macOS 13+) for system audio capture in `SystemAudioCapture`. The entitlement `com.apple.security.screen-capture` is declared in `TranscriptStudio.entitlements`.

**Consequences:**
- ScreenCaptureKit is the only sandboxed, App Store-compatible API for system audio capture on macOS.
- Requires user permission prompt on first use (system-level consent dialog).
- Capture is initiated via `SCStreamConfiguration` with audio-only mode to avoid video overhead.
- Combined mode (microphone + system audio) implemented in `RecordingViewModel` using element-wise `max()` across level arrays from both sources.

---

## DEC-007 — Dutch as Primary UI Language

**Date:** 2026-03
**Status:** Accepted

**Context:** The target market is Dutch business professionals using Prezent / Yinga services. All early users and all internal stakeholders are Dutch-speaking.

**Decision:** Dutch (nl_NL) is the primary language for all user-facing strings. All strings are managed via `Localizable.strings` in `Resources/nl.lproj/`. An English fallback exists in `Resources/en.lproj/` but is not actively maintained for current release.

**Consequences:**
- All UI labels, error messages, alerts, and button titles must be written in Dutch.
- Xcode previews and UI tests use Dutch strings.
- Onboarding new contributors requires awareness that UI strings are not in English.
- Internationalisation to other languages is possible via additional `.lproj` directories but not planned.

---

## DEC-008 — Offline-First Queue: Recording Reliability over Real-Time Upload

**Date:** 2026-03
**Status:** Accepted

**Context:** Users record meetings in environments with unreliable network (conference venues, trains, basements). Losing a recording due to an upload failure at the end of a meeting would be a critical user experience failure.

**Decision:** Audio is written to disk first, always. Upload is a separate asynchronous step managed by `OfflineQueue`. `NetworkMonitor` watches `NWPathMonitor` and triggers queue processing when the path becomes satisfied.

**Consequences:**
- A recording is never lost due to network issues — the worst case is delayed notes delivery.
- `OfflineQueue` serialises pending items to a JSON file on disk, surviving app restarts.
- UI shows pending upload count so users know their recordings are queued and not lost.
- Files in the queue are excluded from the 7-day cleanup routine.
- Upload retry uses exponential backoff to avoid hammering the server during a partial outage.

---

## DEC-009 — Tauri 2 for Windows Client

**Date:** 2026-03
**Status:** Accepted

**Context:** A native-feeling Windows desktop app was required without duplicating the Swift macOS codebase. Electron was considered but rejected on size grounds.

**Decision:** Use Tauri 2 with React 19 + TypeScript for the Windows client.

**Consequences:**
- Binary size ~10 MB vs Electron's ~150 MB.
- Native WebView2 on Windows; Rust backend commands for native API access (WASAPI, keychain, filesystem).
- Requires Rust toolchain for contributors working on the Windows app.
- No built-in Node.js runtime — all native calls go through Tauri IPC commands.
- UI built with React + Tailwind CSS + Fluent UI icons for a Windows-native aesthetic.

---

## DEC-010 — SSE for Real-Time Transcription Status (Not Polling)

**Date:** 2026-03
**Status:** Accepted

**Context:** The transcription pipeline involves multiple backend stages (upload, convert, transcribe, webhook, complete) taking 30 seconds to several minutes. The client needs to reflect current progress without excessive server load.

**Decision:** Use Server-Sent Events (SSE) at `GET /tstudio/api/task/{id}/stream` for real-time status updates. Both clients open an SSE connection after upload and close it when the task reaches a terminal state.

**Consequences:**
- Single persistent HTTP connection per active task — much lower overhead than polling.
- Status transitions are reflected in the UI within milliseconds of the backend emitting them.
- SSE is consumed as `AsyncStream<TaskStatus>` in `APIService` (Swift) and as an `EventSource` in the React client.
- No WebSocket infrastructure required — SSE is unidirectional and sufficient for this use case.
- Connection is automatically re-established on network interruption.

---

## DEC-011 — Biometric Login via Keychain + Secure Enclave

**Date:** 2026-03
**Status:** Accepted

**Context:** Users requested Face ID / Touch ID login on macOS to avoid re-entering their password on every app launch.

**Decision:** Store the auth token in Keychain with `kSecAttrAccessibleWhenUnlocked` and `SecAccessControl` with `.biometryCurrentSet`. Retrieve it via a fresh `LAContext` after biometric evaluation in `BiometricService`.

**Consequences:**
- Token is protected by the Secure Enclave — it cannot be read without biometric consent.
- Falls back to password login if biometric configuration changes (new fingerprint enrolled, Face ID re-scanned).
- `BiometricService` wraps `LAContext.evaluatePolicy` as an async function for clean ViewModel integration.
- Biometric state is checked at app launch; failures (biometry not enrolled, lockout) degrade gracefully to password flow.

---

## DEC-012 — Centralized Field Mapping at API Boundary

**Date:** 2026-03
**Status:** Accepted

**Context:** The backend stores notes in `Task.result` and raw transcript in `Task.transcription`. Both macOS and Windows clients need these fields under platform-idiomatic names (`notuleHtml`/`rawTranscription` in Swift; `notule_html`/`raw_transcription` in TypeScript).

**Decision:** All field renaming is performed at the API boundary in `APIService.swift` (macOS) and `src/services/api.ts` (Windows). Internal app code never uses backend field names.

**Consequences:**
- All components use consistent, idiomatic field names.
- A backend rename requires updating only the mapping layer on each client.
- New backend fields are safely ignored until explicitly mapped.

---

## DEC-013 — Client-Side Logout Only

**Date:** 2026-03
**Status:** Accepted

**Context:** The backend has no token revocation endpoint. Implementing one would require a token store on the server side.

**Decision:** Logout clears the local token from Keychain / OS keychain only. The server-side token remains valid until `SESSION_INACTIVITY_DAYS` expiry.

**Consequences:** Tokens are not immediately invalidated on logout. This is acceptable for the current threat model (single-user devices, low-sensitivity shared credentials). If a device is lost, the user must change their password to invalidate the token server-side.

---

## DEC-015 — API Field Name Mismatches: Root Causes and Resolutions

**Date:** 2026-03-05
**Status:** Accepted

**Context:** Three decoding failures were discovered when running the macOS app against the live backend for the first time:
1. Login returned HTTP 422 because the client sent `"email"` but the server's Pydantic model requires `"username"`.
2. `/auth/me` returned `user_id` and `username`, but `TSUserInfo` expected `id` and `email`.
3. `GET /transcripts` returned `{"items": [...]}` with no pagination keys, but `TranscriptsResponse` mapped `items` via a `CodingKey` aliased to `"transcripts"` (inverted).

**Decision:** Fix all three at the API boundary (`APIService.swift` / `Models.swift`) without changing internal app code. Use `CodingKeys` enums for field renaming. Make fields optional when the backend conditionally omits them (e.g., `requires_two_factor` only present when 2FA is triggered; `total`/`page`/`limit` never returned by the transcripts endpoint).

**Consequences:**
- Internal app code continues to use idiomatic Swift names (`id`, `email`, `items`).
- The API boundary (`CodingKeys`) is the single place to update if backend field names change.
- `Optional` fields that are conditionally absent decode safely as `nil` instead of throwing.
- When backend pagination is added to `GET /transcripts` in future, `total`/`page`/`limit` will decode automatically without any client code change.

---

## DEC-016 — Admin API Invite Code Model Over Email Invitations

**Date:** 2026-03-05
**Status:** Accepted

**Context:** The macOS admin panel was designed with an email-based invitation system (send invite to email with role), but the backend implements a reusable invite code system with configurable usage limits and expiration.

**Decision:** Replace the email-invitation model entirely with the backend's invite code approach. Admin creates codes with `max_uses` and `expires_hours`; users register using a code. Endpoint paths corrected from `/admin/invitations` to `/admin/invites`.

**Consequences:**
- Admin panel now matches the actual backend capability.
- Invite codes can be shared through any channel (email, chat, print) — more flexible than server-side email.
- The AdminView's Uitnodigingen tab UI needs to collect max-uses and expiration instead of email/role.
- `deleteInvitation` added for revoking active codes.

---

## DEC-017 — Automatic Semantic Versioning via Git Post-Commit Hook

**Date:** 2026-03-05
**Status:** Accepted

**Context:** Manual version tracking was error-prone and often forgotten. A consistent version number is needed for force-update checks and release management.

**Decision:** Implement automatic patch-level version bumping via a `.githooks/post-commit` hook. Version is stored in a `VERSION` file at the project root. Only commits to `main` trigger a bump; feature branches and detached HEAD are excluded.

**Consequences:**
- Every commit to `main` produces a new version automatically.
- Version is accessible to the app at build time for display and force-update comparison.
- Major and minor bumps require manual intervention (editing `VERSION` directly).
- Hook must be activated via `git config core.hooksPath .githooks`.

---

## DEC-014 — GDPR Compliance in AccountView

**Date:** 2026-03
**Status:** Accepted

**Context:** App Store submission and EU GDPR regulations require user-accessible data export and account deletion.

**Decision:** Add data export (JSON download of all user data) and account deletion flows in `AccountView`. Add `PrivacyInfo.xcprivacy` manifest declaring all data types accessed.

**Consequences:**
- App Store compliant with privacy nutrition labels.
- Backend deletion endpoint implementation is pending — client shows confirmation dialog and calls the endpoint when available.
- Data export produces a JSON file containing task history, transcripts, notes, and profile settings.

---

## DEC-018 — Multi-Wave Waveform Visualizer for Cross-Platform Consistency

**Date:** 2026-03-06
**Status:** Accepted

**Context:** Windows WaveformVisualizer showed barely visible waveforms for quiet recordings. macOS had a single-wave sine visualizer. Both platforms needed improvement and consistency.

**Decision:** Implement a 5-layer multi-wave rendering system on Windows matching the macOS visual language. Each wave has independent frequency (0.9-2.1), speed (5.8-13.0 rad/s), phase offset, and history buffer sampling point (0-20 samples). Added dynamic range compression (pow 0.6) to make quieter sounds more visible, per-wave jitter for natural variation, and idle breathing animation at 3% amplitude during silence.

**Consequences:**
- Waveforms are now clearly visible even for quiet recordings.
- Cross-platform visual consistency between macOS and Windows apps.
- Primary wave (brand pink) rendered boldest (3px line, 8px glow); four secondary waves (blues/purples) use screen blend mode for additive color mixing.
- Idle breathing animation keeps the interface "alive" even when no audio is present.

---

## DEC-019 — Conditional UIKit Imports for Cross-Platform Compilation

**Date:** 2026-03-06
**Status:** Accepted

**Context:** macOS-only code was importing UIKit unconditionally, causing iOS/macOS cross-compilation failures. UIKit is iOS-only; AppKit is the macOS equivalent for many features.

**Decision:** Add conditional compilation blocks (`#if canImport(UIKit)`) around all UIKit-specific imports and usages. This includes pasteboard access, activity controllers for sharing, and OAuth window presentation.

**Consequences:**
- Single codebase compiles for both iOS 17+ and macOS 14+ targets.
- Features like clipboard copy, share sheets, and OAuth presentation work correctly on both platforms.
- Code is slightly more verbose due to conditional compilation, but avoids duplicate implementations.

---

## DEC-020 — Background Task Tracking in Recording UI

**Date:** 2026-03-06
**Status:** Accepted

**Context:** Users had no visibility into background upload tasks after stopping a recording. The Windows app lacked the task tracking infrastructure that macOS had.

**Decision:** Add background task display section in RecordingPage showing active uploads with progress indicators. Store tracks multiple active tasks simultaneously with status updates via SSE.

**Consequences:**
- Users can see upload progress even after navigating away from the recording screen.
- Better UX for slow network conditions — users know their recordings are being processed.
- Windows implementation now matches macOS background task visibility.

---

## DEC-021 — Centralized API Base URL with Path Prefix

**Date:** 2026-03-07
**Status:** Accepted

**Context:** Both macOS and Windows apps had `/tstudio/api/` hardcoded in every individual endpoint path. This meant changing the API path prefix required updating 30+ endpoint definitions per platform.

**Decision:** Move the `/tstudio/api/` prefix into the base URL configuration. All endpoint paths are now relative (e.g., `/transcripts` instead of `/tstudio/api/transcripts`). The default base URL is `https://n8n.prezent.nl/tstudio/api`.

**Consequences:**
- Single place to change the API path prefix on each platform.
- Settings UI stores the full base URL including the API path.
- Existing users who configured a custom server URL need to append `/tstudio/api` (handled by default value update).
- macOS uses relative URL resolution (`URL(string:relativeTo:)`); Windows uses string concatenation.

---

## DEC-022 — Automated Build Pipeline with Ad-Hoc Signing

**Date:** 2026-03-07
**Status:** Accepted

**Context:** Building release artifacts was manual and error-prone. The `VERSION` file was not synced to platform build configs (Xcode had `MARKETING_VERSION = 1.0`, Tauri had `1.0.10`). No distribution mechanism existed for delivering builds to users.

**Decision:** Create four shell scripts (`sync-version.sh`, `build.sh`, `upload.sh`, `release.sh`) that automate the full release pipeline. macOS builds use ad-hoc code signing (`codesign --force --deep --sign -`) for internal distribution. Release artifacts are uploaded to EC2 and served via nginx at `/tstudio/download/`.

**Consequences:**
- Version numbers are consistent across all platform configs before every build.
- DMG/MSI artifacts are versioned and downloadable at a stable URL.
- Ad-hoc signed apps require "right-click → Open" on first launch (Gatekeeper bypass).
- Full Apple Developer signing can be added later by replacing `-` with a signing identity in `build.sh`.
- `.command` files provide clickable Finder shortcuts for non-technical release managers.

---

## DEC-023 — Backend Feedback Status Validation Must Include "archived"

**Date:** 2026-03-07
**Status:** Accepted

**Context:** Both macOS and Windows apps used `"archived"` as a feedback status for the admin archive feature, but the backend's `FeedbackUpdate` endpoint only validated `['new', 'in_progress', 'resolved', 'closed']`, causing a 400 Bad Request. The macOS app silently swallowed the error with `try?`, masking the bug. The Windows app showed "Status bijwerken mislukt" to the user. Additionally, both clients sent a `response` field for admin replies, but the Pydantic model expected `admin_response`.

**Decision:** Add `"archived"` to the backend validation list in `feedback.py`. Fix both clients to send `admin_response` instead of `response`. No database migration needed — the `update_feedback` db operation has no status constraint.

**Consequences:**
- Archive/restore workflow now works on both platforms.
- Admin responses are correctly stored and associated with the admin user.
- Backend validation list and client status usage are now aligned: `new`, `in_progress`, `resolved`, `closed`, `archived`.

---

## DEC-026 — Browser-Native FormData Upload over Rust reqwest

**Date:** 2026-03-11
**Status:** Accepted

**Context:** Multiple attempts to fix the Windows upload 422 error via Rust's reqwest library all failed — both the `multipart::Form` API (DEC-025) and manual `Vec<u8>` body construction produced multipart bodies that FastAPI's python-multipart parser rejected. The macOS client using URLSession (OS-native HTTP stack) worked perfectly, suggesting the issue was specific to how reqwest encodes multipart data when combined with nginx reverse proxy settings.

**Decision:** Remove the Rust-based upload path entirely. Read the WAV file via Tauri FS plugin (`readFile()` → `Uint8Array`), wrap it in browser-native `FormData` + `Blob`, and send with browser `fetch()`. This is identical to how an HTML `<form>` upload works — the most battle-tested multipart implementation available.

**Consequences:**
- Upload works reliably — browser FormData encoding is universally compatible with all HTTP servers.
- Rust no longer involved in the upload HTTP request; `http_upload_file` command removed, `multipart` and `uuid` dependencies dropped.
- Requires Tauri FS plugin with `fs:scope` permission allowing `$APPDATA/**` for reading recordings.
- CORS must allow the Tauri WebView origin (`https://tauri.localhost`) since fetch goes directly from browser to backend.
- The old file-readiness retry loop (20 attempts × 200ms) is unnecessary — the `recording-stopped` event already fires after WAV finalization.

---

## DEC-025 — reqwest Form API over Manual Multipart Construction

**Date:** 2026-03-11
**Status:** Superseded by DEC-026

**Context:** Windows audio uploads returned HTTP 422 "field required" despite the multipart body being correctly formatted (verified via debug middleware). Manual construction sent a fixed `Vec<u8>` body with an explicit `Content-Length` header via `.body()`. The combination of this approach with nginx's `proxy_buffering off` + `chunked_transfer_encoding off` settings interfered with python-multipart's ability to parse the body. A previous investigation (DEC-prior) used manual construction to work around a missing `multipart` feature flag in `Cargo.toml`, but that flag has since been added.

**Decision:** Replace the manual `Vec<u8>` multipart body with reqwest's `multipart::Form` API. Reqwest manages the boundary, `Content-Type` header, and body encoding internally. Remove the explicit `Content-Length` header and `http1_only()` constraint.

**Consequences:**
- Reqwest handles multipart encoding correctly and compatibly across platforms.
- Body is sent as `Transfer-Encoding: chunked` (streaming) rather than fixed-length — compatible with nginx upstream.
- Less code to maintain; no risk of manually constructed boundary format bugs.
- The `multipart` feature must remain in `Cargo.toml` (`reqwest = { features = ["multipart", ...] }`).

---

## DEC-024 — Windows Widget Pill Design Parity with macOS

**Date:** 2026-03-09
**Status:** Accepted

**Context:** The Windows floating recording widget existed in code but never appeared because `core:window:allow-create` (part of `core:window:default`) was missing from Tauri capabilities. The widget also used a vertical 240×140px card layout that didn't match the macOS pill-shaped overlay.

**Decision:** Fix the missing Tauri permission by adding `core:window:default` and `core:webview:default` to capabilities. Redesign the widget as a 380×56px horizontal pill matching macOS `RecordingWidgetView`: status badge with state label (REC/PAUZE/STOP...), inline waveform, monospaced timer, divider, pause/resume button, and labeled stop button. Position bottom-right above the Windows taskbar.

**Consequences:**
- Widget now appears during recording on Windows, matching macOS feature parity.
- Pill design is compact enough to stay visible without obscuring video call windows.
- Widget communicates with the main window via Tauri events (`audio-level`, `recording-stopped`) — no shared store needed.
- The Rust backend applies Windows 11 Acrylic effect to the widget via `window-vibrancy` on `tauri://webview-created` event.

---

## DEC-028 — Separate File Recording with Post-Mix for Windows Combined Mode

**Date:** 2026-03-12
**Status:** Accepted

**Context:** Windows combined mode (mic + system audio) had two critical bugs in `src-tauri/src/audio/recorder.rs`. First, `let _ = loopback_stream_holder;` on line 210 immediately dropped the WASAPI loopback stream due to Rust's `_` pattern semantics — bare `_` does not bind and drops the value immediately, unlike `_name` which creates a real binding. The loopback stream was destroyed before recording even started. Second, even if the stream survived, both mic and loopback callbacks wrote to the same `Arc<Mutex<WavWriter>>`, interleaving samples in arbitrary chunks from two OS audio threads. This produced garbled audio instead of a proper mix.

**Decision:** Fix the drop bug (`let _loopback = ...`) and refactor combined recording to write mic and loopback to separate WAV files. After both streams stop, `mix_wav_files()` reads both files and produces a mixed output using element-wise max by absolute value — the same algorithm macOS uses in `RecordingViewModel.mixAudioFiles()`. The loopback temp file is deleted after mixing.

**Consequences:**
- System audio is now actually captured via WASAPI loopback in combined mode.
- Audio quality is correct — no interleaved sample corruption from concurrent writes.
- Slight increase in disk usage during recording (two files), but the temp file is deleted immediately after mixing.
- If loopback initialization fails or mixing fails, the system gracefully degrades to mic-only audio.
- WASAPI loopback requires no special permissions — it captures the default output device's audio stream.

---

## DEC-027 — Route Microsoft Graph API Through Tauri proxy_request for CORS Bypass

**Date:** 2026-03-12
**Status:** Accepted

**Context:** The Windows app's Microsoft 365 OAuth token exchange failed with a generic "Token uitwisseling mislukt" error. Investigation revealed the root cause: `microsoftGraph.ts` used browser `fetch()` to call Microsoft's token endpoint. The redirect URI `transcript-studio://auth/callback` is registered in Azure AD as a "Mobile and desktop applications" type, not SPA. Microsoft's `/oauth2/v2.0/token` endpoint only returns CORS headers (`Access-Control-Allow-Origin`) for SPA-type redirect URIs. The Tauri WebView origin (`http://localhost:1420` in dev, `https://tauri.localhost` in production) was blocked by the missing CORS headers.

**Decision:** Replace all browser `fetch()` calls to Microsoft APIs with `invoke("proxy_request")`, which routes through the Rust reqwest HTTP client. Reqwest is not subject to browser CORS restrictions. This applies to three calls: token exchange (`/oauth2/v2.0/token`), user profile (`/me`), and calendar events (`/me/calendarView`).

**Consequences:**
- OAuth token exchange works reliably regardless of Azure AD redirect URI type configuration.
- All Microsoft Graph API calls are consistent — no mix of browser fetch and Tauri proxy.
- Error responses from Microsoft now include status code and body in console logs, improving future debugging.
- The existing `proxy_request` command in `http.rs` required no changes — it already supports POST with custom headers and body.
- Browser CSP `connect-src` entries for `login.microsoftonline.com` and `graph.microsoft.com` are no longer needed for these calls (but kept for forward compatibility).

---

## DEC-029 — Collapsible Sidebar Replacing columnVisibility Toggle

**Date:** 2026-03-12
**Status:** Accepted

**Context:** The macOS sidebar used SwiftUI's `NavigationSplitViewVisibility` (`columnVisibility`) state to toggle sidebar visibility. When the sidebar was hidden, it was completely removed from the view hierarchy with no affordance to restore it. This locked users out of the profile section containing the logout button — the only way to recover was to restart the app.

**Decision:** Replace the `columnVisibility`-based toggle with a custom `sidebarCollapsed` boolean state in `ContentView.swift`. Collapsed mode renders a minimal 52px-wide column showing only navigation icons with tooltips and an expand button at the bottom. Expanded mode shows the full sidebar with a collapse button in the profile section. Toggle via `Shift+Cmd+S` keyboard shortcut.

**Consequences:**
- Users always have a visible path to expand the sidebar and access logout, settings, and profile.
- The collapsed icon column provides quick navigation without occupying full sidebar width.
- Tooltips on collapsed icons ensure discoverability of each tab's purpose.
- The `Shift+Cmd+S` shortcut mirrors common sidebar toggle patterns in macOS apps (Finder, Xcode).
- The `columnVisibility` state is no longer used — sidebar visibility is entirely managed by the custom `sidebarCollapsed` property.

---

## DEC-031 — Build-Time Overrides for Dev/Production Channels

**Date:** 2026-03-13
**Status:** Accepted

**Context:** Elke build was automatisch een productie-release. Er was geen manier om snel een dev/beta build te maken met eigen bundle ID voor side-by-side installatie naast productie. Een dev pipeline was nodig voor het testen van nieuwe functies voordat ze naar productie gaan.

**Decision:** Build-time overrides via een `BUILD_CHANNEL` environment variabele (standaard `dev`). Geen bestanden in de repo worden permanent aangepast — `pbxproj` en `tauri.conf.json` behouden hun productie-waarden. Dev builds overschrijven ze tijdelijk: macOS via xcodebuild command-line settings (`PRODUCT_BUNDLE_IDENTIFIER`, `PRODUCT_NAME`), Windows via de `TAURI_CONFIG` env var die een JSON merge doet over tauri.conf.json. Een gedeeld `scripts/env.sh` bestand centraliseert alle channel-afhankelijke configuratie. GitHub Actions krijgt `workflow_dispatch` trigger naast de bestaande tag trigger. Het releases.json manifest op de server bevat aparte `dev_*` velden naast de bestaande productie-velden.

**Consequences:**
- Dev en productie builds zijn side-by-side installeerbaar (gescheiden bundle ID's en app data).
- Repository source files blijven altijd productie-waarden — geen risico op per ongeluk deployen met dev-configuratie.
- Dev is de standaard bij lokale builds en manual dispatch; productie vereist expliciet `--production` of een `v*` tag push.
- De download page toont automatisch een beta sectie wanneer dev builds beschikbaar zijn.
- `scripts/env.sh` is de single source of truth voor channel-configuratie — alle scripts sourcen dit bestand.

---

## DEC-030 — Auto-Pagination for Transcript Loading

**Date:** 2026-03-12
**Status:** Accepted

**Context:** Both macOS and Windows clients fetched only the first page of transcripts (up to 100 items). Users with more than 100 transcripts could not see older entries in the transcript library.

**Decision:** Implement automatic pagination in `TranscriptsView.loadTranscripts()` (macOS) and `getTranscripts()` (Windows `api.ts`). Both loop through pages of 100 items each, accumulating results until either the page returns fewer items than requested or the response total is reached. Error handling retains partially loaded data rather than showing nothing.

**Consequences:**
- All transcripts are now visible regardless of total count.
- Initial load time increases linearly with transcript count (one API call per 100 items).
- Partial load on error preserves user experience — some data is better than no data.
- No UI pagination controls needed — the list loads completely on mount.

---

## DEC-033 — Multi-Instance Over Multi-Tenant for Scaling to Multiple Customers

**Date:** 2026-03-13
**Status:** Accepted

**Context:** TranscriptStudio is currently a single-tenant system — one backend container, one database, one n8n flow. To serve multiple customers, two approaches were evaluated: (1) multi-tenant — adding an organization layer throughout the entire stack (database, auth, API, clients), estimated at 3-4 weeks of development with high security risk from potential data isolation bugs; (2) multi-instance — deploying a separate backend container + database + Redis index per customer using the same Docker image, requiring only deployment tooling with zero application code changes for the basic setup.

**Decision:** Adopt multi-instance deployment. Each customer gets their own Docker container, PostgreSQL database, Redis DB index, and Docker volume for file storage. Shared resources: GPU (Whisper model), Ollama LLM, nginx reverse proxy, and a single parameterized n8n flow. A separate `transcript-studio-ops` repository holds tenant configs (.env files with credentials) and management scripts. No fork per customer — all instances run the same Docker image with different environment variables. Customer-specific needs are addressed through three levels: (1) configuration via env vars (90%), (2) feature flags in code (8%), (3) webhooks or custom n8n flows (2%).

**Consequences:**
- Complete data isolation between customers — separate databases, volumes, and Redis indices.
- Zero application code changes for basic multi-instance (only env var-driven configuration).
- Small backend changes needed: configurable `API_ROOT_PATH`, `CALLBACK_PATH_PREFIX`, and dynamic callback URL in n8n webhook payload.
- One universal n8n flow serves all customers — callback URL and admin key are passed dynamically in the payload.
- GPU memory is the scaling bottleneck: each container loads Whisper (~3.2GB for medium model). At >4 customers, a shared Whisper microservice is needed.
- Operational overhead scales linearly with customers — mitigated by `manage-tenant.sh` automation.
- Credentials and tenant configs are kept in a separate private ops repo, not in the application code.
- Viable for 1-10 customers. At >20 customers, reconsider multi-tenant architecture.
- Full plan documented in `docs/PLAN-MULTI-INSTANCE.md`.

---

## DEC-032 — Simplified Profile Creation with Style Picker

**Date:** 2026-03-13
**Status:** Accepted

**Context:** Profile creation required users to fill in three text fields: "Systeemprompt" (AI personality/role), "Notulenprompt" (instructions for note generation), and "Sjabloon" (HTML template). User feedback indicated this was confusing — most users don't understand the difference between a system prompt and a notule prompt, and the technical jargon ("prompt", "sjabloon") was a barrier. The majority of use cases fall into one of three styles (zakelijk, informeel, technisch) that only differ in the system prompt.

**Decision:** Replace the dual-prompt form with a simplified flow in both macOS (`ProfilesView.swift → ProfileEditSheet`) and Windows (`ProfilesPage.tsx`). The new form has: (1) a **name** field, (2) a visual **style picker** with three options (Zakelijk/Informeel/Technisch) — each with an icon, label, and description — that maps to a predefined system prompt, and (3) a single **opdracht** field ("Wat moet er in de notulen staan?") with placeholder examples. The system prompt and HTML template fields are preserved in a collapsible "Geavanceerde opties" section for power users. When editing an existing profile, the style picker auto-detects which style matches the saved system prompt; profiles with custom system prompts open in advanced mode.

**Consequences:**
- Profile creation reduced from 3 required fields to 2 (name + opdracht). Style defaults to "Zakelijk".
- Backend API contract unchanged — clients still send `system_prompt` + `notule_prompt` strings. The simplification is entirely client-side.
- Existing profiles with custom system prompts continue to work — they show the advanced section when edited.
- The three style system prompts match the existing default profiles in `Models.swift` / `types.ts`, ensuring consistency.
- Users who need full control can still access the raw system prompt via the advanced toggle.

---

## DEC-034 — Directory Restructuring to Lowercase Platform Names

**Date:** 2026-03-13
**Status:** Accepted

**Context:** De repository had inconsistente directory-namen: `TranscriptStudio/` (CamelCase) voor de macOS source, `transcript-studio-windows/` (kebab-case) voor Windows, en `RecordingActivityWidget/` (CamelCase) voor de iOS widget. Met de toevoeging van `transcript-studio-android/` werd de naamgeving nog onoverzichtelijker. Nieuwe ontwikkelaars en AI-assistenten moesten telkens raden welke conventie gebruikt werd.

**Decision:** Hernoem naar consistente lowercase platform namen: `macos/`, `windows/`, `ios-widget/`. Laat `TranscriptStudio.xcodeproj` en `TranscriptStudioTests` ongemoeid — deze zijn gekoppeld aan Xcode schemes, targets en build settings; hernoemen zou disproportioneel risico opleveren voor minimale winst. Gebruik `git mv` om history te behouden.

**Consequences:**
- Alle build scripts, CI/CD workflows, .gitignore, en documentatie moesten bijgewerkt worden (~20 bestanden).
- Xcode `project.pbxproj` vereiste exacte pad-aanpassingen voor group path, entitlements, en Info.plist referenties.
- Historische plan-bestanden (`docs/plans/`, `.claude/plans/`) zijn niet bijgewerkt — ze zijn snapshots van eerdere sessies.
- Toekomstige platform directories volgen nu automatisch het patroon: `android/`, `web/`, etc.

---

## DEC-035 — YouTube Transcriptie via Backend Download (niet Client Upload)

**Date:** 2026-03-14
**Status:** Accepted

**Context:** YouTube-video's moesten transcribeerbaar worden in TranscriptStudio. Twee architecturale opties: (1) client downloadt audio en uploadt naar backend zoals bij normale opnames, of (2) client stuurt alleen de URL, backend downloadt de audio zelf via `yt-dlp`. Optie 1 zou yt-dlp op elke client vereisen (complexe native dependency op macOS/Windows/Android) en grote downloads over het netwerk twee keer verplaatsen (YouTube → client → server).

**Decision:** Backend downloadt YouTube audio via `yt-dlp` subprocess (`POST /transcribe-youtube`). Client stuurt alleen de URL. Nieuwe `downloading` task status toegevoegd aan de pipeline. Feature achter `FEATURE_YOUTUBE_ENABLED` flag zodat het per instance in/uitschakelbaar is. Rate limit 5/uur (strenger dan audio upload) om misbruik te voorkomen. Maximale videoduur configureerbaar via `YOUTUBE_MAX_DURATION_SECONDS` (default 7200s = 2 uur).

**Consequences:**
- Geen yt-dlp dependency nodig op clients — alleen een URL input veld en feature flag check.
- Backend Dockerfile moet `yt-dlp` bevatten (pip install). ffmpeg was al aanwezig.
- Nieuwe task status `downloading` vereist exhaustive switch updates op alle clients (macOS `TasksView.swift`, `ProcessingView.swift`; Windows `types.ts`).
- Feature flag via `GET /features` endpoint (ongeauthenticeerd) laat clients de YouTube UI conditioneel tonen.
- `source_type` en `source_url` kolommen op Task model voor traceerbaarheid van de bron.

---

## DEC-036 — Per-User API Keys met Hash-Only Opslag

**Date:** 2026-03-14
**Status:** Accepted

**Context:** Externe systemen (scripts, CI/CD, integraties) moeten de TranscriptStudio API kunnen aanspreken zonder interactieve login. Sessie-tokens zijn ongeschikt: ze verlopen na 7 dagen inactiviteit en vereisen username/password om te verkrijgen. Een API key systeem is nodig dat (1) veilig is bij database-lekken, (2) scope-beperking ondersteunt, en (3) geen nieuwe aanvalsvectoren introduceert voor key-replicatie.

**Decision:**
- Key formaat: `tskey_` prefix + 32 hex chars (38 chars totaal). Prefix maakt keys herkenbaar in logs en secret scanners.
- Alleen SHA-256 hash opgeslagen in database — ruwe key wordt eenmalig getoond bij aanmaak. Bij verlies moet een nieuwe key aangemaakt worden.
- Twee scopes: `full` (lezen + schrijven) en `read` (alleen lezen, 403 op write endpoints). Scope enforcement op elke write route via `check_write_scope()`.
- Authenticatie volgorde: `X-User-Token` → `X-API-Key` → `X-Admin-API-Key`. Bestaande auth flow blijft ongewijzigd.
- API key CRUD (aanmaken, revoken) is alleen beschikbaar via sessie-token — voorkomt dat een gelekte API key zichzelf kan repliceren.
- Max 10 actieve keys per gebruiker.
- Soft-delete bij revoke (`is_active=false`) — audit trail blijft behouden.
- `last_used_at` wordt max 1x per minuut bijgewerkt om database writes te beperken.

**Consequences:**
- Database-lek onthult geen bruikbare keys (alleen hashes).
- Read-only integraties kunnen geen data muteren, zelfs bij key compromise.
- Gelekte API key kan geen nieuwe keys aanmaken (CRUD vereist sessie-token).
- Geen sliding window expiry op API keys — ze zijn geldig tot expliciet gerevoked of tot `expires_at`.
- Alle bestaande route files zijn aangepast om `X-API-Key` header te accepteren en scope te controleren.
- Client-side UI voor key management moet nog gebouwd worden (macOS, Windows, Android).
