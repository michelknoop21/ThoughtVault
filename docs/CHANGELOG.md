# TranscriptStudio — Changelog

All notable changes to the TranscriptStudio project (macOS, Windows, Android clients, web app, and backend) are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2026-03-19] — Windows audio resampling + upload limit 250 MB

### Fixed
- **Windows 48 kHz recording bloat** (`windows/src-tauri/src/audio/recorder.rs`): Windows audio devices typically output at 48 kHz. Previously, the WAV file was written at device rate (48 kHz), producing ~500 MB files for 1.5 hour meetings. Added `StreamingResampler` struct that downsamples in the audio callback itself using linear interpolation — no post-processing, no extra memory allocation, no CPU spike after recording. `fractional_pos` state carries across callbacks for gapless chunk-boundary resampling.
- **WAV spec forced to 16 kHz**: Both mic and loopback WAV writers now always use `TARGET_SAMPLE_RATE` (16000 Hz) regardless of device rate. Resampling happens in real-time within `build_input_stream_i16()`, `build_input_stream_f32()`, and both loopback stream callbacks.
- **Audio level calculation preserved**: Level metering runs on pre-resample samples (device rate) for accurate visualization. `samples_written` tracking counts resampled samples for correct duration logging.

### Changed
- **Upload limit raised to 250 MB** (was 120 MB) across all layers:
  - Backend: `config.py:96` `max_upload_size = 250 * 1024 * 1024`
  - Windows: `http.rs:106` `MAX_UPLOAD_SIZE = 250 * 1024 * 1024` + error message
  - macOS: `APIService.swift:386` `maxBytes = 250 * 1024 * 1024` + `APIError.fileTooLarge` message
  - macOS: `Models.swift:611` `UploadFailureReason.fileTooLarge` description
  - Docs: `API.md` all 120 MB references updated

### Decisions
- DEC-051: Real-time streaming resampler for Windows audio

### Notes
- Root cause: Windows WASAPI devices don't support 16 kHz directly — they clamp to their minimum (typically 48 kHz). Result: 48000 × 2 bytes × 5400 sec = 518 MB.
- After fix: 16000 × 2 bytes × 5400 sec = ~165 MB — fits within the new 250 MB limit.
- The existing `mix_wav_files()` resampling logic remains as a safety net but will be a no-op since both WAVs are now 16 kHz.
- Backend deployed and verified: `max_upload_size_mb: 250.0` in health check.
- Both `cargo check` and `xcodebuild` pass cleanly.

---

## [2026-03-18] — Streaming file upload (Windows memory fix)

### Changed
- **Streaming upload** (`windows/src-tauri/src/commands/http.rs:92-108`): Replaced `tokio::fs::read()` (loads entire WAV into `Vec<u8>`) with `ReaderStream::with_capacity(file, 64KB)` + `Part::stream_with_length()`. File is now streamed in 64 KB chunks during upload instead of buffered entirely in memory. A 100 MB WAV previously consumed 100 MB of heap; now uses ~64 KB.
- **File size check before open** (`http.rs:107-113`): Size validation now uses `metadata.len()` instead of reading the file first — avoids allocating memory for oversized files that would be rejected anyway.
- **Added `tokio-util` dependency** (`Cargo.toml`): `tokio-util = { version = "0.7", features = ["io"] }` for `ReaderStream`.

### Notes
- Root cause: Activity Monitor showed WebView2 process at 538 MB during uploads. Main contributor was `tokio::fs::read()` loading the entire WAV into memory.
- Expected memory reduction: 100-200 MB during active uploads, bringing total app memory from ~628 MB to ~400-450 MB (rest is WebView2/Chromium baseline).
- All 6 existing upload tests pass with the streaming implementation.

---

## [2026-03-18] — Auto-login / "Onthoud mij" feature (Windows)

### Added
- **"Onthoud mij" checkbox** (`windows/src/pages/LoginPage.tsx:240-247`): Checkbox between password field and submit button. When checked, email + password are saved to Windows Credential Manager after successful login (including 2FA completion). Checkbox state persisted in Zustand localStorage.
- **Auto-login on startup** (`windows/src/stores/authStore.ts:105-213`): `loadTokenFromKeyring()` expanded to 4-step flow: (1) load existing token + validate via `getProfiles()`, (2) check `remember_me` flag in keyring, (3) load saved email + password, (4) call `api.login()` automatically. On 2FA accounts, auto-submits credentials — user sees only the 2FA code input.
- **`pendingTwoFactor` state** (`authStore.ts:18`): Stores `{ tempToken, email }` when auto-login hits 2FA. LoginPage picks this up on mount and jumps to 2FA code view.
- **`saveCredentials()` / `clearSavedCredentials()`** (`authStore.ts:72-94`): Store/remove `saved_email`, `saved_password`, `remember_me` keys in OS keyring via existing Tauri commands.
- **`isNetworkError()` helper** (`authStore.ts:31-45`): Detects transient network errors (timeout, DNS, connection refused, offline) to distinguish from auth failures during auto-login.
- **`.form-checkbox` CSS** (`globals.css`): Inline flex layout with branded accent color.

### Changed
- **`logout()` clears saved credentials** (`authStore.ts:98-103`): Explicit logout removes all saved credentials from keyring and resets `rememberMe` to `false`.
- **`partialize` includes `rememberMe`** (`authStore.ts:219`): Checkbox state persisted to localStorage alongside user info.

### Edge Cases
- **Network offline during auto-login**: Credentials kept (transient). Old token preserved so user can keep working.
- **Password changed server-side**: Auth error → saved credentials cleared, login page shown.
- **2FA accounts**: Auto-submits email/password, shows only 2FA code screen. Credentials stay saved.
- **Corrupt keyring data**: Partial credentials → clear and show login page.
- **Token invalid without remember-me**: Old token kept for graceful degradation until real request fails.

### Decisions
- DEC-050: Auto-login via OS keyring credentials

### Notes
- No Rust changes needed — uses existing `store_credential`, `load_credential`, `delete_credential` commands.
- Keyring keys: `auth_token` (existing), `saved_email`, `saved_password`, `remember_me`.
- TypeScript compiles cleanly.

---

## [2026-03-18] — Duidelijke upload foutmeldingen across all layers

### Added
- **Gestructureerde error codes (backend)** (`src/insanely_fast_whisper_api/app/errors.py`): Nieuw gecentraliseerd error module met `raise_api_error()`, `APIError` (extends HTTPException), `api_error_response()`, en `validate_audio_extension()`. Definieert 11 gestructureerde error codes met Nederlandse user-facing messages. Standaard response format: `{"error_code": "...", "message": "...", "detail": "..."}`.
- **`UploadFailureReason.networkError` (macOS)** (`macos/Models/Models.swift`): Nieuwe case voor netwerk-gerelateerde upload failures met Nederlands beschrijving en `wifi.exclamationmark` icoon.
- **Retry sheet voor upload failures (macOS)** (`macos/Views/RecordingView.swift`): `.sheet` modifier voor `showRetrySheet` — presenteert `ReprocessSheet` in retry mode wanneer upload faalt.
- **Permanently failed uploads (Windows)** (`windows/src/stores/uploadQueueStore.ts`): `permanentlyFailed` array met `addPermanentlyFailed()` en `clearPermanentlyFailed()` actions. Na 50 retries worden items gerapporteerd met bestandsnaam.
- **Permanently failed banner (Windows)** (`windows/src/App.tsx`): `OfflineQueueBanner` toont waarschuwingsbanner voor permanent gefaalde uploads met bestandsnaam en dismiss-knop.

### Changed
- **Backend error responses gestandaardiseerd** (`services/auth_service.py`, `middleware/rate_limiting.py`, `routes/transcription.py`): ~30 raw `HTTPException` calls vervangen door `raise_api_error()` met gestructureerde error codes. 500 errors lekken geen raw exception strings meer naar clients. Error codes: `file_too_large`, `queue_unavailable`, `server_error`, `not_found`, `access_denied`, `auth_required`, `validation_error`, `audio_format_unsupported`, `rate_limit_exceeded`.
- **Audio format validatie (backend)** (`routes/transcription.py`): Extension allowlist voor uploads — ongeldige formaten worden geweigerd met `audio_format_unsupported` error code.
- **File size limiet verlaagd naar 120 MB** (`macos/Services/APIService.swift`, `windows/src-tauri/src/commands/http.rs`): Client-side validatie op beide platformen verlaagd van 200 MB naar 120 MB, consistent met backend limiet.
- **`APIError.httpError` uitgebreid (macOS)** (`macos/Services/APIService.swift`): Nu 3 argumenten: `(statusCode, message, errorCode)`. Nieuwe `extractErrorInfo()` parseert gestructureerde `error_code` + `message` van backend met fallback naar legacy formaten. Error descriptions actionable in het Nederlands.
- **`UploadFailureReason` descriptions (macOS)** (`macos/Models/Models.swift`): Alle descriptions bijgewerkt naar actionable Nederlands (120 MB limiet vermeld, verbindingsadvies, herstart suggestie).
- **Upload retry limiet met user-facing message (macOS)** (`macos/ViewModels/RecordingViewModel.swift`): Queue processing incrementeert `retryCount` bij failure via `replaceItem()`, verwijdert items na 10 retries met user-visible message. Auth error tijdens upload zet `offlineStatusMessage`.
- **Structured error parsing (Windows)** (`windows/src/services/api.ts`): `request()` en beide upload methods parsen `error_code` van backend responses en gebruiken `message` direct. Fallback naar status-code-based Nederlandse messages.
- **Client-side file size check (Windows Rust)** (`windows/src-tauri/src/commands/http.rs`): 120 MB check voordat bestand wordt gelezen. Netwerk errors produceren specifieke Nederlandse messages per error type (timeout, connection refused, generiek).
- **SSE connection-lost message (Windows)** (`windows/src/hooks/useGlobalRecordingHandler.ts`): Bijgewerkt met actionable Nederlands advies.

### Decisions
- DEC-049: Gestructureerde error codes across all layers

### Notes
- Backend error module definieert 11 error codes: `auth_required`, `read_only_key`, `forbidden`, `rate_limit_exceeded`, `file_too_large`, `queue_unavailable`, `server_error`, `not_found`, `access_denied`, `validation_error`, `audio_format_unsupported`.
- macOS retry limiet: 10 pogingen. Windows retry limiet: 50 pogingen. Verschil door platform-specifieke offline queue implementatie.
- File size limiet is nu consistent 120 MB op alle lagen (backend + beide clients).

---

## [2026-03-17] — Never auto-logout + upload queue progress banner

### Fixed
- **CRITICAL: Recording loss on 401** — `RecordingPage.tsx:285` classified HTTP 401 as a client error (`msg.includes("HTTP 4")`), preventing the recording from being enqueued for retry. The recording was silently lost. Fixed by excluding 401 from client error classification: `const isClientError = msg.includes("HTTP 4") && !msg.includes("HTTP 401")`.
- **Auto-logout on 401 (Windows)** — `api.ts:204` called `useAuthStore.getState().logout()` on every 401 response, deleting the token from keyring. Replaced with: retry the request once after 2 seconds, then throw error without logging out. Token stays in keyring.
- **Auto-logout on 401 (macOS)** — `AuthViewModel.swift:325` observer on `.authDidInvalidate` called `self.logout()` after grace period. Changed to log-only — user stays authenticated indefinitely until explicit logout.

### Changed
- **Offline queue retry limit** — `offlineQueue.ts:58`: max retries increased from 3 → 50. Items also removed if the source file no longer exists on disk (`@tauri-apps/plugin-fs` `exists()` check).
- **Upload queue progress** — `offlineQueue.ts` now uses `api.uploadRecordingWithProgress()` with XHR progress callbacks, feeding `uploadQueueStore.ts`.
- **OfflineQueueBanner** — `App.tsx:36-98`: Redesigned from plain text to show filename, file size, progress bar with percentage, upload speed (bytes/sec), and queue position (e.g. "1/3").
- **RecordingPage enqueue metadata** — `RecordingPage.tsx:287`: Enqueue now includes `file_size_bytes` (via `stat()`), `file_name` for display in the progress banner.

### Added
- **`uploadQueueStore.ts`** — New Zustand store tracking: `currentItem`, `progress` (0-100), `uploadSpeed` (bytes/sec), `items` (full queue snapshot). Used by `OfflineQueueBanner` and `processQueue()`.
- **`QueuedUpload` metadata fields** — `types.ts`: Added optional `file_size_bytes`, `recording_duration_secs`, `file_name`, `last_error` to the offline queue item interface (backwards-compatible).
- **Token validation at startup (Windows)** — `App.tsx` `ProtectedRoutes`: validates token via `getProfiles()` on mount. On failure shows non-disruptive toast via `useToast` — never redirects to login.
- **Token validation at startup (macOS)** — `AuthViewModel.swift` `checkAuthState()`: validates token via `getProfiles()` in background Task. On failure logs warning — user stays authenticated.
- **Auth error → offline queue (macOS)** — `RecordingViewModel.swift:514`: on `APIError.sessionExpired` during upload, recording is enqueued to `OfflineQueue` before showing retry sheet, preventing recording loss.

### Decisions
- DEC-048: Never auto-logout after authentication

### Notes
- **Kernprincipe**: Na inloggen wordt de gebruiker NOOIT meer uitgelogd, tenzij ze zelf uitloggen. Backend heeft 365-dagen token expiry.
- The 401 retry in `api.ts` uses a simple 2-second delay (not exponential backoff) — sufficient for transient server issues.
- Both macOS and Windows builds verified: `xcodebuild` BUILD SUCCEEDED, `npx tsc --noEmit` clean.

---

## [2026-03-17] — Documentation maintenance: archive old entries, fix version

### Changed
- **CHANGELOG.md** refactored: Entries from 2026-02-27 to 2026-03-12 archived to `docs/archive/CHANGELOG-2026-02-27-to-2026-03-12.md`. Main changelog reduced from 865 → ~425 lines.
- **README.md**: Fixed stale version reference (1.0.82 → 1.0.84).

---

## [2026-03-17] — Backend bugfix: reset_to_original parameter missing

### Fixed
- **`update_transcript()` crash on `reset_to_original`** (`backend/repositories/task_repo.py:302`): `PUT /transcripts/{task_id}` passed `reset_to_original=update.reset_to_original` to `update_transcript()`, but the function signature did not accept that parameter. Result: `TypeError: update_transcript() got an unexpected keyword argument 'reset_to_original'` on every transcript update request. Root cause: the route in `transcripts.py:161` was updated to support `reset_to_original` (clearing edited version to revert to original transcript), but the corresponding repository function was never updated with the new parameter.
- **Fix**: Added `reset_to_original: bool = False` parameter to `update_transcript()` in `task_repo.py`. When `True`, sets `edited_transcription = None` and `edited_at = None`, effectively reverting the transcript to the original Whisper output. When `False` (default), existing behavior preserved.

### Notes
- Deployed to production: `task_repo.py` synced to server, container restarted. Verified clean startup.
- This bug affected all platforms (macOS, Windows, web) — any transcript edit/update would fail with HTTP 500.

---

## [2026-03-17] — YouTube proxy support and bot detection resilience

### Added
- **YouTube proxy setting** (`macos/Views/AdminView.swift`, `windows/src/pages/AdminPage.tsx`): New "Proxy (optioneel)" field in Admin > Instellingen > YouTube section. Accepts SOCKS5 or HTTP proxy URL (e.g. `socks5://user:pass@host:port`) to route yt-dlp and youtube-transcript-api requests through a proxy, bypassing AWS IP-based YouTube blocks.
- **`youtube_proxy` field** (`macos/Services/APIService.swift:AdminSettingsResponse`, `windows/src/services/api.ts`): Added to admin settings GET/POST on both platforms.

### Changed
- **Backend YouTube service** (commit message, backend changes in separate repo): oEmbed metadata fallback when yt-dlp is blocked by bot detection. Proxy support for both yt-dlp subprocess calls and `youtube-transcript-api` library. User-friendly Dutch error messages for YouTube bot detection scenarios. Anonymous captions decoupled from yt-dlp metadata dependency — metadata now fetched via oEmbed API (`https://noembed.com/embed`) as fallback when yt-dlp `--dump-json` fails due to bot detection.

### Decisions
- See DEC-047 in [DECISIONS.md](DECISIONS.md) for the YouTube proxy and bot detection resilience rationale.

### Notes
- Backend changes deployed separately — this changelog documents the client-side admin UI changes committed in this repo.
- The proxy field is optional — when empty, requests go directly without proxy (existing behavior).

---

_Entries from 2026-03-15 to 2026-03-16 archived to [archive/CHANGELOG-2026-03-15-to-2026-03-16.md](archive/CHANGELOG-2026-03-15-to-2026-03-16.md)._
_Entries from 2026-03-13 to 2026-03-14 archived to [archive/CHANGELOG-2026-03-13-to-2026-03-14.md](archive/CHANGELOG-2026-03-13-to-2026-03-14.md)._
_Older entries (2026-02-27 to 2026-03-12) archived to [archive/CHANGELOG-2026-02-27-to-2026-03-12.md](archive/CHANGELOG-2026-02-27-to-2026-03-12.md)._
