# TranscriptStudio — Changelog

All notable changes to the TranscriptStudio project (macOS, Windows, Android clients, web app, and backend) are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2026-03-16] — Web login page: proper dark mode support

### Fixed
- **Login page ignored system dark mode** (`static/css/main.css`, `static/css/registration.css`, `templates/auth/login.html`): The login page forced a light theme in all modes — `[data-theme="dark"] .login-body` applied the same light gradient as light mode and overrode CSS custom properties (`--text-primary: #333339`, `--bg-card: white`) to light values. Meanwhile, global dark theme input styles (`[data-theme="dark"] input[type="email"]`) had higher CSS specificity (0,2,0) than the login-specific `.login-input` class (0,1,0), applying dark backgrounds (`var(--bg-tertiary)` = `#222439`) to input fields while text color remained dark (`#333339`) — making input text unreadable.
- **Root cause**: Specificity conflict between forced-light login overrides and global dark theme form styles. The login page's approach of overriding CSS custom properties on `.login-body` didn't override the global `[data-theme="dark"] input[type="email/password"]` selectors that target elements directly.

### Changed
- **Login body**: `[data-theme="dark"] .login-body` now applies dark gradient (`#0B0C15` → `#191C28`) instead of forced-light. Removed the CSS variable overrides that forced `--text-primary`, `--text-secondary`, `--border-primary`, `--bg-card` to light values.
- **Login card**: Added `[data-theme="dark"] .login-card` with dark translucent background (`rgba(25,28,40,0.85)`), dark border, stronger shadow.
- **Login inputs**: Added `[data-theme="dark"] .login-body .login-input` / `.auth-input` / `input[type="email/password"]` with specificity (0,3,0) to override global dark input styles. Dark background, light text, magenta focus ring.
- **Text elements**: `.login-card-title`, `.login-card-subtitle`, `.password-toggle`, `.login-forgot-link`, `.login-footer` switched from hardcoded hex colors to `var(--text-primary/secondary/tertiary)`.
- **Registration CSS**: Added dark mode rules for `.strength-text`, `.strength-bar`, `.manual-code p`, `.step-header h3`, `.manual-code-fallback summary`, `.password-match.success`. New `.totp-secret-code` class replaces inline style on TOTP code display element.
- **Login HTML**: Removed hardcoded `color: #666` on summary, hardcoded `background: #f8f9fa` on code element. Added `color: var(--text-primary)` on success screen headings. Fixed `var(--primary-color)` → `var(--primary)` on resend code link.

### Notes
- The login page now fully follows system dark/light mode preference (via `theme.js` `prefers-color-scheme` detection).
- Files deployed: `static/css/main.css`, `static/css/registration.css`, `templates/auth/login.html`.

---

## [2026-03-16] — Backend CSS bugfix: dark mode select chevron tiling

### Fixed
- **Dark mode `<select>` chevron tiling** (`static/css/main.css`, `templates/pages/admin.html`): The `background:` shorthand in dark mode styles was resetting `background-repeat` to `repeat`, causing the custom chevron SVG to tile across the entire `<select>` element instead of appearing once on the right. Fixed by changing `background:` to `background-color:` in 4 places:
  - `[data-theme="dark"] select` (line ~2296)
  - `[data-theme="dark"] select:focus` (line ~2304)
  - `select:focus` light mode (line ~2165)
  - `.log-filter-select` inline style in `admin.html` (line ~634)

### Notes
- The root cause: CSS `background:` is a shorthand that resets all sub-properties (`background-image`, `background-repeat`, `background-position`, etc.) to their initial values. The chevron was set via `background-image` on the base `select` rule, but the dark mode override used `background:` (shorthand) to change the color, which reset `background-repeat` to `repeat` and `background-image` was then inherited with repeat. Using `background-color:` (longhand) only changes the color without affecting other background properties.

---

## [2026-03-16] — Admin panel improvements and transcript loading simplification

### Changed
- **Admin Logging tab redesigned** (`macos/Views/AdminView.swift`, `windows/src/pages/AdminPage.tsx`): The "Fouten" tab is now a dual-subtab interface with "Activiteit" (activity logs) and "Fouten" (error logs). Includes filter bar with severity, user, action type, and text search. Expandable rows show full log details (stack traces, request context). Paginated display with 25 items per page.
- **Admin Settings: YouTube configuration** (`macos/Views/AdminView.swift`, `windows/src/pages/AdminPage.tsx`): New fields in Admin > Instellingen for YouTube yt-dlp configuration: max video duration (minutes), cookies content (textarea for Netscape cookie format), extractor args (default: `youtube:player_client=mediaconnect`). Removes the need to SSH into the server and restart the container for cookie updates.
- **Admin Settings: Google OAuth fields** (`macos/Views/AdminView.swift`, `windows/src/pages/AdminPage.tsx`): Google OAuth Client ID fields (macOS + Windows) added to the settings tab alongside existing MS365 fields.
- **APIService filter parameters** (`macos/Services/APIService.swift`, `windows/src/services/api.ts`): `getAdminErrors()` and `getAdminActivity()` now accept filter parameters (`severity`, `userId`, `search`, `startDate`, `endDate`, `actionType`) instead of fetching a fixed list.
- **AdminSettingsResponse extended** (`macos/Services/APIService.swift`, `windows/src/services/api.ts`): Now includes `youtube_max_duration_minutes`, `youtube_cookies_content`, `youtube_extractor_args` fields. `updateAdminSettings()` accepts these as optional parameters.
- **Transcript pagination removed** (`macos/Services/APIService.swift`, `macos/ViewModels/TranscriptsViewModel.swift`, `macos/Views/TranscriptsView.swift`, `macos/Views/HomeView.swift`, `macos/Models/Models.swift`, `windows/src/services/api.ts`, `windows/src/pages/HomePage.tsx`, `windows/src/pages/RecordingPage.tsx`, `windows/src/App.tsx`): Client-side pagination loops removed from all transcript loading paths. Both platforms now fetch all transcripts in a single request without `page`/`limit`/`sort_by` query parameters. `TranscriptsResponse` model simplified to `{ items: [Transcript] }` — removed `total`, `page`, `limit` fields. ~80 lines of pagination loop logic removed.

### Decisions
- See DEC-045 in [DECISIONS.md](DECISIONS.md) for the transcript pagination removal rationale.
- See DEC-046 in [DECISIONS.md](DECISIONS.md) for the admin panel enhancement rationale.

---

## [2026-03-16] — YouTube anonieme captions via youtube-transcript-api

### Added
- **Anonieme YouTube captions** (`backend/services/youtube_service.py`): Nieuwe functie `fetch_captions_anonymous()` haalt captions op via de `youtube-transcript-api` library — geen Google API key, geen OAuth token, geen Google account nodig. Taal-prioriteit: nl manual → nl auto → en manual → en auto → overige. Metadata (titel, duur) wordt opgehaald via bestaande `get_youtube_metadata()` (yt-dlp `--dump-json`).
- **Dependency**: `youtube-transcript-api` toegevoegd aan `requirements.txt` en `Dockerfile`.

### Changed
- **YouTube endpoint prioriteitsvolgorde** (`backend/routes/transcription.py:transcribe_youtube()`): Nieuwe 3-staps flow:
  1. **Anonieme captions** via `fetch_captions_anonymous()` (nieuw, geen auth)
  2. **Google API captions** via `fetch_youtube_captions()` (als `X-Google-Token` header aanwezig)
  3. **yt-dlp + Whisper** fallback (audio download + GPU transcriptie)

  Voorheen was stap 1 niet beschikbaar en was Google OAuth vereist voor de fast-path.
- **Feature flag default** (`backend/config.py`): `FEATURE_YOUTUBE_ENABLED` default gewijzigd van `False` naar `True`. YouTube transcriptie is nu standaard ingeschakeld — de anonieme captions maken Google OAuth setup overbodig.
- **yt-dlp configuratie** (`backend/services/youtube_service.py`): `_extra_ytdlp_args()` uitgebreid met DB-overrides voor extractor args en cookies content. Nieuwe helper `_get_max_duration_seconds()` leest max duur uit DB settings met fallback naar env var. Nieuwe helper `_ensure_cookies_file()` schrijft cookies content vanuit DB naar disk.

### Decisions
- See DEC-044 in [DECISIONS.md](DECISIONS.md) for the anonymous captions rationale.

### Notes
- Clients (macOS/Windows) hebben **geen wijzigingen** nodig — de YouTube UI was al gebouwd en gated op de feature flag.
- Deployed naar productie: `youtube-transcript-api` geïnstalleerd in Docker container, code gesynct, container herstart. Feature flag verified via `GET /features`.

---

## [2026-03-16] — macOS 15 audio-only ScreenCaptureKit categorisatie

### Changed
- **SystemAudioCapture macOS 15+ audio-only modus** (`macos/Services/SystemAudioCapture.swift`): Op macOS 15+ wordt de `.screen` output niet meer toegevoegd aan `SCStream`. Hierdoor wordt de app in Systeeminstellingen gecategoriseerd als "Systeemaudio" in plaats van "Scherm- en systeemaudio-opname" — een betere UX omdat gebruikers geen schermopname-toestemming hoeven te verwachten voor een audio-only app. De video workload config (`width=2, height=2, minimumFrameInterval=1s, queueDepth=5`) is verplaatst naar een `#unavailable(macOS 15.0)` branch, want macOS 14 vereist minstens één `.screen` output om SCStream te laten functioneren. macOS 15 heeft `captureMicrophone` en hoeft geen screen output als fallback.
- **Error message vereenvoudigd** (`macos/Services/SystemAudioCapture.swift:72`): "Schermopnamemachtiging is vereist voor systeemaudio-opname." → "Systeemaudio-machtiging is vereist voor opname." — consistenter met de macOS 15 categorisatie.

### Decisions
- See DEC-043 in [DECISIONS.md](DECISIONS.md) for the macOS 15 audio-only rationale.

---

## [2026-03-16] — Threading fixes, YouTube card vereenvoudiging, CLAUDE.md optimalisatie

### Fixed
- **VideoCallDetectionService threading crash** (`macos/Services/VideoCallDetectionService.swift`): KVO callback op `AVCaptureDevice.isInUseByAnotherApplication` werd geleverd op `com.apple.root.default-qos` (background queue). Het bestaande `Task { @MainActor in }` patroon veroorzaakte `_dispatch_assert_queue_fail` omdat `self` (een `@Observable` object geobserveerd door SwiftUI op MainActor) werd gecaptured op de background thread. Fix: KVO callback gebruikt nu `DispatchQueue.main.async` en vertraagt `guard let self` tot we op de main queue zijn (regels 78-88, 90-94). Cooldown task in `enterCooldown()` veranderd van redundant `Task { @MainActor in }` naar `Task` met expliciete `MainActor.run` voor state mutatie.
- **SystemAudioCapture timer** (`macos/Services/SystemAudioCapture.swift:274-282`): `Timer.scheduledTimer` callback gebruikte `Task { @MainActor in }` ondanks dat timers van een `@MainActor` class al op de main run loop vuren. Vervangen door `MainActor.assumeIsolated` — zero-overhead en semantisch correct.

### Changed
- **YouTube card vereenvoudigd** (`macos/Views/RecordingView.swift`): Verwijderd: aparte YouTube profielpicker (`youtubeProfileSection`, `youtubeProfileBinding`) — YouTube transcriptie gebruikt nu hetzelfde profiel als reguliere opname (`selectedProfile`). YouTube-rode gradient kleuren (#E61212 → #B80000) vervangen door `Color.brandPrimary` voor consistente branding. Google OAuth connectiesectie altijd zichtbaar (niet meer achter `isGoogleOAuthConfigured` gate). Google verbinding niet meer vereist om YouTube URL te submitten.
- **RecordingViewModel** (`macos/ViewModels/RecordingViewModel.swift`): `youtubeSelectedProfile: Profile?` property verwijderd. `submitYouTubeURL()` gebruikt nu `selectedProfile`. Initialisatielogica voor `youtubeSelectedProfile` uit `loadDefaultProfile()` verwijderd.
- **CLAUDE.md geoptimaliseerd** (`CLAUDE.md`): Vier `@`-referenties verwijderd die 2.555 regels (~20k tokens) aan documentatie in elke sessie laadden: `@README.md` (dubbel geladen — README is al auto-injected), `@docs/API.md` (966 regels), `@docs/PLAN-MULTI-INSTANCE.md` (888 regels), `@docs/RELEASE.md` (234 regels). Roadmap sectie verplaatst als one-liner naar Gotchas. Referenties behouden als plain text zodat Claude docs on-demand kan lezen.

### Decisions
- See DEC-042 in [DECISIONS.md](DECISIONS.md) for the KVO callback threading pattern.
- DEC-039 (onafhankelijke YouTube profielselectie) is superseded — teruggedraaid naar gedeeld profiel.

### Notes
- De threading crash manifesteerde zich als `_dispatch_assert_queue_fail` op Thread 2 (`com.apple.root.default-qos`). Root cause: KVO callbacks worden geleverd op willekeurige threads, en `@Observable` property access tracking triggerde op de verkeerde queue.
- Windows YouTube card had al eerder YouTube-rode styling — die is niet meegenomen in deze sessie.

---

## [2026-03-16] — YouTube hybride aanpak: Captions API + yt-dlp fallback

### Added
- **Google OAuth service** (`macos/Services/GoogleAuthService.swift`): New `actor GoogleAuthService` implementing Google OAuth PKCE flow via `ASWebAuthenticationSession`. Follows the exact `MicrosoftGraphService` pattern: PKCE code verifier/challenge, token exchange with `https://oauth2.googleapis.com/token`, user email fetch from Google userinfo endpoint, automatic token refresh with 60-second margin, Keychain persistence of refresh token via `KeychainService` (key: `googleRefreshToken`). Scope: `youtube.force-ssl` (required for `captions.download`). Redirect URI: `transcript-studio://google/callback`. Error enum `GoogleAuthError` with Dutch descriptions.
- **YouTube Data API v3 functions** (backend `services/youtube_service.py`): Six new async functions using `httpx.AsyncClient`: `extract_video_id()` parses 11-char ID from URL variants, `get_youtube_metadata_api()` calls `videos.list`, `list_caption_tracks()` calls `captions.list`, `select_best_caption_track()` prioritizes nl standard > nl ASR > en standard > en ASR > any, `download_caption_text()` fetches SRT and converts to plain text via `_srt_to_text()`, `fetch_youtube_captions()` orchestrates the full flow. Helper `_parse_iso8601_duration()` converts ISO 8601 durations (PT1H2M3S) to seconds.
- **Google OAuth in features endpoint** (backend `routes/features.py`): `/features` response now includes `google_oauth_configured: bool` and `google_oauth_client_id_macos: string` for client discovery.
- **Google OAuth admin settings** (backend `routes/admin.py`, `config.py`): Added `google_oauth_client_id_macos` and `google_oauth_client_id_windows` to `AdminSettingsUpdate` model, settings GET/POST endpoints, and env config. Same pattern as `ms365_client_id`.
- **Google OAuth UI in YouTube card** (`macos/Views/RecordingView.swift`): Google connection section in YouTube card showing connected state (email + disconnect button) or connect button. URL field and submit disabled when not connected. Captions fallback info banner when `captionsNotAvailable` is true.
- **Google OAuth admin fields** (`macos/Views/AdminView.swift`): Google OAuth Client ID fields (macOS + Windows) in Admin > Instellingen tab, sharing the existing save button with MS365 settings.
- **API features extended** (`macos/Services/APIService.swift`): New `FeaturesResponse` struct and `fetchFeaturesExtended()` method for typed feature response including Google OAuth fields.

### Changed
- **`/transcribe-youtube` endpoint** (backend `routes/transcription.py`): Now accepts optional `X-Google-Token` header. When present, tries YouTube Data API captions first → if found, creates task as "transcribed" and enqueues to notule pipeline (same as `/transcribe-text` pattern) with `source_type: "youtube_captions"`. Falls back to yt-dlp + Whisper when no captions available, with `captions_available: false` in response.
- **`transcribeYouTube()` method** (`macos/Services/APIService.swift`): Now accepts optional `googleToken` parameter, sends as `X-Google-Token` header.
- **`AdminSettingsResponse`** (`macos/Services/APIService.swift`): Added `google_oauth_client_id_macos` and `google_oauth_client_id_windows` fields.
- **`updateAdminSettings()`** (`macos/Services/APIService.swift`): Now accepts optional `googleOAuthClientIdMacos` and `googleOAuthClientIdWindows` parameters.
- **`RecordingViewModel`** (`macos/ViewModels/RecordingViewModel.swift`): Added Google OAuth state (`isGoogleConnected`, `googleUserEmail`, `googleAuthError`, `captionsNotAvailable`, `isGoogleOAuthConfigured`). Added `connectGoogle()`, `disconnectGoogle()`, `checkGoogleConnection()` methods. Updated `checkFeatures()` to use `fetchFeaturesExtended()` and configure `GoogleAuthService`. Updated `submitYouTubeURL()` to pass Google token and require Google connection.
- **Admin settings** (`macos/Views/AdminView.swift`): `loadAdminSettings()` and `saveAdminSettings()` now include Google OAuth fields.

### Decisions
- See DEC-041 in [DECISIONS.md](DECISIONS.md) for the hybrid captions-first architecture.

### Notes
- Windows and Android do not yet have Google OAuth — backend is ready (settings exist, `X-Google-Token` header is optional).
- YouTube Data API quota: ~40 videos/day at default 10,000 units/day.
- Google Cloud Console setup required: create OAuth Client ID (type: iOS, bundle ID: `nl.prezent.TranscriptStudio`), enable YouTube Data API v3, configure consent screen with `youtube.force-ssl` scope.
- The Xcode project (`project.pbxproj`) was updated to include `GoogleAuthService.swift`.

---

## [2026-03-16] — Video call detection service

### Added
- **VideoCallDetectionService** (`macos/Services/VideoCallDetectionService.swift`): New `@Observable` singleton service that detects active video calls by combining two signals: (1) KVO observation on `AVCaptureDevice.default(for: .video)?.isInUseByAnotherApplication` and (2) `NSWorkspace.shared.runningApplications` matching against known video app bundle IDs (Teams, Zoom, FaceTime, Slack, Webex, Discord) and browser bundle IDs. Three-state machine: `idle → detected → cooldown (60s) → idle`. Posts `Notification.Name.videoCallDetected` with a synthetic `CalendarEvent` as userInfo, reusing the existing `CallAlertView` and `MeetingNotificationService` infrastructure. Includes calendar dedup (skips if a calendar meeting already covers the time window), session dismissal tracking, and a 10-second polling fallback when camera device is unavailable in sandbox.
- **`.videoCallDetected` notification** (`macos/Services/MeetingNotificationService.swift`): New `Notification.Name` extension for video call detection events.
- **ContentView `.onReceive`** (`macos/App/ContentView.swift:159-165`): Listens for `.videoCallDetected` notifications, shows existing `CallAlertView` overlay. "Start opname" action forces `.combined` recording mode for detected video calls (via `meeting.id.hasPrefix("videocall-")` check). "Negeer" action propagates dismissal to `VideoCallDetectionService.shared.dismissSession()`.
- **Monitoring startup** (`macos/App/TranscriptStudioApp.swift:30-32`): `VideoCallDetectionService.shared.startMonitoring()` called in app `.task` block, guarded by `#if os(macOS)`.
- **Settings toggle** (`macos/Views/SettingsView.swift`): "Automatische vergaderdetectie" toggle in Agenda section, bound to `@AppStorage("videoCallDetectionEnabled")` (default: true). macOS-only via `#if os(macOS)`.
- **Localizable strings** (`macos/Resources/nl.lproj/Localizable.strings`): 4 new Dutch strings for video call detection notifications and settings.

### Decisions
- See DEC-040 in [DECISIONS.md](DECISIONS.md) for the KVO + running app detection approach.

### Notes
- Browser + camera detection can false-positive on non-video WebRTC sites — dismissed in 1 click.
- Audio-only calls are not detected (no camera activation); calendar integration covers scheduled audio calls.
- The service uses `@unchecked Sendable` because all mutable state is gated behind `@MainActor` methods.

---

## [2026-03-15] — Recording view redesign + onafhankelijke YouTube profielselectie

### Changed
- **Recording idle view redesign** (macOS `macos/Views/RecordingView.swift`): Opnametype-opties (Microfoon, Videogesprek) herontworpen van verticale lijst naar horizontale kaarten met gecentreerde iconen (40×40 cirkel), korte labels ("Alleen microfoon", "Microfoon + systeemgeluid"), en `frame(maxWidth: .infinity)` voor gelijke breedte. Verwijderd: dubbel-geneste `.background`/`.overlay`/`.padding` op `recordingTypeSection` en `profileSection` — cards worden nu uitsluitend door de buitenste `.modernCard()` modifier gestyled.
- **Content padding** (macOS `macos/Views/RecordingView.swift:175`): VStack padding gewijzigd van `TS.Spacing.md` (16pt) naar `TS.Spacing.lg` (24pt) zodat content uitlijnt met de header.
- **"Tik" → "Klik"** (macOS `macos/Views/RecordingView.swift:116,211`): Instructieteksten gewijzigd van "Tik om op te nemen" / "tik daarna" naar "Klik om op te nemen" / "klik daarna" — macOS is geen touch interface.
- **YouTube card styling** (macOS `macos/Views/RecordingView.swift`): Tekstveld gebruikt nu `.textFieldStyle(.plain)` met custom `surfaceSecondary` achtergrond + border overlay i.p.v. `.roundedBorder`. Verzendknop is custom gestyled met YouTube-rood gradient (`#E61212` → `#B80000`) + shadow i.p.v. `.borderedProminent`. Card border gewijzigd van `Color.borderSecondary` naar `Color.red.opacity(0.12)`.
- **YouTube card styling** (Windows `windows/src/pages/RecordingPage.tsx`, `windows/src/styles/globals.css`): YouTube card herontworpen met rode rand-tint, ondertiteltekst, en nieuw `.btn-youtube` button-class (gradient `#E61212` → `#B80000`, witte tekst, rode shadow). Sectielabel kleur gewijzigd van `#FF0000` naar `#E61212`.

### Added
- **Onafhankelijke YouTube profielselectie** (macOS `macos/ViewModels/RecordingViewModel.swift:42`): Nieuw `youtubeSelectedProfile: Profile?` property. `submitYouTubeURL()` gebruikt nu `youtubeSelectedProfile` i.p.v. `selectedProfile`. Wordt geïnitialiseerd vanuit `loadDefaultProfile()` als fallback.
- **YouTube profiel UI** (macOS `macos/Views/RecordingView.swift`): Nieuwe `youtubeProfileSection` view met rood accent-badge dat het geselecteerde profiel toont, plus eigen `ProfilePicker` met `youtubeProfileBinding`. Vervangt de eerder gedeelde `profileSection` in de YouTube card.
- **YouTube profiel state** (Windows `windows/src/stores/recordingStore.ts`): `youtubeProfileId: string` toegevoegd aan Zustand store met `setYouTubeProfileId` setter. Geïnitialiseerd vanuit default profile via `useEffect` in `RecordingPage.tsx`.
- **YouTube profiel picker** (Windows `windows/src/pages/RecordingPage.tsx`): Profielkiezer met `profile-chip` buttons in de YouTube card, onafhankelijk van de opnamekaart.
- **`.btn-youtube` CSS class** (Windows `windows/src/styles/globals.css`): YouTube-rode gradient button met hover/active/disabled states.

### Decisions
- Zie [DEC-039](DECISIONS.md) voor de keuze van onafhankelijke YouTube profielselectie (Optie B).

### Notes
- Android heeft nog geen YouTube transcriptie feature — geen wijzigingen nodig.
- De YouTube card heeft nu op zowel macOS als Windows een eigen profiel picker, onafhankelijk van de opnamekaart.

---

## [2026-03-15] — YouTube bot-detectie fix + Admin module toggle

### Fixed
- **YouTube bot-detectie** (backend `services/youtube_service.py`, `config.py`, `Dockerfile`): `ERROR: [youtube] Sign in to confirm you're not a bot` — root cause: drie ontbrekende zaken op de EC2 server: (1) geen browser cookies → YouTube herkent geen echte gebruiker, (2) geen JS runtime → yt-dlp kan YouTube's anti-bot challenge niet oplossen, (3) geen EJS scripts → challenge solver heeft geen solver distributie. Fix: `_extra_ytdlp_args()` helper voegt `--cookies` en `--js-runtimes node:/usr/local/bin/node` toe aan alle yt-dlp aanroepen. `_ytdlp_cmd()` gebruikt `python3 -m yt_dlp` i.p.v. het binary om dependency conflicten te voorkomen (conda vs pip installaties). Dockerfile aangepast met Node.js 20 LTS binary en `yt-dlp[default]` (bevat `yt-dlp-ejs` challenge solver). Cookies geëxporteerd vanuit Firefox en op server geplaatst (`/app/cookies.txt`, schrijfbaar voor appuser). Metadata timeout verhoogd van 30s naar 60s vanwege EJS challenge solving overhead.
- **yt-dlp niet gevonden** (backend `services/youtube_service.py`): `FileNotFoundError: [Errno 2] No such file or directory: 'yt-dlp'` — root cause: `pip install yt-dlp` installeert de binary in `/home/appuser/.local/bin/` dat niet in het container PATH zit. Opgelost door `_ytdlp_cmd()` die `python3 -m yt_dlp` gebruikt — omzeilt PATH issues volledig.

### Added
- **Admin feature toggle endpoints** (backend `routes/admin.py`):
  - `GET /admin/features` — retourneert alle bekende feature flags met actuele status, label, beschrijving en icoon. Admin-only.
  - `POST /admin/features/{key}` — schakel feature in/uit. Slaat op in `Settings` tabel via `save_setting(f"feature_{key}", "true"/"false")`. Activity logging bij toggle.
  - `FEATURE_FLAGS` dict definieert bekende features met display metadata. Momenteel alleen `youtube_transcription`.
- **Database-backed feature flags** (backend `routes/features.py`): Nieuwe `is_feature_enabled(key, env_default)` functie — checkt eerst `Settings` tabel (`feature_{key}`), valt terug naar env var. Hierdoor kan een admin features togglen zonder container restart.
- **Modules tab in admin UI** (backend `templates/pages/admin/modules.html`, `static/js/admin.js`): Nieuwe "Modules" tab in het admin dashboard met toggle switches per feature. YouTube module toont rood YouTube icoon. Toggle stuurt direct `POST /admin/features/{key}` en reflecteert resultaat. CSS toggle switch component met disabled state tijdens request.

### Changed
- **Feature flag check** (backend `routes/transcription.py`): `POST /transcribe-youtube` gebruikt nu `is_feature_enabled()` i.p.v. directe env var check, zodat admin toggle meteen werkt.
- **Feature endpoint** (backend `routes/features.py`): `GET /features` gebruikt nu `is_feature_enabled()` met DB-first lookup.
- **Dockerfile** (backend): Node.js 20.18.3 LTS toegevoegd voor yt-dlp EJS challenge solver. `yt-dlp` vervangen door `yt-dlp[default]` dat `yt-dlp-ejs` bundelt.
- **youtube_service.py** (backend): `_find_ytdlp()` vervangen door `_ytdlp_cmd()` (module invocatie). `_cookies_args()` uitgebreid naar `_extra_ytdlp_args()` met cookies + JS runtime detectie.

### Decisions
- Zie [DEC-037](DECISIONS.md) voor database-backed feature flags.
- Zie [DEC-038](DECISIONS.md) voor YouTube anti-bot mitigatie met cookies + EJS.

### Notes
- Cookies verlopen — bij herhaalde bot-detectie errors moeten nieuwe cookies vanuit een browser geëxporteerd worden (Firefox: `yt-dlp --cookies-from-browser firefox --cookies cookies.txt`).
- Node.js en yt-dlp-ejs zijn nu in de Dockerfile gebakken — persistent bij container rebuild.
- De admin module toggle werkt direct: uitschakelen verbergt de YouTube card op de upload pagina en retourneert 404 op het transcriptie endpoint.

---

## [2026-03-14] — Per-user API keys

### Added
- **API key model** (backend `models.py`): Nieuw `ApiKey` model met SHA-256 hash opslag, `key_prefix` (eerste 8 chars voor identificatie), `scope` (`full` of `read`), `expires_at`, `is_active` soft-delete flag, en `last_used_at` tracking (max 1x per minuut bijgewerkt). Tabel wordt automatisch aangemaakt via `Base.metadata.create_all()` bij container restart.
- **API key CRUD endpoints** (backend `routes/api_keys.py`): Nieuw routerbestand met drie endpoints:
  - `POST /api-keys` — Maak API key aan (alleen via sessie-token, voorkomt key self-replication). Max 10 actieve keys per gebruiker. Key formaat: `tskey_` + 32 hex chars (38 chars totaal). Ruwe key wordt eenmalig getoond bij aanmaak.
  - `GET /api-keys` — Lijst eigen keys (sessie-token of API key). Toont prefix, naam, scope, aanmaakdatum, laatste gebruik — nooit de volledige key.
  - `DELETE /api-keys/{id}` — Revoke key via soft-delete (`is_active=false`), alleen via sessie-token.
- **API key authenticatie** (backend `services/auth_service.py`): `get_user_by_api_key()` zoekt gebruiker op via SHA-256 hash van de meegestuurde key. `authenticate_request()` uitgebreid met 3e parameter `x_api_key` — volgorde: `X-User-Token` → `X-API-Key` → `X-Admin-API-Key`.
- **Scope enforcement** (backend `services/auth_service.py`): `check_write_scope()` helper die 403 retourneert bij write-operaties met een `read`-scope API key. Alle write endpoints in `transcription.py`, `transcripts.py`, `profiles.py`, `notes.py`, `settings.py`, `feedback.py`, `calendar.py` controleren scope.
- **`X-API-Key` header** (backend `app.py`): Toegevoegd aan CORS `allow_headers`, `api_keys_router` geregistreerd.
- **Rate limiting** (backend `rate_limiting.py`): API key prefix als rate limit key (i.p.v. user token).
- **Error logging** (backend `middleware/error_logging.py`): Fallback naar API key voor gebruikersidentificatie bij foutrapportage.

### Decisions
- Zie [DEC-036](DECISIONS.md) voor de rationale achter het API key ontwerp.

### Notes
- Alleen de backend is aangepast. Client-side UI voor API key management is nog niet geïmplementeerd.
- Bestaande sessie-token authenticatie blijft ongewijzigd werken.
- API keys hebben geen sliding window expiry — ze verlopen op de ingestelde `expires_at` datum (of nooit als die niet gezet is).

---

## [2026-03-14] — YouTube transcriptie + Blog Samenvatting profiel

### Added
- **Blog Samenvatting profiel** (backend `profile_templates.py`): Nieuw 4e default profiel `blog_samenvatting` — genereert narratieve long-form samenvattingen als basis voor blogartikelen. Template bevat TL;DR box, thematische secties met blockquotes, en conclusie met key takeaways. Wordt automatisch aangemaakt via migratie `_migrate_add_blog_profile()` in `app.py`.
- **Feature flag infrastructuur** (backend `config.py`, `routes/features.py`): `GET /features` endpoint retourneert in/uitschakelbare features als JSON (`{"youtube_transcription": true/false}`). Geen authenticatie vereist zodat clients features kunnen checken voor login. Config via `FEATURE_YOUTUBE_ENABLED` env var (default: `false`).
- **YouTube transcriptie endpoint** (backend `routes/transcription.py`): `POST /transcribe-youtube` accepteert YouTube URL + optioneel `profile_id`. Valideert URL (strict regex voor youtube.com/watch, youtu.be, shorts, live), haalt metadata op via `yt-dlp --dump-json`, downloadt audio via `yt-dlp --extract-audio --audio-format wav`, en voert het in de normale Whisper pipeline. Rate limit: 5/uur per gebruiker.
- **YouTube service** (backend `services/youtube_service.py`): Drie functies — `validate_youtube_url()`, `get_youtube_metadata()` (met duurcheck tegen `YOUTUBE_MAX_DURATION_SECONDS`, default 7200s), `download_youtube_audio()` (subprocess met 600s timeout).
- **`downloading` task status** (backend `models.py`, macOS `Models.swift`, macOS `TasksView.swift`, macOS `ProcessingView.swift`, Windows `types.ts`): Nieuwe status in de pipeline voor YouTube downloads. Progress 10%, Nederlandse labels "Downloaden..." / "YouTube video wordt gedownload...".
- **`source_type` / `source_url` velden** (backend `models.py`): Nieuwe kolommen op Task model om de bron van een transcriptie vast te leggen (bijv. `source_type="youtube"`, `source_url="https://..."`). Migratie `_migrate_add_source_fields()` voegt kolommen toe via ALTER TABLE.
- **YouTube UI** (macOS `RecordingView.swift`, `RecordingViewModel.swift`): Conditionele YouTube card in idle state — verschijnt alleen als `isYouTubeEnabled` via feature flag. URL TextField, profiel picker (hergebruikt bestaande `profilePickerSection`), submit knop met loading state en foutmelding. Rood kleurthema voor YouTube branding.
- **YouTube UI** (Windows `RecordingPage.tsx`, `recordingStore.ts`): YouTube sectie in IdleState met URL input, submit knop, en error display. Feature check via `api.fetchFeatures()` bij mount. Submit handler voegt task toe als background task met SSE tracking.
- **API methodes** (macOS `APIService.swift`, Windows `api.ts`): `fetchFeatures()` (GET /features, ongeauthenticeerd) en `transcribeYouTube(url:profileId:)` (POST /transcribe-youtube) op beide platforms.
- **yt-dlp** (backend `Dockerfile`): Toegevoegd aan pip install voor YouTube audio download.
- **YouTube UI** (webapp `templates/pages/upload.html`): YouTube card met URL input, profiel selector en submit knop. Card is verborgen en wordt conditioneel getoond via `fetch('/tstudio/api/features')` bij page load. Submit handler doet `POST /transcribe-youtube` met auth token uit localStorage. Success-melding verwijst gebruiker naar taken.
- **`downloading` status** (webapp `static/js/upload.js`): Toegevoegd aan `statusMap` met label "YouTube video downloaden..." en progress 15%.

### Changed
- **Backend config** (`config.py`): Pydantic v1/v2 compatibiliteit — `_env_field()` helper die `validation_alias` (v2) of `env` (v1) gebruikt afhankelijk van geïnstalleerde versie. `class Config` fallback voor servers zonder `pydantic-settings` package.
- **Feature flag geactiveerd** (`docker-compose.yml`): `FEATURE_YOUTUBE_ENABLED=true` toegevoegd aan container env vars en container opnieuw aangemaakt. YouTube card is nu zichtbaar in webapp, macOS en Windows.

### Decisions
- Zie [DEC-035](DECISIONS.md) voor de rationale achter YouTube als backend-download.

### Notes
- YouTube feature is live op productie (`FEATURE_YOUTUBE_ENABLED=true`). `GET /features` retourneert `{"youtube_transcription": true}`.
- Backend deployed en geverifieerd: blog profiel succesvol aangemaakt via migratie, `source_type`/`source_url` kolommen toegevoegd.
- macOS build geverifieerd: `BUILD SUCCEEDED` (alle switch statements uitgebreid met `downloading` case).
- Windows TypeScript compileert zonder fouten.
- Webapp YouTube card getest: verschijnt conditioneel bij enabled feature.
- Android client (Fase 6) nog niet geïmplementeerd.
- Server heeft pydantic v1 (1.10.7) — config.py aangepast voor backward compatibility.
- Container is handmatig opnieuw aangemaakt met `docker run` (niet via docker-compose) omdat docker-compose een build probeert die failt op ontbrekend pad.

---

## [2026-03-14] — Android client + CI/CD verbeteringen (v1.0.58–1.0.73)

### Added
- **Android client** (`transcript-studio-android/`): Volledig nieuw platform met Kotlin 2.x, Jetpack Compose, Material 3, Hilt DI, Room database en OkHttp/Retrofit networking. Alle UI screens geïmplementeerd: Login (email/wachtwoord + 2FA + biometrie), Home, Recording (waveform visualizer), Tasks (SSE real-time updates), Transcripts (lijst + detail met HTML rendering en export), Settings, en Admin (6 management tabs). Architectuur volgt Repository pattern met ViewModels, `StateFlow`, en `collectAsStateWithLifecycle()`. Offline queue via Room, tokens via EncryptedSharedPreferences (Tink), netwerk monitoring via ConnectivityManager. Package: `nl.prezent.transcriptstudio`, min SDK 28, target SDK 36.
- **Android CI build** (`.github/workflows/release.yml`): `build-android` job bouwt APK op `ubuntu-latest` met JDK 21 en Gradle. APK wordt geüpload naar server en toegevoegd aan `releases.json` manifest (`android` / `dev_android` velden). Debug keystore wordt aangemaakt op CI runner omdat GitHub Actions geen standaard Android debug keystore heeft.
- **Android download card** (`scripts/download-page.html`): Download pagina toont nu een Android APK card naast macOS en Windows.
- **Styled DMG installer** (`scripts/create-dmg-background.py`, `.github/workflows/release.yml`): macOS DMG heeft nu een branded achtergrond met drag-to-Applications layout. Background image wordt gegenereerd via Python script met Pillow, AppleScript positioneert de app en Applications iconen.

### Changed
- **Waveform visualizer** (Windows `WaveformVisualizer.tsx`): Vereenvoudigd naar dezelfde aanpak als macOS — directe canvas rendering zonder complexe animation queue.
- **Floating widget** (macOS `FloatingWidgetController.swift`): Fix voor widget die niet sloot na stoppen opname.
- **Android strings** (`res/values/strings.xml`): Alle hardcoded Nederlandse UI strings geëxtraheerd naar strings.xml resource file.
- **Android state collection** (alle screens): Gemigreerd van `collectAsState()` naar `collectAsStateWithLifecycle()` voor correcte lifecycle-aware state collection.

### Fixed
- **Android signing config** (`app/build.gradle.kts`): Release build gebruikt `signingConfigs.getByName("debug")` voor ad-hoc signing zonder Play Store vereiste. CI runner mist de standaard debug keystore — opgelost door `keytool` stap in GitHub Actions workflow.
- **Android version display** (`BuildConfig.VERSION_NAME`): Versie wordt nu gelezen uit `VERSION` bestand via Gradle i.p.v. hardcoded string.

### Notes
- Android app is functioneel voor UI maar recording-integratie is nog in ontwikkeling.
- Android build version wordt automatisch bepaald uit het root `VERSION` bestand via `build.gradle.kts`.
- Deploy job wacht nu op alle drie de platform builds (macOS + Windows + Android) voordat artifacts naar server worden geüpload.

---

## [2026-03-13] — Directory herstructurering per platform

### Changed
- **Directory renames** (`git mv`): `TranscriptStudio/` → `macos/`, `transcript-studio-windows/` → `windows/`, `RecordingActivityWidget/` → `ios-widget/`. Consistent lowercase platform namen op root level. `TranscriptStudio.xcodeproj` en `TranscriptStudioTests` blijven ongewijzigd (Xcode scheme/target namen).
- **Xcode project** (`TranscriptStudio.xcodeproj/project.pbxproj`): Group path `TranscriptStudio` → `macos`, entitlements paden (`CODE_SIGN_ENTITLEMENTS`), en `INFOPLIST_FILE` bijgewerkt naar `macos/` prefix.
- **Build scripts** (`scripts/sync-version.sh`, `build.sh`, `upload.sh`, `sync-version.ps1`, `build.ps1`, `upload.ps1`): Alle `transcript-studio-windows` referenties → `windows`.
- **GitHub Actions** (`.github/workflows/release.yml`): `working-directory` en `find` paden bijgewerkt.
- **Documentatie** (`CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/RELEASE.md`, `docs/README.md`, `docs/CHANGELOG.md`, `skills/transcript-studio-android.md`): Alle directory referenties bijgewerkt.
- **`.gitignore`**: Ignore patterns van `transcript-studio-windows/` → `windows/`.

### Decisions
- Zie [DEC-034](DECISIONS.md) voor de rationale.

### Notes
- `git mv` behoudt history tracking.
- macOS build geverifieerd: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` — **BUILD SUCCEEDED**.
- `scripts/sync-version.sh` geverifieerd: alle 3 platform configs succesvol bijgewerkt.
- Historische plan-bestanden in `docs/plans/` en `.claude/plans/` zijn niet bijgewerkt — dit zijn snapshots van eerdere sessies.

---

## [2026-03-13] — Documentatie: Apple telefonie beperking

### Added
- **Bekende issues: Apple telefonie niet opneembaar** (`README.md` bekende issues tabel): Gedocumenteerd dat iPhone-doorschakeling (FaceTime relay / Telefoon-app via Mac) niet werkt met de Systeemgeluid- of Gecombineerd-opnamemodus. Apple routeert deze audio via een privé audiopad (`com.apple.avconference` / CoreTelephony) dat buiten het bereik van ScreenCaptureKit valt. Dit is een macOS-platformbeperking, geen bug in TranscriptStudio. Workarounds: gebruik een VoIP-app (Teams/Zoom/WhatsApp Desktop), microfoonmodus met speaker, of een virtuele audio-driver (BlackHole/Loopback).

---

## [2026-03-13] — Profile UX simplification + timezone fix (v1.0.50)

### Changed
- **Simplified profile creation** (macOS `ProfilesView.swift`, Windows `ProfilesPage.tsx`): Replaced the confusing dual-prompt form (system prompt + notule prompt) with a streamlined flow. Users now pick a **style** (Zakelijk/Informeel/Technisch) from a visual card selector and enter a single **opdracht** describing what the notes should contain. The style determines the AI's system prompt automatically. Previous "system prompt" and "HTML template" fields are hidden behind a collapsible "Geavanceerde opties" section for power users. Existing profiles with custom system prompts are automatically detected and shown in advanced mode when edited.
- **Profile form labels** (macOS + Windows): Field labels changed from technical jargon ("Systeemprompt", "Notulenprompt") to user-friendly Dutch ("Stijl", "Wat moet er in de notulen staan?") with placeholder examples and descriptive footer text.

### Fixed
- **Email timestamps show Amsterdam time** (backend `routes/transcription.py`): Notification emails ("Notule klaar" and "Veiligheidscontrole geblokkeerd") displayed UTC time (e.g., "14:30 UTC"). Changed to `Europe/Amsterdam` timezone using `ZoneInfo`. The Dockerfile already had `TZ=Europe/Amsterdam` configured, but the Python code explicitly used `datetime.now(timezone.utc)` for display formatting. Internal API timestamps (ISO format for client consumption) remain UTC — clients handle timezone conversion via their own `DateFormatter` / locale settings.

### Decisions
- Zie [DEC-032](DECISIONS.md) voor de rationale achter de profiel UX vereenvoudiging.

### Notes
- Backend change deployed directly via `scp` + `docker restart n8n_transcript_studio`.
- The three default styles (Zakelijk/Informeel/Technisch) use the same system prompts as the existing default profiles in `Models.swift` / `types.ts`, ensuring backward compatibility.
- Backend API contract unchanged — still receives `system_prompt` + `notule_prompt` strings. The simplification is entirely client-side.

---

## [2026-03-13] — Real-time upload progress tracking (macOS & Windows)

### Added
- **Upload progress delegate** (macOS, `APIService.swift`): New `UploadProgressDelegate` class implementing `URLSessionTaskDelegate` with `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)`. Reports byte-level upload progress (capped at 0.99 to reserve 1.0 for confirmed completion). The `uploadAudio()` method now uses `session.upload(for:from:delegate:)` instead of `session.data(for:)`, removing `req.httpBody` since the body is passed directly to the upload call.
- **XHR-based upload with progress** (Windows, `api.ts`): New `uploadRecordingWithProgress()` method using `XMLHttpRequest` with `upload.onprogress` for real-time byte progress. Browser `fetch()` doesn't support upload progress events, so XHR is used. Same FormData construction, error handling, and abort signal support as the existing `uploadRecording()`.

### Changed
- **RecordingPage upload call** (Windows, `RecordingPage.tsx` line 183): Replaced `api.uploadRecording()` with `api.uploadRecordingWithProgress()`, passing an `onProgress` callback that updates the background task progress percentage.

### Notes
- No UI changes needed — macOS `RecordingWidgetView.swift` already renders `recordingVM.uploadProgress` as a circular progress ring, and Windows `ProcessingBar.tsx` already renders `task.progress` as a percentage with animated bar.
- Progress capped at 99% during transfer; 100% only set after server confirms successful upload.

---

## [2026-03-13] — Dev/beta build pipeline met GitHub Actions

### Added
- **Dev/beta build channel** (`scripts/env.sh`, `scripts/build.sh`, `scripts/release.sh`, `scripts/upload.sh`): Nieuw `BUILD_CHANNEL` systeem (standaard `dev`, expliciet `--production` voor productie). Dev builds krijgen eigen bundle ID (`nl.prezent.TranscriptStudio.dev`), app naam ("TranscriptStudio Dev"), en artifact namen (`TranscriptStudio-Dev-*.dmg`). Side-by-side installeerbaar naast productie.
- **GitHub Actions dual-trigger** (`.github/workflows/release.yml`): Naast de bestaande `v*` tag trigger (productie) zijn er nu twee extra triggers: `dev-v*` tags voor dev builds en `workflow_dispatch` voor handmatige channel keuze. Beide channels bouwen met correcte bundle ID's, product namen en artifact namen via build-time overrides (`PRODUCT_BUNDLE_IDENTIFIER` voor xcodebuild, `TAURI_CONFIG` env var voor Tauri).
- **GitHub Releases met release notes** (`.github/workflows/release.yml` deploy job): Na deploy worden automatisch GitHub Releases aangemaakt. Release notes worden uit de eerste entry van `docs/CHANGELOG.md` geëxtraheerd. Dev releases worden gemarkeerd als pre-release; productie releases als volledige release. DMG en MSI worden als downloadbare assets aan de release gehangen.
- **Deploy scripts** (`scripts/deploy-dev.sh`, `scripts/deploy-production.sh`): One-command deploy scripts. `deploy-dev.sh` maakt een `dev-v{version}` tag en pusht naar GitHub; `deploy-production.sh` maakt een `v{version}` tag. Beide pushen eerst de laatste commits, creëren de tag, en laten GitHub Actions de rest doen (build → upload → release notes).
- **Dev sectie op download page** (`scripts/download-page.html`): "Ontwikkelversie (Beta)" sectie met oranje badge, wordt automatisch getoond wanneer `dev_*` velden in releases.json aanwezig zijn. Leest `dev_macos` en `dev_windows_x64` uit het manifest.
- **Shared build config** (`scripts/env.sh`): Nieuw bestand dat door alle build scripts wordt gesourced. Centraliseert `VERSION`, `BUILD_DIR`, `SERVER`, en channel-afhankelijke variabelen (`APP_DISPLAY_NAME`, `BUNDLE_ID_MACOS`, `DMG_NAME`, etc.).

### Changed
- **Dynamische TitleBar** (`windows/src/components/layout/TitleBar.tsx`): Hardcoded "TranscriptStudio" vervangen door `getName()` uit `@tauri-apps/api/app`. Toont automatisch "TranscriptStudio Dev" of "TranscriptStudio" afhankelijk van build channel.
- **releases.json manifest**: Dev builds schrijven naar `dev_latest_version`, `dev_macos`, `dev_windows_x64` velden. Productie builds schrijven naar de bestaande velden. Beide channels bestaan naast elkaar in hetzelfde manifest.

### Decisions
- Zie [DEC-031](DECISIONS.md) voor de rationale achter build-time overrides vs. repository wijzigingen.

### Notes
- Workflow: `v*` tag push = automatische productie build. Manual dispatch = keuze dev (default) of production.
- Lokaal: `./scripts/release.sh` = dev, `./scripts/release.sh --production` = productie.

---

## [2026-03-12] — Fix biometric toggle race condition (v1.0.49)

### Fixed
- **Biometric toggle race condition** (macOS, `SettingsView.swift`): Touch ID inschakelen faalde stilletjes door een duplicate `biometricSection` in SettingsView. Beide secties hadden een `onChange` handler op dezelfde `@AppStorage("biometricLoginEnabled")` key, waardoor `saveTokenWithBiometrics` twee keer parallel werd aangeroepen. Dit veroorzaakte een `errSecDuplicateItem` Keychain-fout (de tweede aanroep probeerde een token op te slaan dat de eerste net had geschreven). Na de fout werd de toggle stilletjes gereset naar uit, zonder foutmelding aan de gebruiker. Opgelost door de ongebruikte duplicate `biometricSection` te verwijderen, een guard toe te voegen die controleert of er een geldig auth token aanwezig is voordat de Keychain-operatie start, en gebruikersfeedback toe te voegen bij fouten zodat mislukte biometrische activering zichtbaar is in de UI.

### Notes
- Versies 1.0.33 t/m 1.0.48 bevatten uitsluitend CI-configuratie en release pipeline fixes (Swift 5 modus voor CI, Xcode 16.x compatibiliteit). Geen functionele wijzigingen.

---

## [2026-03-12] — Collapsible sidebar, full transcript pagination & waveform improvements (v1.0.32)

### Added
- **Collapsible sidebar** (macOS, `ContentView.swift`): New collapse/expand system replacing the previous `columnVisibility` toggle that completely hid the sidebar with no recovery. Collapsed mode shows a minimal 52px icon column with navigation icons and an expand button at the bottom. Expanded mode shows the full sidebar with a collapse button in the profile section. Keyboard shortcut `Shift+Cmd+S` toggles between states. Tooltips on all collapsed icons for discoverability.
- **Full transcript pagination** (macOS + Windows): Both platforms now automatically paginate through all transcript pages. Previously only the first page (up to 100 items) was loaded. The `loadTranscripts()` function (macOS `TranscriptsView.swift`) and `getTranscripts()` method (Windows `api.ts`) now loop through pages of 100 items until all transcripts are fetched, using response item count and total as stop conditions.
- **Delete saved recordings** (macOS, `RecordingViewModel.swift` + `RecordingView.swift`): New `deleteSavedRecording()` method locates the WAV file on disk, deletes it via FileManager, and removes it from the in-memory list. Context menu on saved recording rows provides "Opnieuw verwerken" (reprocess) and "Verwijderen" (delete with destructive role and trash icon).
- **Pending task recovery on app restart** (macOS, `RecordingViewModel.swift` + `ContentView.swift`): Tasks that were in progress when the app was quit are now recovered on next launch and integrated into the authentication flow.

### Changed
- **Waveform rendering** (macOS, `WaveformView.swift`): Replaced right-angle polyline rendering with smooth bezier curve interpolation for more organic waveform shapes. Updated wave parameters and visual appearance.
- **ReprocessSheet styling** (macOS, `RecordingView.swift`): Added `.formStyle(.grouped)` and explicit frame sizing (min 420×340pt, ideal 460×380pt) to ensure consistent modal presentation on macOS.
- **FloatingWidgetPanel** (macOS): Minor styling adjustments.
- **AdminView** (macOS): Minor UI adjustments.
- **Microsoft Graph** (Windows, `microsoftGraph.ts`): Minor improvements to API call handling.
- **HomePage** (Windows, `HomePage.tsx`): UI refinements.

### Decisions
- DEC-029: Collapsible sidebar replacing columnVisibility toggle (see [DECISIONS.md](DECISIONS.md))
- DEC-030: Auto-pagination for transcript loading (see [DECISIONS.md](DECISIONS.md))

### Notes
- The collapsible sidebar ensures users can always access the logout button in the profile section, which was previously inaccessible when the sidebar was fully hidden.
- Transcript pagination error handling retains partially loaded data rather than showing nothing when an error occurs mid-pagination.

---

## [2026-03-12] — Task management: cancel, delete, and monitor active tasks

### Added
- **Task management view** (macOS + Windows): New "Taken" tab/page showing all active and recent tasks with real-time status, progress bars, and relative timestamps. Auto-refreshes every 10 seconds.
- **Cancel task** (backend + macOS + Windows): Users can cancel in-progress tasks (pending through processing_webhook). Removes task from transcription and webhook Redis queues, sets status to `cancelled`, broadcasts cancellation via SSE to connected clients.
- **Delete task** (backend + macOS + Windows): Users can delete any task (active or completed). Active tasks are automatically cancelled before deletion.
- **Backend endpoints**: `POST /task/{task_id}/cancel` and `DELETE /task/{task_id}` with ownership checks, admin bypass, and activity logging.

### Changed
- **macOS sidebar**: Added "Taken" tab between "Opnemen" and "Notulen" (keyboard shortcut Cmd+3, existing shortcuts shifted)
- **Windows sidebar**: Added "Taken" nav item between "Opnemen" and "Notulen"

---

## [2026-03-12] — Fix Windows combined recording: loopback stream drop + audio mixing

### Fixed
- **WASAPI loopback stream immediately dropped** (Windows, `src-tauri/src/audio/recorder.rs:210`): The line `let _ = loopback_stream_holder;` was intended to suppress an "unused variable" warning while keeping the stream alive. However, Rust's bare `_` pattern does not create a binding — it moves and immediately drops the value. The loopback stream was destroyed before `input_stream.play()` even started, meaning **system audio was never captured** in combined mode. Fixed by changing to `let _loopback = loopback_stream_holder;` (underscore-prefixed name creates a real binding that lives until end of scope).
- **Concurrent WAV write corruption** (Windows, `recorder.rs`): Mic and loopback streams both wrote samples to the same `Arc<Mutex<WavWriter>>`. Since both callbacks fire from separate OS audio threads, samples were interleaved in arbitrary chunks — producing garbled audio, not a proper mix. Refactored to write mic and loopback to **separate WAV files**. After recording stops, both files are mixed via `mix_wav_files()` using element-wise max by absolute value (consistent with macOS `mixAudioFiles()` approach).

### Changed
- **Windows audio pipeline** (`recorder.rs`): Combined mode now creates two WAV files: `recording_{ts}.wav` (mic) and `recording_{ts}.loopback.wav` (system audio). After both streams finalize, `mix_wav_files()` reads both files, produces a mixed output, writes it back to the mic path, and deletes the loopback temp file. If mixing fails, the mic-only audio is preserved as fallback.

### Decisions
- DEC-028: Separate file recording with post-mix for combined mode (see [DECISIONS.md](DECISIONS.md))

### Notes
- WASAPI loopback requires **no special permissions** on Windows — it's built into Windows Core Audio
- Microphone muting has **no effect** on loopback capture (independent audio devices)
- The `let _ = x` vs `let _x = x` distinction in Rust is a known footgun — bare `_` drops immediately, underscore-prefixed names keep the value alive
- This must be tested on Windows to verify loopback capture works end-to-end

---

## [2026-03-12] — Microsoft 365 OAuth fix, hallucination detection, transcript visibility

### Fixed
- **OAuth token exchange CORS failure** (Windows): `microsoftGraph.ts` used browser `fetch()` to call Microsoft's `/oauth2/v2.0/token` endpoint. Microsoft only returns CORS headers for SPA-type redirect URIs, not desktop/mobile custom schemes (`transcript-studio://auth/callback`). Replaced all `fetch()` calls to Microsoft APIs with Tauri `proxy_request` command (reqwest in Rust), which bypasses CORS entirely.
- **Deep-link payload parsing** (Windows): Tauri deep-link plugin emits URLs as a JSON array (`["transcript-studio://..."]`), but `event.payload().to_string()` produced the raw JSON string. Added `serde_json` array parsing with fallback to quote-trimming in `lib.rs`.
- **Admin settings save HTTP 500** (backend): `save_setting()` in `admin.py` used SQLite-only `INSERT OR REPLACE` syntax. Production runs PostgreSQL, which requires `INSERT ... ON CONFLICT DO UPDATE`. Fixed by importing the PostgreSQL-compatible `save_setting` from `db_operations.py`.
- **Transcript visibility** (Windows): Transcripts not appearing in the list after login — fixed store initialization and data fetching order.

### Added
- **Whisper hallucination detection** (backend): Added detection for garbled/hallucinated Whisper output when audio files contain no clear speech. Checks for repetitive patterns, nonsense character sequences, and statistically improbable token distributions. Returns `no_speech` status instead of garbage transcript text.

### Decisions
- DEC-027: Route Microsoft Graph API through Tauri proxy_request for CORS bypass (see [DECISIONS.md](DECISIONS.md))

### Notes
- The `transcript-studio://auth/callback` redirect URI must be registered in Azure AD App Registration under "Mobile and desktop applications" — not as SPA type
- All three Microsoft API calls (token exchange, user profile, calendar events) now use `proxy_request` for consistency
- Previous OAuth attempts showed correct authorization codes arriving via deep-link — the failure was exclusively in the token exchange step

---

## [2026-03-11] — Browser-native upload replaces reqwest multipart (v1.0.27)

### Fixed
- **Windows upload 422 finally resolved**: Replaced the entire Rust-based multipart upload path (`http_upload_file` in `http.rs`) with browser-native `FormData` + `fetch()`. The reqwest multipart encoding — both the `.multipart()` API (DEC-025) and manual `Vec<u8>` construction — was fundamentally incompatible with FastAPI's python-multipart parser behind nginx reverse proxy. Browser `FormData` produces the exact same encoding as an HTML form upload, which every backend supports.

### Changed
- **Upload architecture** (Windows): File is now read via Tauri FS plugin (`@tauri-apps/plugin-fs`), converted to a `Blob`, wrapped in `FormData`, and sent with browser `fetch()`. No Rust code involved in the upload HTTP request itself.
- **Rust cleanup**: Removed `http_upload_file` command, `multipart` feature from reqwest, `uuid` crate dependency. Cleaned up unused imports (`Version`, `Uuid`).
- **Backend CORS**: Added `https://tauri.localhost`, `http://tauri.localhost`, `http://localhost:1420` to default CORS origins (production uses `CORS_ORIGINS=*` env var so already open).

### Added
- **Tauri FS plugin**: `tauri-plugin-fs` (Rust) + `@tauri-apps/plugin-fs` (JS) for reading WAV files from disk into the browser context.
- **FS scope permission**: `fs:scope` with `$APPDATA/**` allow path — required for the FS plugin to read recordings from AppData.

### Decisions
- DEC-026: Browser-native FormData upload over Rust reqwest (see [DECISIONS.md](DECISIONS.md))

### Notes
- The macOS client uses URLSession (OS-native HTTP stack) which never had this issue — only the Windows reqwest path was affected
- The old retry loop (20 attempts × 200ms) for waiting on WAV finalization is no longer needed — the `recording-stopped` event already fires after finalization

---

## [2026-03-11] — Fix Windows upload 422 error: remove debug middleware, switch to reqwest Form API

### Fixed
- **422 "field required" on Windows uploads** (backend + Windows): Two separate issues combined to cause all Windows audio uploads to fail:
  1. `upload_debug_middleware` in `app.py` called `await request.body()` inside `BaseHTTPMiddleware`. This consumed the ASGI receive channel, leaving an empty stream for FastAPI's multipart parser → 422.
  2. After removing the middleware, uploads still failed because `http_upload_file` in `http.rs` used manual `Vec<u8>` body construction with an explicit `Content-Length` header. The combination of this with nginx's `proxy_buffering off` + `chunked_transfer_encoding off` settings caused python-multipart to fail to parse the multipart body.

### Changed
- **Backend**: Removed `upload_debug_middleware` from `app.py` — body format confirmed correct, middleware served its purpose
- **Windows Rust backend** (`src-tauri/src/commands/http.rs`): Replaced manual multipart body construction with reqwest's `multipart::Form` API. Removed `http1_only()` constraint and explicit `Content-Length` header — reqwest now manages these

### Notes
- Cleared stale `__pycache__` on the server after removing the middleware (caused a separate `TranscribeTextRequest` NameError on restart)
- Python manual body tests confirmed body format was always correct — the issue was at the HTTP layer, not the multipart encoding
- Requires Tauri app rebuild to deploy the Rust change

### Decisions
- DEC-025: reqwest Form API over manual multipart construction (see [DECISIONS.md](DECISIONS.md))

---

## [2026-03-10] — Waveform visual redesign: blue-violet neon fabric

### Changed
- **Waveform visualization** (macOS + Windows): Complete visual redesign of the recording waveform to match a neon blue-violet fabric reference. 5 waves → 12 overlapping waves with a blue → violet → pink neon color palette. Thinner, more varied line widths (0.6–2.5px), stronger glow on primary wave (glowWidth 12, opacity 0.25), and wider frequency/speed ranges (0.7–3.2 freq, 3.8–14.5 speed) create a dense woven-thread effect. Primary wave color changed from magenta (#E50074) to electric blue (0.30, 0.50, 1.0). History offsets tightened (steps of 2 instead of 5) for more responsive staggering.

### Notes
- Dynamics (smoothing, envelope, jitter) unchanged — only colors, wave count, and sizing parameters were modified
- Both `WaveformView.swift` and `WaveformVisualizer.tsx` updated in lockstep

---

## [2026-03-09] — Windows floating recording widget fix and redesign

### Fixed
- **Widget window not appearing** (Windows): Added missing `core:window:default` and `core:webview:default` Tauri permissions — the frontend was silently denied permission to create the widget window

### Changed
- **Widget redesign** (Windows): Replaced rectangular 240×140px card layout with horizontal 380×56px pill matching macOS `RecordingWidgetView` — includes status badge (REC/PAUZE/STOP...), inline waveform, monospaced timer, pause button, and labeled stop button
- **Widget positioning** (Windows): Now anchors to bottom-right of primary monitor (above taskbar) matching macOS behavior, was previously top-left at (20, 20)

### Decisions
- DEC-024: Windows widget pill design parity with macOS (see [DECISIONS.md](DECISIONS.md))

---

## [2026-03-07] — Security hardening, feedback bugfixes, backend deployment (v1.0.22)

### v1.0.22 (2026-03-07)

#### Fixed
- **Feedback archive 400 error** (backend + both clients): Backend rejected "archived" as invalid status — added to validation whitelist in `feedback.py`. Both macOS and Windows clients sent `response` field but backend expects `admin_response` — fixed in `APIService.swift` and `api.ts`
- **Duplicate delete calls** (Windows): Feedback delete button could fire multiple times before the first request completed, causing 404 errors on subsequent calls. Added `busyId` guard state to disable action buttons during pending operations

#### Changed
- **Security hardening** (Windows): Content Security Policy enabled in Tauri config, file size validation before upload, auth token moved from URL to headers in SSE client, XSS protection via DOMPurify sanitization, token storage migrated from localStorage to OS keyring
- **API logging** (Windows): Console logs now only appear in development mode (`import.meta.env.DEV`)
- **Search validation** (Windows): Added query length validation to prevent excessive API calls

#### Added
- **Backend deployment docs** in `CLAUDE.md`: Server address, deployment path, rsync/scp commands, container restart procedure

#### Decisions
- DEC-023: Backend feedback status validation (see [DECISIONS.md](DECISIONS.md))

---

## [2026-03-07] — API URL refactoring, admin fixes, build pipeline (v1.0.17 - v1.0.21)

### v1.0.21 (2026-03-07)

#### Added
- **Build & release pipeline**: Four shell scripts in `scripts/` for automated version sync, building (DMG/MSI), uploading to server, and orchestrated release
- **Clickable shortcuts**: `.command` files in `scripts/` for Finder double-click execution
- **Server-side download hosting**: Nginx `/tstudio/download/` route serving static release artifacts from EC2
- **Release manifest**: `releases.json` on server with latest version info and download URLs per platform
- **Release documentation**: `docs/RELEASE.md` with complete pipeline guide

### v1.0.20 (2026-03-07)

#### Fixed
- **API URL centralization** (macOS + Windows): Base URL now includes `/tstudio/api/` prefix, removing redundant path segments from all endpoint definitions
- **Admin page data fetching** (Windows): Fixed user display, transcript count calculation, and feedback field mapping to match backend response format
- **Date parsing** (macOS): Enhanced `TranscriptTask` with comprehensive ISO8601 formatters and fallback date parsers for consistent date display
- **TaskStatus decoding** (macOS): Fixed enum decoding for snake_case backend values (`no_speech`, `processing_webhook`)
- **Upload URL construction** (macOS): Fixed `uploadAudio` and `taskStreamInfo` URL construction after base URL refactoring

#### Changed
- **Version sync**: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in Xcode pbxproj, `tauri.conf.json`, and `Cargo.toml` now synced to `VERSION` file (was hardcoded at 1.0/1.0.10)
- **Windows app types**: `AdminUser`, `AdminFeedback`, and `AdminStats` interfaces aligned with actual backend response shapes

### v1.0.17 - v1.0.19 (2026-03-06 - 2026-03-07)

#### Fixed
- **App freeze after transcription error**: Reset recording state when backend returns error, preventing UI lockup
- **422 upload error**: Fixed multipart encoding and added Content-Length header for reliable audio uploads

---

## [2026-03-06] — Recording error handling, waveform visibility, cross-platform fixes (v1.0.12 - v1.0.16)

### v1.0.16 (2026-03-06)

#### Fixed
- **Recording error handling**: Added comprehensive error handling for recording failures with debug logging
- **Improved state management**: Better handling of recording state transitions on error conditions

### v1.0.15 (2026-03-06)

#### Fixed
- **Cross-platform iOS/macOS compilation**: Added conditional UIKit imports for iOS-specific features (pasteboard, activity controller, OAuth presentation)
- **Waveform visibility**: Improved waveform amplitude compression and scaling for better visibility of quiet recordings
- **Account management**: Enhanced GDPR account deletion and data export flows

#### Changed
- **macOS deployment target**: iOS 17.0 deployment configured for iPhone and iPad support
- **Background task tracking**: Added background task display in RecordingPage UI

### v1.0.14 (2026-03-06)

#### Added
- **macOS menu bar icon**: Added native menu bar icon assets for TranscriptStudio

#### Fixed
- **Windows app layout**: Footer positioning fixed — footer now displays correctly at bottom instead of taking over full page
- **API authentication**: Aligned auth header format between platforms (X-User-Token vs Authorization: Bearer)

### v1.0.13 (2026-03-06)

#### Fixed
- **Admin panel models**: Aligned admin panel data models with actual backend API response shapes
- **User management endpoints**: Corrected field mappings for user creation and role management

### v1.0.12 (2026-03-06)

#### Added
- **Windows app redesign**: Complete visual redesign matching macOS design language
- **WaveformVisualizer**: Multi-wave rendering system with 5 layered sine waves, dynamic range compression, and idle breathing animation
- **ProfilesPage**: Profile management page with create/edit/delete functionality
- **AccountPage**: Account settings with GDPR export and deletion
- **FeedbackWidget**: In-app bug reporting and feedback submission
- **SavedRecordings**: List view of saved recordings with playback and management
- **RecordingWidget**: Improved recording controls with timer and visual feedback

#### Changed
- **Tailwind configuration**: Updated design tokens matching macOS Color+Brand.swift palette
- **Global styles**: Comprehensive CSS overhaul for consistent cross-platform appearance
- **API service**: Improved error handling and field mapping alignment with macOS APIService

#### Fixed
- **Waveform visibility**: Barely visible soundwave recordings display improved through amplitude compression
- **Recording state management**: Better handling of upload failures and retry logic

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
