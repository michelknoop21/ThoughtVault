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

## DEC-014 — GDPR Compliance in AccountView

**Date:** 2026-03
**Status:** Accepted

**Context:** App Store submission and EU GDPR regulations require user-accessible data export and account deletion.

**Decision:** Add data export (JSON download of all user data) and account deletion flows in `AccountView`. Add `PrivacyInfo.xcprivacy` manifest declaring all data types accessed.

**Consequences:**
- App Store compliant with privacy nutrition labels.
- Backend deletion endpoint implementation is pending — client shows confirmation dialog and calls the endpoint when available.
- Data export produces a JSON file containing task history, transcripts, notes, and profile settings.
