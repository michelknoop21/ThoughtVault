# Codebase Concerns

**Analysis Date:** 2026-06-03

---

## Tech Debt

**Windows SSE client — no reconnection logic:**
- Issue: `windows/src/services/sse.ts` `SSEClient` has no retry/reconnect on connection drop. The Rust `http_sse_stream` command at `windows/src-tauri/src/commands/http.rs:608` streams with a hard 300s timeout and no reconnect loop. If the stream drops mid-transcription (network hiccup, server restart), the task enters a `failed` state in the UI with a message pointing users to "Opnames" tab. In contrast, macOS `SSEClient` in `macos/Services/APIService.swift:1110` reconnects up to 5 times with exponential backoff (2–16s).
- Files: `windows/src/services/sse.ts`, `windows/src-tauri/src/commands/http.rs:608–660`
- Impact: Windows users lose live task progress on any network interruption; task shows as failed even though the server is still processing.
- Fix approach: Add reconnect loop in `SSEClient.connect()` with attempt cap, or handle the error callback in `uploadAndTrack.ts:54–59` to re-initiate the stream after a delay.

**macOS offline queue — identity comparison via JSON encoding:**
- Issue: `macos/Services/OfflineQueue.swift:94–100` finds items by encoding both the candidate and target to JSON and comparing bytes. This is O(n) per remove/replace and fragile — any field ordering difference in `Codable` encoding can silently miss a match. macOS retry limit is hardcoded at 10 (`RecordingViewModel.swift:835`); Windows uses 5 (`offlineQueue.ts:8`). The asymmetry is undocumented and creates confusing behavior parity.
- Files: `macos/Services/OfflineQueue.swift:94–100`, `macos/ViewModels/RecordingViewModel.swift:835`, `windows/src/services/offlineQueue.ts:8`
- Impact: A serialization ordering change (Swift version bump, added field) could cause items to never be removed, growing the queue indefinitely. Retry limit asymmetry means macOS retries for ~1.7 min, Windows for max 1h 42m — wildly different user experience.
- Fix approach: Add an `id: UUID` field to `QueuedItem` and look up by `id` instead of JSON comparison. Align retry counts to a shared constant.

**macOS `APIService.uploadAudio` — streaming multipart via temp file, no WAV validation:**
- Issue: `macos/Services/APIService.swift:390–478` builds the multipart body by streaming through an `OutputStream` to a temp file (`upload_\(UUID).tmp`) in `NSTemporaryDirectory()`, then uploads the temp file. Unlike the Windows path (DEC-059), there is no WAV magic-byte validation before sending, no integrity check between written bytes and actual file size, and no SHA header for server-side correlation. The temp file path does not protect against macOS Spotlight/Time Machine access during the write.
- Files: `macos/Services/APIService.swift:390–478`
- Impact: Corrupted files silently reach the backend on macOS; server returns an obscure error. No diagnostic correlation possible unlike Windows.
- Fix approach: Add `RIFF`/`WAVE` magic-byte check after writing the audio part; add `X-Upload-Sha256` header (SHA-256 of audio bytes); write to `FileManager.default.temporaryDirectory` which is excluded from backup.

**`eprintln!` debug prints in production Rust code:**
- Issue: `windows/src-tauri/src/commands/http.rs:204` and `:281` use `eprintln!` for upload diagnostics. These write to stderr in production builds (visible in Windows Event Log / system console), not a structured log channel.
- Files: `windows/src-tauri/src/commands/http.rs:204, 281`
- Impact: Low severity, but pollutes process stderr in production and leaks internal URL and file paths.
- Fix approach: Replace with `log::info!` / `log::debug!` via the `log` crate (already available transitively via tauri) or Tauri's `tracing` support.

**CHANGELOG lag — v1.0.125 through v1.0.130 undocumented:**
- Issue: `docs/CHANGELOG.md:18` explicitly notes "CHANGELOG loopt achter: laatste inhoudelijke entry was v1.0.124, huidige versie is v1.0.130." Six releases have no changelog entries.
- Files: `docs/CHANGELOG.md`
- Impact: Decision records and context for recent changes (v1.0.125–130) are lost. Future developers and `plan-phase` automation that reads the CHANGELOG for release notes will extract stale information.
- Fix approach: Backfill entries from git log for those 6 versions; enforce one-line-per-commit changelog entries via the post-commit hook.

---

## Known Bugs

**macOS `SystemAudioCapture` timer uses wrong threading pattern (DEC-042 violation):**
- Symptoms: `Timer.scheduledTimer` callback at `macos/Services/SystemAudioCapture.swift:283–292` wraps its body in `Task { @MainActor in }`. DEC-042 (`docs/DECISIONS.md`) explicitly prohibits this pattern for timer callbacks already on the main run loop — it should use `MainActor.assumeIsolated`. The `@Observable` property access on `self.duration` inside the `Task` hop introduces a subtle race window identical to the pattern that caused `_dispatch_assert_queue_fail` crashes documented in DEC-042.
- Files: `macos/Services/SystemAudioCapture.swift:283–292`
- Trigger: Duration updates every second during recording; reproducible under Swift strict concurrency checking.
- Workaround: Functionally works today because `@MainActor`-scheduled tasks usually run on the main thread, but is not safe under Swift 6 strict concurrency.

**macOS combined-mode audio mixing: average-volume formula suppresses quiet speakers:**
- Symptoms: `macos/ViewModels/RecordingViewModel.swift:1261` uses `(micSample + sysSample) * 0.5` (average mix). This halves the volume of both tracks. If one source is silent (e.g., no system audio), the microphone output is also halved, producing a quieter-than-expected transcript. The CLAUDE.md gotcha says "element-wise max over PCM" but the code uses average.
- Files: `macos/ViewModels/RecordingViewModel.swift:1257–1261`
- Trigger: Combined recording mode on macOS where one audio source is dominant.
- Workaround: `audioMixFallbackOccurred` flag in `RecordingViewModel` is set when the mix itself falls back, but not when average suppresses quiet audio.

**Windows SSE: `uploadAndTrack.ts` updates task on wrong ID after upload:**
- Symptoms: `windows/src/services/uploadAndTrack.ts:47` calls `updateBackgroundTask(tempId, { task_id, ... })` using the temp ID to set the real `task_id`. Then `sseClient.connect` at line 52 calls `updateBackgroundTask(task_id, update)` with the real server ID — but the store entry was keyed under `tempId`. If the store's update logic matches by `task_id` field rather than the map key, updates apply correctly; if it matches by key the updates are lost.
- Files: `windows/src/services/uploadAndTrack.ts:47–52`
- Trigger: Every upload on Windows.

---

## Security Considerations

**No code signing — macOS and Windows builds ship unsigned:**
- Risk: macOS Gatekeeper shows "unknown developer" warning; Windows SmartScreen blocks with "Unknown publisher". Users must manually bypass on first launch.
- Files: `docs/ROADMAP-CODE-SIGNING.md`, `.gitlab-ci.yml`, `.github/workflows/build-windows.yml`
- Current mitigation: Road map document exists at `docs/ROADMAP-CODE-SIGNING.md` with full implementation plan. Apple Developer team `XL9KN38ATX` confirmed active.
- Recommendations: Acquire Developer ID Application cert for macOS notarization ($0, included in $99/yr Dev Program). Acquire SSL.com OV eSigner for Windows (~$450/yr). Implement per `docs/ROADMAP-CODE-SIGNING.md`.

**macOS `APIService` enforces HTTPS; Windows does not:**
- Risk: `macos/Services/APIService.swift:165` throws `URLValidationError.httpsRequired` if the server URL is not HTTPS. `windows/src/services/api.ts:134–146` reads `server_url` from persistent store and falls back to the hardcoded `https://n8n.prezent.nl/tstudio/api` — no HTTPS enforcement if the user sets a custom `http://` server URL. `X-User-Token` auth header would be sent in plaintext.
- Files: `windows/src/services/api.ts:134–146`, `windows/src/pages/SettingsPage.tsx`
- Current mitigation: Default URL is HTTPS; custom server URL is an advanced setting.
- Recommendations: Add HTTPS validation in `api.ts` getter, same as macOS `validatedBaseURL()`.

**`temporary-exception.audio-unit-host` entitlement may block notarization:**
- Risk: `docs/ROADMAP-CODE-SIGNING.md:119` notes this entitlement can cause Apple notarization rejection. It is currently present in `macos/TranscriptStudio.entitlements` (referenced in the roadmap).
- Files: `macos/TranscriptStudio.entitlements`, `docs/ROADMAP-CODE-SIGNING.md:119`
- Current mitigation: Builds are ad-hoc signed; notarization not yet attempted.
- Recommendations: Audit whether the entitlement is still needed before attempting notarization.

**Windows password stored in OS Credential Manager (DEC-050):**
- Risk: `windows/src/stores/authStore.ts` stores email + password via `store_credential`/`load_credential` Tauri commands for "Onthoud mij". Windows Credential Manager is not end-to-end encrypted — any process with the same user context can read it.
- Files: `windows/src/stores/authStore.ts`, `windows/src/pages/LoginPage.tsx`
- Current mitigation: Uses Windows Credential Manager, not plaintext storage. Standard desktop credential pattern.
- Recommendations: Consider storing only the long-lived token (365 days) rather than plaintext password, reducing credential exposure scope.

---

## Performance Bottlenecks

**Windows upload: in-memory load for ≤200 MB — peak RAM spike:**
- Problem: `windows/src-tauri/src/commands/http.rs:166–180` loads the entire file into memory for files ≤200 MB (`tokio::fs::read`). A 200 MB recording causes a ~200 MB heap allocation inside the Tauri process.
- Files: `windows/src-tauri/src/commands/http.rs:164–180`
- Cause: Intentional trade-off from DEC-059 to eliminate the Content-Length/body race condition. Streaming was the source of the 422 bug.
- Improvement path: Accepted and documented in DEC-059. No action until a user hits the 200 MB wall. Files >200 MB already stream from the integrity-checked temp copy.

**macOS multipart upload: two-pass I/O (stream to temp, then upload):**
- Problem: `macos/Services/APIService.swift:414–477` writes the full multipart body to a temp file via `OutputStream`, then uploads that temp file. Large recordings are read twice (once to build multipart, once to upload), and the temp file can be up to 500 MB.
- Files: `macos/Services/APIService.swift:414–477`
- Cause: `URLSession` upload tasks require a file URL for large bodies; multipart boundary wrapping necessitates writing first.
- Improvement path: Use `URLSessionUploadTask` with streaming multipart construction, or add a size-based in-memory path for files ≤200 MB matching the Windows strategy.

**Client-side pagination removed — no server-side pagination for large transcript counts:**
- Problem: DEC-045 removed pagination from `getTranscripts()` on both platforms; single request returns all transcripts. Noted as "not suitable if transcript counts grow to thousands per user."
- Files: `macos/Services/APIService.swift` (`getTranscripts`), `windows/src/services/api.ts`
- Cause: Pagination added complexity for typical user counts (tens to low hundreds).
- Improvement path: Re-introduce cursor-based pagination when any user exceeds ~500 transcripts.

---

## Fragile Areas

**n8n Claude proxy — single point of failure for `handleiding` profile:**
- Files: `docs/DECISIONS.md` (DEC-057)
- Why fragile: DEC-057 states "Claude proxy (`n8n_claude_code:3100`) moet beschikbaar zijn voor handleiding-verwerking; Ollama als fallback is niet geïmplementeerd." If the `n8n_claude_code` container goes down, all `handleiding` notule generation silently fails — the n8n workflow has no fallback path for that profile.
- Safe modification: Any change to the n8n "Notule Generator" workflow (`Iq3AAf8Vk8eQ9dcZ`) must preserve the IF-node routing logic. Profile routing depends on `profile_id` being sent in webhook payload from 4 backend code locations (`transcription_service.py`, `transcription.py` ×2, `transcripts.py`).
- Test coverage: No automated tests for the n8n workflow routing logic.

**YouTube captions pipeline — depends on internal YouTube API:**
- Files: `backend/services/youtube_service.py`, `docs/DECISIONS.md` (DEC-044)
- Why fragile: Primary path uses `youtube-transcript-api` v1.2.4 which scrapes YouTube's internal transcript endpoint — same fragility as yt-dlp, acknowledged in DEC-044 ("kan breken bij YouTube-wijzigingen"). The secondary Google OAuth path (DEC-041) and yt-dlp fallback exist but yt-dlp is documented as "fragile (yt-dlp breaks on YouTube changes, bot detection)".
- Safe modification: Do not upgrade `youtube-transcript-api` without integration-testing against live videos. Monitor for HTTP 429 or bot-detection responses which indicate IP-based blocking.
- Test coverage: None — backend tests not present in the frontend repo.

**macOS `LocalTranscriptStore` — `try!` crash on in-memory fallback failure:**
- Files: `macos/Services/LocalTranscriptStore.swift:31`
- Why fragile: The primary `ModelContainer` init is inside a `do/catch` that falls back to an in-memory store via `try!`. If the in-memory `ModelContainer` init also fails (e.g., schema migration error on model change), the app crashes with no user-facing message.
- Safe modification: Wrap the fallback `try!` in another `do/catch` with a user-facing alert.
- Test coverage: None for schema migration paths.

**`extractStyles()` regex uses `try!` on static pattern:**
- Files: `macos/Views/NotuleResultView.swift:605`
- Why fragile: `try! NSRegularExpression(pattern: ...)` — if the pattern string is ever modified and introduces a syntax error, the app crashes at startup. The pattern is complex (`<style[^>]*>[\s\S]*?</style>`).
- Safe modification: Replace with `try?` and a graceful no-op fallback, or compile the regex as a static constant.
- Test coverage: None.

**CI/CD depends on a single Mac runner being online:**
- Files: `.gitlab-ci.yml`, `docs/DECISIONS.md` (DEC-055)
- Why fragile: DEC-055 explicitly states "Geen builds mogelijk als Mac offline is." Michel's personal Mac is the sole macOS + Android build runner. If it is sleeping, offline, or the `gitlab-runner` process has crashed, all macOS and Android release builds block.
- Safe modification: Any `.gitlab-ci.yml` change must be tested with the runner available. The `deploy` job SSHs to EC2 — SSH key rotation on either side silently breaks deploys.
- Test coverage: No CI pipeline tests; pipeline is verified by running a dev release.

**Windows CI runner depends on `C:\Users\michel` path hardcoding:**
- Files: `.gitlab-ci.yml:177, 233`, `docs/DECISIONS.md` (DEC-058)
- Why fragile: The Windows GitLab runner runs as `SYSTEM`; Rust, SSH keys, and WiX tools fall back to `C:\Users\michel` when `$env:USERPROFILE` resolves to the system profile. If the Windows PC username changes or a different machine is used, all Windows CI builds fail.
- Safe modification: Parameterise the fallback path as a GitLab CI variable rather than hardcoding `C:\Users\michel`.

---

## Scaling Limits

**Single EC2 GPU instance — no horizontal scaling:**
- Current capacity: One `n8n_transcript_studio` container on `3.69.205.209` (AWS EC2 GPU). Queue manager serialises transcription jobs.
- Limit: Under sustained concurrent load, jobs queue up indefinitely. No autoscaling, no queue depth monitoring exposed to clients.
- Scaling path: `docs/PLAN-MULTI-INSTANCE.md` documents a multi-instance deployment strategy for 1–10 customers (still unimplemented as of 2026-06-03).

---

## Dependencies at Risk

**`youtube-transcript-api` v1.2.4 — scrapes YouTube internal endpoint:**
- Risk: No stable API contract; can break on any YouTube frontend deploy. Primary captions path for all YouTube transcription.
- Impact: YouTube transcription fails for all users; falls back to yt-dlp (slow, GPU-intensive, also fragile).
- Migration plan: Maintain Google OAuth path (DEC-041) as secondary; monitor library releases. Consider self-hosting a caption fetch proxy with retry logic.

**`yt-dlp` — YouTube ToS and bot detection:**
- Risk: Documented in DEC-041 as "fragile (yt-dlp breaks on YouTube changes, bot detection)" and "technically in conflict with YouTube's ToS."
- Impact: yt-dlp fallback path fails; no YouTube transcription available.
- Migration plan: Accept as last-resort fallback. Keep updated (`yt-dlp --update`). Monitor `youtube-transcript-api` library health.

---

## Missing Critical Features

**Windows + Android: no Google OAuth for YouTube captions:**
- Problem: Google OAuth (DEC-041) for YouTube captions is macOS-only. `docs/DECISIONS.md:183` notes "Windows and Android will follow later — backend is ready." Without it, Windows/Android users cannot use the Google API fallback path when `youtube-transcript-api` is blocked.
- Blocks: Windows/Android users have no YouTube captions fallback if anonymous path fails.

**Windows + Android: no video call auto-detection:**
- Problem: `VideoCallDetectionService` (`macos/Services/VideoCallDetectionService.swift`) is macOS-only. DEC-040 notes Windows/Android equivalents exist but are not implemented.
- Blocks: Windows/Android users must manually start recording for ad-hoc video calls.

**macOS local mode: authentication gate is correctly bypassed but profile load still hits backend:**
- Problem: `macos/App/ContentView.swift:81` correctly bypasses login when `isLocalMode`. However `macos/ViewModels/RecordingViewModel.swift:158–161` calls `loadDefaultProfile` and `checkFeatures` on init unconditionally — these hit the backend API. In local mode with no server configured, these fail silently (catching errors), but in a pure offline scenario with no network, they generate unnecessary error logs and delay profile availability.
- Files: `macos/ViewModels/RecordingViewModel.swift:158–161`, `macos/App/ContentView.swift:89–92`
- Impact: Local mode shows "Geen profiel geselecteerd" briefly until the API call fails and the fallback profile is used.

---

## Test Coverage Gaps

**No tests for macOS `OfflineQueue` item identity matching:**
- What's not tested: The JSON-encoding identity comparison in `indexOfItem` (`macos/Services/OfflineQueue.swift:94–100`).
- Files: `macos/Services/OfflineQueue.swift`
- Risk: A `Codable` encoding order change (e.g., Swift version update) causes silent queue item leak.
- Priority: Medium

**No tests for Windows SSE reconnection (because there is none):**
- What's not tested: SSE stream drop-and-recover behaviour on Windows.
- Files: `windows/src/services/sse.ts`, `windows/src/services/uploadAndTrack.ts`
- Risk: Users see tasks as permanently failed after any network interruption.
- Priority: High

**No tests for `extractStyles()` HTML CSS extraction:**
- What's not tested: Edge cases in the `<style>` block regex (nested `<style>`, malformed tags, multiple blocks).
- Files: `macos/Views/NotuleResultView.swift:600–630`
- Risk: CSS not applied in WKWebView for edge-case handleiding HTML; `try!` crash if pattern modified.
- Priority: Low

**No tests for macOS audio mixing (`mixAudioFiles`):**
- What's not tested: Buffer length mismatch (mic longer than system audio), both sources silent, format mismatch.
- Files: `macos/ViewModels/RecordingViewModel.swift:1216–1279`
- Risk: Mix fallback to mic-only silently when system audio buffer is shorter; average formula halves volume.
- Priority: Medium

**No integration tests for backend title extraction dual-path:**
- What's not tested: The two `_extract_title_from_html` code paths in `app.py` and `transcription.py` staying in sync (documented as a gotcha in `CLAUDE.md`).
- Files: Backend `app.py:496`, `transcription.py:103` (not in this repo)
- Risk: A future backend change to one path that misses the other, causing inconsistent title extraction for regenerated vs. auto-generated notulen.
- Priority: High

---

*Concerns audit: 2026-06-03*
