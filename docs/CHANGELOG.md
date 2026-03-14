# TranscriptStudio — Changelog

All notable changes to the TranscriptStudio macOS and Windows applications are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
