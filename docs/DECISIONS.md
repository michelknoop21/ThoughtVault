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
