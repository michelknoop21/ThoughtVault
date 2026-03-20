# TranscriptStudio — Architectural Decision Records

_Append-only log. Each entry records context, decision, and consequences._

_Decisions DEC-029 through DEC-038 archived to [archive/DECISIONS-DEC-029-to-DEC-038.md](archive/DECISIONS-DEC-029-to-DEC-038.md)._

---

## DEC-054 — Background Uploads with Global ProcessingBar

**Date:** 2026-03-20
**Status:** Accepted

**Context:** After a recording stopped, `uploadFile()` kept `recordingState = .uploading` until the upload completed, blocking the entire RecordingView. The user couldn't start a new recording, navigate to other tabs, or use the app at all during uploads — which could take minutes for large files over slow connections. Windows already had background task tracking via `backgroundTasks` in the Zustand store and a `ProcessingBar` component. macOS had no equivalent.

**Decision:** Make `uploadFile()` fire-and-forget: create a temporary `TranscriptTask` (ID prefixed with `upload-`) in `activeTasks`, set `recordingState = .idle` immediately, and run the upload in a background `Task`. Upload progress updates the temp task via `updateTask()`. On success, the temp task is replaced with the real server task and SSE monitoring begins. On failure, the task shows the error message inline. New `ProcessingBar.swift` component is placed in `ContentView.detailView` (above tab content), visible on all tabs. It renders each active task with filename, status, progress bar, percentage, and cancel/dismiss actions.

**Consequences:**
- User can immediately start a new recording or navigate after stopping — no more blocked UI.
- Upload progress and errors are visible on every tab via the global ProcessingBar.
- `uploadProgressView` removed from RecordingView (no longer needed).
- `cancelUpload()` now accepts an optional task ID to cancel specific uploads.
- The `uploadProgress` property on RecordingViewModel is no longer used by the upload flow but retained for widget compatibility.
- Files changed: `RecordingViewModel.swift` (background upload, `updateTask()`), `ProcessingBar.swift` (new), `ContentView.swift` (ProcessingBar placement), `RecordingView.swift` (removed uploadProgressView).

---

## DEC-039 — Onafhankelijke YouTube Profielselectie (Optie B)

**Date:** 2026-03-15
**Status:** Superseded (2026-03-16) — teruggedraaid naar gedeeld profiel. Separate YouTube profielselectie bleek onnodige complexiteit; gebruikers verwachten hetzelfde profiel voor alle transcriptie-methodes.

**Context:** De YouTube transcriptie card en de opname card deelden dezelfde profielselectie (`selectedProfile` op macOS, `selectedProfileId` op Windows). Dit leidde tot verwarring: als een gebruiker profiel "Technisch" selecteerde voor een YouTube transcriptie, veranderde ook het profiel voor de volgende opname — en vice versa. De twee cards hebben fundamenteel verschillende use cases (live opname vs. URL-gebaseerde transcriptie) en moeten onafhankelijk configureerbaar zijn.

**Decision:** Optie B gekozen: elke card krijgt een eigen profiel-state. macOS: `youtubeSelectedProfile: Profile?` in `RecordingViewModel.swift`, met eigen `youtubeProfileSection` view en `youtubeProfileBinding` in `RecordingView.swift`. Windows: `youtubeProfileId: string` in `recordingStore.ts`, met eigen `profile-chip` buttons in `RecordingPage.tsx`. Beide worden geïnitialiseerd vanuit het default profiel als fallback. `submitYouTubeURL()` gebruikt het YouTube-specifieke profiel.

**Consequences:**
- Gebruikers kunnen een ander profiel kiezen voor YouTube transcriptie dan voor opname, zonder wederzijdse interferentie.
- Beide profiel-states worden onafhankelijk geïnitialiseerd vanuit het default profiel — geen extra configuratie nodig.
- De YouTube card toont een rood accent-badge met de geselecteerde profielnaam, visueel onderscheidend van de opnamekaart.
- Android heeft nog geen YouTube feature — wanneer die wordt toegevoegd, moet dezelfde onafhankelijke state-aanpak gevolgd worden.

---

## DEC-040 — Video Call Detection via KVO Camera + Running App Matching

**Date:** 2026-03-16
**Status:** Accepted

**Context:** TranscriptStudio detected only scheduled meetings via calendar integration (EventKit / Microsoft Graph). Ad-hoc video calls — someone calls you on Teams without a calendar invite — were not detected. Users had to manually navigate to the recording tab and start recording, missing the first minutes of unplanned calls. The goal was to show an automatic "Start opname" notification when a video call begins, reusing the existing `CallAlertView` and `MeetingNotificationService` infrastructure.

**Decision:** Combine two signals in a new `VideoCallDetectionService` (`macos/Services/VideoCallDetectionService.swift`): (1) KVO observation on `AVCaptureDevice.default(for: .video)?.isInUseByAnotherApplication` — fires when any app activates the camera, (2) `NSWorkspace.shared.runningApplications` matched against a static dictionary of known video app bundle IDs (Teams, Zoom, FaceTime, Slack, Webex, Discord) and browser bundle IDs (Safari, Chrome, Edge, Brave, Arc, Firefox). Both signals must be true to trigger detection. A three-state machine (`idle → detected → cooldown`) with 60-second cooldown prevents re-triggering on brief camera cycles. Synthetic `CalendarEvent` objects (id prefixed with `videocall-`) are posted via `NotificationCenter` and fed into the existing `CallAlertView` and `MeetingNotificationService` paths unchanged. Fallback: when `AVCaptureDevice.default(for: .video)` returns nil (sandbox restriction without camera entitlement), the service degrades to a 10-second poll on running apps, alerting after 30 seconds of continuous video app presence.

**Consequences:**
- Both `isInUseByAnotherApplication` and `NSWorkspace.shared.runningApplications` are available in sandboxed macOS apps without additional entitlements — no camera stream access needed.
- Browser-based video calls (Google Meet, Teams web) trigger detection via camera + browser match, but can false-positive on non-video WebRTC sites. Acceptable: dismiss in 1 click.
- Audio-only calls are not detected (no camera activation). Calendar integration handles scheduled audio calls.
- Calendar dedup prevents duplicate alerts when a scheduled meeting coincides with a detected video call.
- Toggle via `@AppStorage("videoCallDetectionEnabled")` in Settings → Agenda section (default: on).
- No changes to `CallAlertView`, `MeetingNotificationService`, or `CalendarEvent` struct — full infrastructure reuse.
- Windows and Android do not yet have this feature; when added, similar process-monitoring APIs exist (`WTSEnumerateProcesses` on Windows, `ActivityManager` on Android).

---

## DEC-041 — YouTube Hybride Aanpak: Captions API + yt-dlp Fallback

**Date:** 2026-03-16
**Status:** Accepted

**Context:** YouTube transcription used yt-dlp to download audio and run it through Whisper. This was fragile (yt-dlp breaks on YouTube changes, bot detection), slow (~15 min: download + GPU transcription), GPU-intensive, and technically in conflict with YouTube's ToS. Most YouTube videos already have captions (manual or auto-generated) that can be retrieved in ~1 second via the YouTube Data API v3, requiring no GPU at all.

**Decision:** Implement a hybrid approach in `backend/services/youtube_service.py` and `backend/routes/transcription.py`. When the client sends an `X-Google-Token` header with the YouTube request, the backend first tries the YouTube Data API v3 (`captions.list` + `captions.download`) to fetch existing captions. Caption track priority: `nl standard > nl ASR > en standard > en ASR > any standard > any ASR`. If captions are found, the text is fed directly into the notule pipeline (same path as `/transcribe-text`: `split_into_chunks()` → `qm.enqueue()`) with `source_type: "youtube_captions"`. If no captions are available, the existing yt-dlp + Whisper path is used as fallback with `source_type: "youtube"`. Google OAuth (PKCE) is required — implemented in `macos/Services/GoogleAuthService.swift` following the `MicrosoftGraphService` pattern. The `/features` endpoint exposes `google_oauth_configured` and `google_oauth_client_id_macos` for client discovery.

**Consequences:**
- Caption retrieval completes in ~1 second vs ~15 minutes for yt-dlp + Whisper. Zero GPU usage for captioned videos.
- YouTube Data API quota: 250 units/video (`captions.list` 50 + `captions.download` 200). Default 10,000 units/day = ~40 videos/day.
- Google OAuth scope `youtube.force-ssl` is required for `captions.download`. Users must connect their Google account in the YouTube card UI.
- Backward compatible: without `X-Google-Token`, the endpoint falls back to the existing yt-dlp path unchanged.
- Admin configures Google OAuth Client IDs via Admin > Instellingen (same pattern as MS365 OAuth).
- Windows and Android will follow later — backend is ready (accepts `google_oauth_client_id_windows` setting).
- Refresh tokens stored in macOS Keychain via `KeychainService` (key: `googleRefreshToken`). Access tokens are in-memory (1 hour validity).

---

## DEC-042 — DispatchQueue.main.async voor KVO Callbacks in @Observable Classes

**Date:** 2026-03-16
**Status:** Accepted

**Context:** `VideoCallDetectionService` is een `@Observable` class (niet `@MainActor`) die KVO gebruikt op `AVCaptureDevice.isInUseByAnotherApplication`. KVO callbacks worden geleverd op willekeurige dispatch queues — in de praktijk `com.apple.root.default-qos` (concurrent background queue). Het oorspronkelijke patroon `Task { @MainActor in self.handleCameraActive() }` crashte met `_dispatch_assert_queue_fail` omdat het capturen van `self` (een `@Observable` object geobserveerd door SwiftUI) op de background thread de observation tracking triggerde op de verkeerde queue. Hetzelfde risico bestond in `SystemAudioCapture` waar `Timer.scheduledTimer` callbacks in `Task { @MainActor in }` werden gewrapped terwijl ze al op de main run loop draaien.

**Decision:** Twee patronen vastgelegd voor thread-hopping naar MainActor vanuit callbacks:
1. **KVO/NotificationCenter callbacks** (onbekende thread): gebruik `DispatchQueue.main.async { [weak self] in ... }` — delay `guard let self` tot we op de main queue zijn, voorkom `@Observable` property access op background threads.
2. **Timer callbacks** (main run loop): gebruik `MainActor.assumeIsolated { ... }` — zero-overhead assertie dat we al op de main thread zijn, vermijd onnodige task scheduling.

Vermijd `Task { @MainActor in }` in beide gevallen: het scheduled een nieuwe cooperative task op de MainActor executor, wat subtiel verschilt van de GCD main queue en de dispatch assertion kan triggeren bij `@Observable` observation tracking.

**Consequences:**
- KVO callbacks capturen `self` niet meer op background threads — elimineert de `_dispatch_assert_queue_fail` crash.
- `DispatchQueue.main.async` is synchrone dispatch naar de main queue, betrouwbaarder dan `Task { @MainActor in }` voor bridging tussen GCD en Swift concurrency.
- `MainActor.assumeIsolated` in timer callbacks is zero-overhead (geen scheduling, geen context switch) en documenteert de threading verwachting.
- Bestaande `@MainActor` methoden (`handleCameraActive`, `handleCameraInactive`, `enterCooldown`) hoeven niet gewijzigd te worden — ze worden nu correct aangeroepen vanuit de main queue/actor context.
- Dit patroon moet gevolgd worden bij toekomstige KVO observers en system callbacks in `@Observable` classes.

---

## DEC-043 — macOS 15 Audio-Only ScreenCaptureKit Categorisatie

**Date:** 2026-03-16
**Status:** Accepted

**Context:** `SystemAudioCapture` gebruikt ScreenCaptureKit (SCStream) voor systeemaudio-opname. Op macOS 14 vereist SCStream minstens één `.screen` output om te functioneren, zelfs als je alleen audio wilt opvangen. Daarom werd altijd een minimale video config meegegeven (`width=2, height=2, framerate=1fps`) om overhead te beperken. Het gevolg: macOS toont de app in Systeeminstellingen als "Scherm- en systeemaudio-opname" — misleidend voor een app die alleen audio opneemt. macOS 15 introduceert `SCStreamConfiguration.captureMicrophone` en maakt het mogelijk om alleen audio te streamen zonder `.screen` output.

**Decision:** Gebruik `#unavailable(macOS 15.0)` om de `.screen` output en bijbehorende video config (`width`, `height`, `minimumFrameInterval`, `queueDepth`) alleen op macOS 14 in te stellen. Op macOS 15+ wordt geen `.screen` output toegevoegd aan de stream. De error message is aangepast van "Schermopnamemachtiging" naar "Systeemaudio-machtiging" om de nieuwe categorisatie te reflecteren.

**Consequences:**
- macOS 15+ toont de app als "Systeemaudio" in Systeeminstellingen — accurate categorisatie.
- Geen onnodige video frames verwerkt op macOS 15+, vermindert CPU/GPU overhead.
- macOS 14 blijft correct functioneren met de minimale video fallback.

---

## DEC-044 — YouTube Anonieme Captions als Primaire Fast-Path

**Date:** 2026-03-16
**Status:** Accepted (supersedes priority logic of DEC-041)

**Context:** YouTube captions fast-path (DEC-041) vereiste een Google OAuth token via `X-Google-Token` header. Dit maakte de feature onbruikbaar zonder Google OAuth configuratie — admin moest een Google Cloud Console project opzetten, OAuth Client IDs configureren, en gebruikers moesten hun Google account koppelen. De `youtube-transcript-api` Python library haalt captions op via dezelfde interne YouTube endpoint die de YouTube website gebruikt, zonder enige authenticatie. Dit maakt de feature direct bruikbaar voor alle gebruikers.

**Decision:** Nieuwe functie `fetch_captions_anonymous()` in `backend/services/youtube_service.py` als primaire captions bron. Gebruikt `youtube-transcript-api` library (v1.2.4) met `YouTubeTranscriptApi().list(video_id)` + `find_manually_created_transcript()` / `find_generated_transcript()`. Taal-prioriteit identiek aan DEC-041: nl manual → nl auto → en manual → en auto → any. Metadata via bestaande `get_youtube_metadata()` (yt-dlp `--dump-json`). Endpoint `transcribe_youtube()` in `backend/routes/transcription.py` gewijzigd naar 3-staps prioriteit: (1) anoniem via `fetch_captions_anonymous()`, (2) Google API via `fetch_youtube_captions()` als `X-Google-Token` aanwezig, (3) yt-dlp + Whisper fallback. Feature flag default gewijzigd naar `True` — YouTube transcriptie nu standaard ingeschakeld.

**Consequences:**
- YouTube captions werken direct voor alle gebruikers zonder Google OAuth setup. Zero configuratie vereist.
- Google OAuth path (DEC-041) blijft intact als secundaire bron — nuttig wanneer `youtube-transcript-api` geblokkeerd wordt door YouTube (IP-based rate limiting, bot detection).
- `youtube-transcript-api` is afhankelijk van YouTube's interne API — kan breken bij YouTube-wijzigingen (zelfde risico als yt-dlp). Library wordt actief onderhouden.
- Feature flag default `True` betekent dat nieuwe installaties YouTube transcriptie direct beschikbaar hebben.
- Clients hoeven niet aangepast — UI was al gebouwd en gated op feature flag. Geen `X-Google-Token` header nodig voor de primaire path.

---

## DEC-045 — Transcript Pagination Removed in Favor of Single-Request Loading

**Date:** 2026-03-16
**Status:** Accepted

**Context:** Both macOS and Windows clients used client-side pagination to fetch transcripts (`?page=N&limit=100`), looping until all pages were loaded. The backend returns all transcripts for the authenticated user, and the typical transcript count per user (tens to low hundreds) makes pagination overhead unnecessary. The pagination loop added complexity to `TranscriptsViewModel` (macOS), `TranscriptsView` (macOS), `api.ts` (Windows), and required tracking `page`, `hasMore`, and `pageSize` state. The `TranscriptsResponse` model carried `total`, `page`, and `limit` fields that were only used for pagination control.

**Decision:** Remove client-side pagination from all transcript loading paths. `APIService.getTranscripts()` (macOS) and `api.getTranscripts()` (Windows) now make a single request without `page`/`limit`/`sort_by` query parameters. The backend returns all matching transcripts in one response. `TranscriptsResponse` model simplified to `{ items: [Transcript] }` only. Client-side sorting and filtering handles display order. `HomeView` takes the first 3 items from the full response for "recent transcripts" instead of requesting `limit: 3`.

**Consequences:**
- Simpler code: removed ~80 lines of pagination loop logic across macOS ViewModel, View, and Windows service.
- Single network request instead of N sequential requests — faster total load time for typical user transcript counts.
- `TranscriptsResponse` model no longer carries `total`, `page`, `limit` — breaking change for any code relying on those fields.
- All sorting and filtering now happens client-side — acceptable given current data volumes.
- Not suitable if transcript counts grow to thousands per user — would need server-side pagination reintroduction.

---

## DEC-046 — Admin Panel: Enhanced Logging Tab and YouTube Configuration

**Date:** 2026-03-16
**Status:** Accepted

**Context:** The admin panel's Logging tab (Fouten) only showed error logs in a basic table. Activity logs were not surfaced in the UI despite being available via `GET /admin/activity`. Additionally, YouTube configuration (max duration, yt-dlp cookies, extractor args) and Google OAuth Client IDs could only be set via environment variables or direct database manipulation, not through the admin UI.

**Decision:** (1) Redesign the Logging tab as a dual-subtab interface with "Activiteit" (activity logs) and "Fouten" (error logs), including filter bars for severity, user, action type, and search. Expandable rows show full log details. Both macOS (`AdminView.swift`) and Windows (`AdminPage.tsx`) implementations. `APIService.getAdminErrors()` and `getAdminActivity()` now accept filter parameters (`severity`, `userId`, `search`, `startDate`, `endDate`, `actionType`). (2) Add YouTube configuration section to Admin > Instellingen: max duration (minutes), yt-dlp cookies content (textarea), extractor args. Add Google OAuth Client ID fields (macOS + Windows). Both platforms send these new fields via `updateAdminSettings()`.

**Consequences:**
- Admins can browse and filter both activity and error logs from the UI without SSH access.
- YouTube yt-dlp configuration manageable through the admin panel — no need to restart the container for cookies or extractor arg changes.
- Google OAuth Client IDs configurable per-platform through the admin UI.
- Backend `GET /admin/settings` and `POST /admin/settings` now include `youtube_max_duration_minutes`, `youtube_cookies_content`, `youtube_extractor_args` fields.

---

## DEC-048 — Never Auto-Logout After Authentication

**Date:** 2026-03-17
**Status:** Accepted

**Context:** User Bas had completed a meeting recording. After the meeting, he found himself logged out — a 401 response from the backend had triggered automatic logout (`useAuthStore.getState().logout()` on Windows, `self.logout()` via `.authDidInvalidate` observer on macOS). Upon re-login, the yellow offline queue banner showed "1 opname worden verstuurd..." without any progress. Worse: the 401 during upload was classified as a client error in `RecordingPage.tsx:285` (`msg.includes("HTTP 4")`), preventing the recording from being enqueued for retry — the recording was permanently lost. The backend already uses 365-day token expiry, making transient 401s from server restarts or brief outages the most likely cause.

**Decision:** Remove all automatic logout behavior on both platforms. Specifically: (1) **Windows `api.ts`**: remove `logout()` call on 401; instead retry the request once after 2 seconds, then throw error without touching auth state. (2) **macOS `AuthViewModel.swift`**: change `.authDidInvalidate` observer from calling `self.logout()` to log-only. (3) **Windows `RecordingPage.tsx`**: exclude 401 from client error classification so recordings always get enqueued for retry. (4) **Windows `offlineQueue.ts`**: increase max retries from 3 to 50 and add file existence check. (5) **macOS `RecordingViewModel.swift`**: on `APIError.sessionExpired` during upload, enqueue to `OfflineQueue` before showing retry sheet. (6) Both platforms validate token at startup with non-disruptive UI feedback — never redirect to login on failure.

**Consequences:**
- Users are never logged out unless they explicitly choose to log out. Token stays in keyring/Keychain.
- Recordings are never lost due to auth errors — they are always enqueued for retry.
- 401 errors during API calls show a non-disruptive error message instead of destroying the session.
- The 50-retry limit (with 10-second intervals in `processQueue`) means the queue will retry for ~8 minutes before giving up — covering typical server restart windows.
- Token validation at startup provides a soft signal ("Sessie mogelijk verlopen") via toast/log without forcing action.
- DEC-013 (Client-Side Logout Only) is effectively superseded — logout is now exclusively user-initiated.

---

## DEC-049 — Gestructureerde Error Codes Across All Layers

**Date:** 2026-03-18
**Status:** Accepted

**Context:** Upload failures toonden onduidelijke foutmeldingen aan gebruikers. Backend retourneerde raw Python exception strings in 500 errors (bijv. `"Internal Server Error"` of stack trace fragmenten). macOS `APIError.httpError` had slechts 2 argumenten (statusCode, message) zonder gestructureerde error codes. Windows `api.ts` toonde HTTP statuscodes direct aan gebruikers. Er was geen standaard error response format — elke route gebruikte een eigen `HTTPException` met ad-hoc detail strings. Het resultaat: gebruikers zagen technische berichten in het Engels en konden niet begrijpen wat er mis ging of wat ze moesten doen.

**Decision:** Drie-laags aanpak:

1. **Backend — gestructureerd error module** (`errors.py`): Centraal `raise_api_error(status_code, error_code, detail)` vervangt alle directe `HTTPException` calls. Standaard JSON response: `{"error_code": "auth_required", "message": "Inloggen is vereist.", "detail": "..."}`. 11 error codes gedefinieerd met vaste Nederlandse `message` per code. `validate_audio_extension()` controleert bestandsextensie tegen allowlist. `api_error_response()` voor non-exception contexts (rate limiting middleware). 500 errors loggen de echte exception maar retourneren alleen `"Er is een serverfout opgetreden."` naar de client.

2. **macOS client**: `APIError.httpError` uitgebreid naar 3 argumenten `(statusCode, message, errorCode)`. Nieuwe `extractErrorInfo()` parseert eerst `error_code` + `message` uit JSON response, dan fallback naar `detail` string, dan HTTP status. `UploadFailureReason` krijgt `.networkError` case. Alle failure reason descriptions worden actionable Nederlands (bijv. "Het bestand is groter dan 120 MB. Probeer een kortere opname.").

3. **Windows client**: `api.ts` `request()` en upload methods parsen `error_code` van JSON responses en gebruiken de backend `message` direct als user-facing tekst. Fallback naar status-code-based Nederlandse berichten. Rust `http.rs` doet 120 MB client-side check en categoriseert netwerk errors (timeout, connection refused, generic). `uploadQueueStore` krijgt `permanentlyFailed` array voor items die 50 retries overschrijden.

**Consequences:**
- Alle error responses van de backend hebben nu een consistent JSON format met `error_code`, `message`, en `detail`.
- Clients kunnen error handling branchen op `error_code` (machine-readable) in plaats van string matching op `message` (fragiel).
- Nederlandse user-facing messages zijn gedefinieerd op de backend — clients hoeven ze niet te vertalen.
- 500 errors lekken geen interne server details meer naar clients (security verbetering).
- File size limiet consistent op 120 MB across all layers (was 200 MB in sommige paden).
- Client-side file size validatie voorkomt onnodige uploads van te grote bestanden.
- macOS retry limiet (10) is lager dan Windows (50) — macOS offline queue is nieuwer en conservatiever.
- Permanently failed items op Windows krijgen een zichtbare banner met bestandsnaam — gebruiker kan actie ondernemen.

---

## DEC-050 — Auto-login via OS Keyring Credentials ("Onthoud mij")

**Date:** 2026-03-18
**Status:** Accepted

**Context:** Gebruikers moesten bij elke herstart van de Windows app opnieuw inloggen, zelfs met een token dat 365 dagen geldig is (DEC-048). Tokens verlopen uiteindelijk wel, en er was geen mechanisme om automatisch opnieuw te authenticeren. Dit leidde tot frustratie, vooral bij gebruikers die dagelijks met de app werken. De macOS app heeft al biometrische login via Keychain; de Windows app had geen equivalent.

**Decision:** "Onthoud mij" checkbox op de login pagina (`LoginPage.tsx`) die email + wachtwoord opslaat in Windows Credential Manager via de bestaande Tauri `store_credential`/`load_credential`/`delete_credential` commands. Bij app start probeert `loadTokenFromKeyring()` in `authStore.ts` automatisch in te loggen als de remember-me vlag is ingesteld:

1. Bestaand token laden en valideren met `getProfiles()` (snelle check)
2. Als token ongeldig/afwezig EN `remember_me` == `"true"` in keyring → saved email + password laden → `api.login()` aanroepen
3. Bij 2FA-accounts: login submitten, `pendingTwoFactor` state instellen → LoginPage toont alleen het 2FA code-invoerveld
4. Bij netwerk-errors: credentials NIET wissen (transient probleem), oud token behouden zodat gebruiker kan doorwerken
5. Bij auth-errors (wachtwoord gewijzigd, account uitgeschakeld): credentials wissen, login pagina tonen
6. Bij expliciete logout: alle saved credentials wissen

Keyring keys: `auth_token` (bestaand), `saved_email`, `saved_password`, `remember_me`.

**Consequences:**
- Gebruikers met "Onthoud mij" worden automatisch ingelogd bij herstart — geen login pagina flash.
- 2FA-gebruikers zien alleen het code-invoerveld, niet het volledige login formulier.
- Wachtwoorden worden opgeslagen in de OS credential manager, niet in localStorage of platte tekst.
- Netwerk-uitval tijdens auto-login leidt niet tot credential verlies — volgende keer wordt opnieuw geprobeerd.
- Expliciet uitloggen wist altijd alle opgeslagen credentials — gebruiker moet opnieuw "Onthoud mij" aanvinken.
- Geen Rust-wijzigingen nodig — alle keyring operaties gebruiken bestaande Tauri commands.
- Bouwt voort op DEC-048 (never auto-logout): auto-login is een aanvulling op de strategie om gebruikers altijd ingelogd te houden.

---

## DEC-051 — Real-Time Streaming Resampler for Windows Audio

**Date:** 2026-03-19
**Status:** Accepted

**Context:** Windows audio devices (WASAPI) typically operate at 48 kHz — when cpal requests 16 kHz, the rate is clamped to the device minimum (usually 44.1 or 48 kHz). The result: a 1.5 hour meeting produced a 489 MB WAV file (48000 × 2 bytes × 5400 seconds = 518 MB theoretical). Combined with the 120 MB upload limit, users could not upload recordings longer than ~20 minutes. The existing `resample()` function in `recorder.rs` was only used in `mix_wav_files()` post-recording — it could not address the file size problem because the WAV was already written at device rate.

**Decision:** Add a `StreamingResampler` struct to `recorder.rs` that performs linear interpolation downsampling within the audio callback itself. Key design: `fractional_pos: f64` is carried across callback invocations, ensuring no samples are lost or duplicated at chunk boundaries. The resampler is injected into all four stream builders (mic i16, mic f32, loopback i16, loopback f32) as an `Arc<Mutex<StreamingResampler>>`. The WAV spec is set to `TARGET_SAMPLE_RATE` (16000 Hz) regardless of device rate. Audio level calculation runs on pre-resample samples for accurate visualization. Simultaneously, the upload limit was raised from 120 MB to 250 MB across backend (`config.py`), Windows (`http.rs`), and macOS (`APIService.swift`, `Models.swift`) to accommodate recordings up to ~2 hours 10 minutes at 16 kHz.

**Consequences:**
- File size reduced 3x for 48 kHz devices: 1.5 hour recording drops from ~500 MB to ~165 MB.
- No post-processing CPU spike: resampling is distributed across real-time callbacks.
- The existing `mix_wav_files()` resampling becomes a no-op (both WAVs already 16 kHz) but remains as safety net.
- 250 MB limit supports recordings up to ~2h10m at 16 kHz mono 16-bit — sufficient for typical meetings.
- Linear interpolation is sufficient quality for speech (Whisper's native input is 16 kHz).
- Files changed: `recorder.rs` (StreamingResampler + all 4 stream builders), `http.rs`, `APIService.swift`, `Models.swift`, `config.py`, `API.md`.

---

## DEC-053 — Remove CGRequestScreenCaptureAccess on macOS 15+

**Date:** 2026-03-20
**Status:** Accepted

**Context:** `ensureScreenCapturePermission()` in `RecordingViewModel.swift` called `CGRequestScreenCaptureAccess()` to trigger the macOS permission dialog for system audio capture. This had two problems: (1) it requested "Screen Recording" permission when the app only needs "System Audio Recording" on macOS 15+ (where `SCStream` without `.screen` output is categorized separately), (2) it may have contributed to a `_dispatch_assert_queue_fail` crash on Thread 4, as the C function's interaction with Swift concurrency's main actor is not guaranteed safe.

**Decision:** Remove `CGRequestScreenCaptureAccess()` entirely. `SCShareableContent.excludingDesktopWindows()` already triggers the correct system permission prompt automatically on first use. On macOS 15+, this shows as "System Audio Recording" (not "Screen Recording") when no `.screen` output is added to the stream — matching the behavior of apps like ChatGPT. Error message updated to reference "Systeemaudio-opname" in System Settings.

**Consequences:**
- Permission flow is now automatic and shows the correct category in System Settings.
- No more explicit `CGRequestScreenCaptureAccess()` call — one less AppKit dependency.
- macOS 14 users still get the permission prompt via `SCShareableContent`; on macOS 15+ the prompt correctly says "System Audio".
- Files changed: `RecordingViewModel.swift` (simplified `ensureScreenCapturePermission()`), `SystemAudioCapture.swift` (Timer crash fix).

---

## DEC-052 — Simplified Retry as Reprocess, Not Special State

**Date:** 2026-03-20
**Status:** Accepted

**Context:** The upload retry flow used `lastFailedUploadURL: URL?`, `lastFailedUploadReason: UploadFailureReason?`, `showRetrySheet: Bool`, and `retryLastFailedUpload()` to handle failed uploads. This mechanism was fragile: `lastFailedUploadURL` was nil when the user tried to retry because `uploadFile()` cleared it at the start of each upload attempt. The retry sheet was a separate SwiftUI `.sheet` that could conflict with the ReprocessSheet (SwiftUI cannot show two sheets simultaneously). Additionally, `retryLastFailedUpload()` used the ViewModel's `selectedProfile` instead of the user's choice in the sheet, causing silent returns when `selectedProfile` was nil.

**Decision:** Replace the entire retry mechanism with a simple `lastFailedRecording: SavedRecording?` property. When an upload fails, the ViewModel matches the file URL to its `SavedRecording` entry (by filename). The error banner shows an "Opnieuw" button that opens the standard ReprocessSheet with that recording — the same flow as clicking any saved recording. No special retry mode, no second sheet, no fragile URL state.

**Consequences:**
- Single code path for both reprocess and retry — ReprocessSheet no longer has an `isRetryMode` branch.
- Only one `.sheet` modifier in RecordingView — no sheet conflicts.
- The user always selects a profile in the ReprocessSheet — no silent nil-profile failures.
- `UploadFailureReason` enum is now dead code (kept for cleanup later).
- Same pattern applied to Windows: `SavedRecordings.handleReprocess()` now uses the shared `uploadAndTrack()` utility instead of fire-and-forget `api.uploadRecording()`.
- Files changed: `RecordingViewModel.swift` (removed 5 properties/methods), `RecordingView.swift` (removed retry sheet, simplified ReprocessSheet), `uploadAndTrack.ts` (new), `useGlobalRecordingHandler.ts` (simplified), `SavedRecordings.tsx` (uses uploadAndTrack).

---

## DEC-047 — YouTube Proxy Support en Bot Detection Resilience

**Date:** 2026-03-17
**Status:** Accepted

**Context:** YouTube blokkeert requests vanaf AWS server IP-adressen met bot-detectie ("Sign in to confirm you're not a bot"). Dit treft zowel `yt-dlp` (audio download + metadata) als `youtube-transcript-api` (anonieme captions). Browser cookies (DEC-038) en EJS challenge solving helpen soms, maar AWS datacenter IP-ranges worden steeds agressiever geblokkeerd. De anonieme captions flow (DEC-044) was ook afhankelijk van yt-dlp voor metadata (titel, duur) via `--dump-json`, waardoor een yt-dlp blokkade de hele captions pipeline uitschakelde.

**Decision:** Drie wijzigingen: (1) **Proxy support**: nieuw `youtube_proxy` admin setting (SOCKS5/HTTP URL) dat wordt doorgegeven aan zowel yt-dlp (`--proxy` argument) als `youtube-transcript-api` (via `proxies` parameter). Configureerbaar via Admin > Instellingen op macOS (`AdminView.swift`) en Windows (`AdminPage.tsx`). (2) **oEmbed metadata fallback**: wanneer yt-dlp `--dump-json` faalt door bot-detectie, wordt metadata opgehaald via de oEmbed API (`https://noembed.com/embed?url=...`) — geeft titel en duur zonder authenticatie. (3) **Decoupled captions**: `fetch_captions_anonymous()` is losgekoppeld van de yt-dlp metadata dependency — gebruikt oEmbed als fallback, zodat captions nog steeds werken wanneer yt-dlp geblokkeerd is.

**Consequences:**
- YouTube transcriptie werkt weer vanaf AWS IPs wanneer een proxy geconfigureerd is die niet geblokkeerd wordt door YouTube.
- Anonieme captions (DEC-044) zijn nu onafhankelijk van yt-dlp — als yt-dlp geblokkeerd is maar captions beschikbaar zijn, werkt de fast-path nog steeds via oEmbed metadata.
- Proxy is optioneel — zonder configuratie gedraagt het systeem zich als voorheen (direct, zonder proxy).
- Admin hoeft niet meer SSH-toegang tot de server te gebruiken om een proxy in te stellen — volledig via de UI.
- oEmbed API biedt beperktere metadata dan yt-dlp (geen upload datum, geen exacte seconden) maar voldoende voor de transcriptie workflow (titel + geschatte duur).
