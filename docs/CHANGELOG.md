# ThoughtVault — Changelog

All notable changes to the ThoughtVault project (macOS, Windows, Android clients, web app, and backend) are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2026-07-10] — Grote-bestanden-transcriptie, live waveform-pipeline, neon Metal-soundwave (v1.0.249)

### Fixed
- **Grote bestanden transcriberen niet op iOS/macOS** — root cause: WhisperKit kreeg het hele bestand in één keer + de watchdog kapte lange runs af. `macos/Services/AudioChunker.swift` splitst nu op sample-exacte chunkgrenzen; `LocalTranscriber.swift` verwerkt per chunk en stuurt een expliciete `.endOfStream`-flush zodat de laatste (partiële) chunk niet zoek raakt. Watchdog-timeout verruimd/afhankelijk gemaakt van bestandsduur (`d4fadc6`, `3048981`).
- **Sample-drift tussen chunks** — chunkgrens rekende in tijd i.p.v. samples waardoor bij lange opnames cumulatieve drift ontstond. Nu sample-exact.
- **Crash bij start opname** — `OnDeviceTranscriber.swift` (crashlog bij record-start). Opgelost samen met de waveform-herbouw (`12:55`-sessie).
- **Windows whisper-decodering** — gesegmenteerde decode i.p.v. één blok + dependency-opschoning (`cad4441`).
- **Windows FFT off-callback** — spectrum-analyse verplaatst van de audio-callback naar een workerthread zodat de callback niet blokkeert (`windows/src-tauri/src/audio/spectrum.rs`, `3048981`).

### Added
- **Cross-platform live mic-envelope** — nieuwe `macos/Services/AudioEnvelopeProcessor.swift` + `windows/src-tauri/src/audio/envelope.rs` (+ `types.rs`, `commands/audio.rs`, `windows/src/hooks/useAudioLevel.ts`) voor gedeelde live-visualisatie-input. Gedekt door `ThoughtVaultTests/AudioEnvelopeProcessorTests.swift` en `tests/fixtures/envelope-fixture.json`.
- **Pitch-responsieve waveform via FFT** — `macos/Services/AudioSpectrumAnalyzer.swift` en Windows Rust-spectrum; waveform reageert op toonhoogte i.p.v. alleen amplitude (`b29d091`, `2fe447d`).
- **Neon soundwave als Metal-shader** — `macos/Shaders/WaveformShader.metal` + herschreven `WaveformView.swift`, een directe port van een aangeleverde WebGL/GLSL-referentie (`23deb80`).
- **Gedeelde `EmptyStateView` + loading-skeleton** en accessibility-labels op kerncomponenten (`6891576`).
- **`scripts/testflight.sh`** — iOS + macOS TestFlight-upload via App Store Connect API-key (`fb2fb80`).

### Changed
- **Opnamepagina 2-koloms layout** gefixt op mobiel/smalle breedte (`RecordingView.swift`, `WaveformView.swift`).
- **Waveform-demping, watchdog-leak, temp-cleanup en echte streaming-decode** als code-review follow-up (`6cff81a`).
- Versie gebumpt naar **v1.0.249**.

### Notes
- Dag bestond uit ~12 deel-sessies; volledige commit-trace in `docs/sessions/2026-07-10.md`.
- CHANGELOG-gap tussen v1.0.130 (2026-06-02) en v1.0.249 is niet retroactief bijgewerkt — buiten scope van deze sessie.

## [2026-06-02] — CLAUDE.md geoptimaliseerd (97 → 62 regels)

### Changed
- **`CLAUDE.md`** afgeslankt zodat minder context elke sessie laadt. Backend-deploy bash-recepten (rsync/scp/ssh) verplaatst naar nieuwe `docs/BACKEND.md`; CLAUDE.md houdt alleen de kernfeiten (server, container, bind-mount deploy-model) + pointer. Karpathy-werkprincipes en macOS code-patterns blijven inline (altijd-aan, project-specifiek).
- **Credentials env-var tabel verwijderd** uit CLAUDE.md — dupliceerde `.env.example` (geverifieerd: alle vars aanwezig). Vervangen door one-line pointer.

### Added
- **`docs/BACKEND.md`** — server-feiten + deploy-commando's voor de productie-backend.

### Notes
- CHANGELOG loopt achter: laatste inhoudelijke entry was v1.0.124, huidige versie is v1.0.130. Backfill valt buiten deze optimalisatie.

## [2026-05-06] — Windows upload pipeline gehard tegen recurring 422 (v1.0.124)

### Fixed
- **Bas's hardnekkige `field required` 422 op 90+ MB uploads** — `windows/src-tauri/src/commands/http.rs` `do_proxy_upload()` volledig herzien. De vorige integrity check uit commit `68273fd` versmaalde het race-window maar sloot het niet — een tweede `tokio::fs::File::open()` ná de pre-flight read liet AV/OneDrive nog tussendoor muteren waardoor `Content-Length` en daadwerkelijke body bytes uit elkaar liepen, wat python-multipart 0.0.17 als ontbrekend `file` veld interpreteerde.
- **Empirische weerlegging python-multipart-hypothese** — een `/tmp/repro-upload/` Rust-binary met identieke reqwest 0.12.28 wire format (zelfde boundary-stijl, lege UA, 100 MB random binary) parseerde foutloos op de productiebackend (gaf 422 `audio_format_unsupported`, niet `field required`). Disculpeert backend volledig; root cause is client-side op Windows.
- **`.gitlab-ci.yml` YAML-syntax (latente bug uit `be88f63`)** — de `update releases.json`-stap gebruikte een PowerShell `@"..."@` heredoc met body op kolom 1, wat het omringende YAML `- |` block scalar dedented en het bestand onparseerbaar maakte. Pipeline #19651 voor v1.0.123 faalde direct in linting. Vervangen door een array van single-line PowerShell strings die met ``-join "`n"`` worden samengevoegd; elke regel staat nu op ≥8 spaties indent.

### Changed
- **`do_proxy_upload()` strategie** (`windows/src-tauri/src/commands/http.rs`):
  1. Bron stabiliseren: `tempfile::Builder::tempfile_in(env::temp_dir())` met TempPath auto-cleanup. Post-copy size-verificatie bij mismatch.
  2. ≤200 MB: `tokio::fs::read()` + `reqwest::multipart::Part::bytes(...)`. Geen streaming, geen Content-Length-vs-body race. Bas's failures (91-168 MB) vallen volledig binnen deze grens.
  3. >200 MB: stream van de integrity-checked temp copy.
  4. WAV magic-byte validatie (`RIFF` + `WAVE`) op in-memory bytes vóór verzending — surface AV-induced corruption als nette client-error.
  5. Reqwest client config: `user_agent("ThoughtVault-Windows/{version}")`, `tcp_nodelay(true)`, `pool_max_idle_per_host(0)`, `http1_only()`, `no_proxy()`, timeout 600 s.
  6. SHA-256 prefix in `[Upload]` log + als `X-Upload-Sha256` request header.
- **Backend `[VALIDATION-422]` log** (`backend/src/insanely_fast_whisper_api/app/app.py:_log_validation_error`): toont nu ook `sha=` (X-Upload-Sha256 van client) en `client=` (peer IP) zodat we bij een eventuele volgende incident-failure client-side hash en server-side hash kunnen vergelijken om body-corruption ondubbelzinnig vast te stellen.

### Added
- **`sha2 = "0.10"`** runtime dependency in `windows/src-tauri/Cargo.toml`.
- **`tempfile = "3"`** verplaatst van `[dev-dependencies]` naar runtime `[dependencies]`.

### Decisions
- DEC-059: Hardened Windows upload pipeline + empirical disproof of python-multipart hypothesis

### Notes
- v1.0.123 tag bestaat maar werd nooit gebouwd door de YAML-fout. v1.0.124 is de eerste daadwerkelijke release met de hardening.
- Backend-wijziging is gedeployd via `rsync ../transcript-studio-backend/.../app.py michelk@3.69.205.209:` + `docker restart n8n_transcript_studio`. Geverifieerd schone start (CUDA actief, queue manager up).
- Productie pipeline draait via tag `v1.0.124` op GitLab CI (https://gitlab.prezent.nl/ai-coding/transcript-studio-native/-/pipelines).
- Reproductie-harness blijft in `/tmp/repro-upload/` voor toekomstige debug-sessies; niet in repo.

---

## [2026-04-01] — Windows TranscriptsPage UX redesign

### Changed
- **TranscriptsPage** (`windows/src/pages/TranscriptsPage.tsx`): Volledig herschreven van 1233-regel monoliet naar 280-regel orchestratie-laag. Notulen/Transcripties tab-split verwijderd — nu één unified document library.
- **Nieuwe componenten**:
  - `windows/src/components/transcripts/TranscriptsList.tsx` — Lijst met date grouping (Vandaag/Gisteren/Deze week/Eerder), dot-indicators (roze=notule, blauw=transcriptie), subtiele tag/profiel badges
  - `windows/src/components/transcripts/TranscriptDetail.tsx` — Document reader met single toolbar (was 4 chrome-lagen), inline titel editing, notule/transcriptie toggle
- **Toolbar redesign**: Alle knoppen hebben labels (Bewerken, Regenereer, Titel, Export, Tags). Logische groepering met separators.
- **CSS** (`globals.css`): Alle `.transcripts-*` klassen vervangen door `.tp-`, `.tl-`, `.td-` prefix. Compactere spacing, dot-indicators i.p.v. grote badges.

### Added
- **Genereer titel** functie: Sparkle-knop in toolbar extraheert titel uit notule-inhoud (headings, bold tekst, paragrafen). Skipt duplicaten en generieke woorden.
- **Inline titel bewerken**: Klik op documenttitel om te bewerken, Enter om op te slaan.
- **Date grouping** in lijst: Items gegroepeerd op dag i.p.v. platte lijst.

### Fixed
- Titel verscheen 3x (lijst, header, document) — nu alleen in document
- "Hertranscribeer" hernoemd naar "Regenereer notulen" (correcte functie)
- Duration "0s" verborgen wanneer geen data beschikbaar
- Titel wrapping: `word-break: break-word` voorkomt mid-woord afkapping
- `bg-blobs` decoratie verwijderd — schone achtergrond

### Notes
- v1.0.110–1.0.111. Geen backend wijzigingen.
- TypeScript clean, build succesvol.

---

## [2026-04-01] — Fix notule titel-extractie bij regeneratie

### Fixed
- **Backend titel-extractie** (`app.py:496`, `transcription.py:103`): Bij regeneratie via de queue callback path (payload zonder `"html"` key) werd geen titel uit de HTML geëxtraheerd. N8n stuurt sectiekoppen zoals "Kernargumenten" als titel — de `_is_valid_callback_title` filterde dit correct, maar de fallback `_extract_title_from_html` werd niet aangeroepen in de `app.py` else-tak.
- **Titellimiet** (`transcription.py:106,120,128`): Verhoogd van 60 naar 80 tekens. Titels als "Notulen Zakelijk Gesprek: AI-Generatie van Website-Styling & Im" werden mid-woord afgekapt.

### Root cause
N8n's "Extract Title" node pakt de eerste HTML heading als titel. Als de LLM het output template niet volgt en een sectiekop als eerste heading genereert (bijv. "Kernargumenten" i.p.v. een beschrijvende titel), stuurt n8n die door. De backend `_is_valid_callback_title` herkent sectiekoppen correct via `_SECTION_WORDS`, maar de queue callback path in `app.py` miste de fallback naar `_extract_title_from_html`.

### Notes
- Fix gedeployed en geverifieerd via test-regeneratie. Titel wordt nu correct geëxtraheerd uit `<h4>` subtitel in de notule HTML.
- E-mail notificatie toont nu ook de juiste titel.
- Backend repo: commit `7bb3396`.

---

## [2026-04-01] — Windows MSI build op GitLab CI met self-hosted runner

### Added
- **Windows GitLab CI runner** (`.gitlab-ci.yml:build-windows`): Self-hosted Windows PC als GitLab Runner (shell executor, tag `windows`). Bouwt MSI volledig standalone zonder afhankelijkheid van de Mac runner. v1.0.104–v1.0.109.
- **SSH key voor Windows runner**: Ed25519 keypair op `C:\Users\michel\.ssh\` voor MSI upload naar EC2 server. Public key geregistreerd op `michelk@3.69.205.209`.

### Changed
- **Tauri config** (`windows/src-tauri/tauri.conf.json`): `useLocalToolsDir: true` toegevoegd. Slaat WiX/NSIS tools op in `target/.tauri/` i.p.v. het restricted SYSTEM profiel `AppData`. Tauri's eigen oplossing voor CI runners die als LocalSystem draaien.
- **MSI zoekpad** (`.gitlab-ci.yml:225`): `windows\src-tauri\...` → `src-tauri\...` en build output naar `..\build\`. De `cd windows` in het eerste script block bleef hangen in GitLab's shell executor, waardoor het pad `windows\windows\src-tauri\...` werd.
- **SSH key fallback** (`.gitlab-ci.yml:233`): Zoekt nu in `$env:USERPROFILE\.ssh\` én `C:\Users\michel\.ssh\` (zelfde patroon als Rust/Cargo lookup). Gebruikt `-i` flag voor expliciete key selectie.
- **Rust PATH** (`.gitlab-ci.yml:177`): Zoekt Cargo in zowel `$env:USERPROFILE` als `C:\Users\michel` — nodig omdat SYSTEM profiel geen Rust installatie heeft.

### Decisions
- DEC-058: Windows MSI build op GitLab CI met self-hosted runner

### Notes
- Runner draait als LocalSystem (SYSTEM account) — `$env:USERPROFILE` is `C:\Windows\system32\config\systemprofile`. Alle paden naar user-specifieke tools (Rust, SSH, WiX) hebben fallback naar `C:\Users\michel`.
- Eerste succesvolle build: v1.0.109 (ThoughtVault_1.0.109_x64.msi, 5.4 MB).
- GitHub Actions Windows build (`.github/workflows/build-windows.yml`) blijft beschikbaar als fallback.

---

## [2026-03-23] — Claude routing voor handleiding-profiel in n8n + WebView CSS fix

### Added
- **n8n Route Profile node** (workflow `Iq3AAf8Vk8eQ9dcZ`): IF-node na Guardrails1 routeert `handleiding` profiel naar Claude, alle andere profielen naar bestaande Ollama route. Voorheen hallucinineerde Ollama (`ministral-3:8b`) generieke content bij de complexe handleiding-template.
- **n8n Claude: Genereer Handleiding node**: HTTP Request naar `http://n8n_claude_code:3100/v1/chat/completions` met 300s timeout, `temperature: 0.4`, `max_tokens: 8192`. Gebruikt zelfde proxy als SEO Blog Pipeline en Yinga AI Weekly.
- **n8n Parse Claude Response node**: Extraheert HTML content uit OpenAI-compatible response format. Zet `response`, `output`, `notule`, `htmlOutput` fields voor compatibiliteit met downstream nodes.

### Changed
- **Backend webhook payload** (`transcription_service.py:680`, `transcription.py:356,525`, `transcripts.py:317`): `profile_id` toegevoegd aan alle 4 webhook payload locaties (auto-trigger, on-device transcriptie, YouTube captions, regeneratie). N8n kan nu routeren op basis van profiel.
- **n8n Extract JSON Data node**: Extraheert `profileId` uit payload (`json.profile_id || 'zakelijk'`).
- **n8n Build Prompts node**: Stuurt `profileId` door naar downstream nodes.
- **n8n Extract Title node**: Stript `<style>` blocks voor titel-extractie en scant nu ook `<h1>` tags. Voorheen werd CSS content als titel geëxtraheerd (`--surface: #fff;`).
- **macOS HTMLWebView** (`NotuleResultView.swift:597`): Detecteert `<style>` tags in HTML content en verplaatst ze naar `<head>`. WKWebView past CSS counters, grid layouts en pseudo-elements niet volledig toe vanuit `<style>` in `<body>`.
- **macOS EditableHTMLWebView** (`EditableHTMLWebView.swift`): Zelfde `<style>` extractie logica voor de bewerkbare notule view.
- **Shared `extractStyles()` helper** (`NotuleResultView.swift`): Regex-gebaseerde extractie van `<style>` blocks, gebruikt door alle 4 WebView varianten (macOS/iOS × HTMLWebView/EditableHTMLWebView) + export.

### Decisions
- DEC-057: Claude routing voor handleiding-profiel via n8n IF-node

### Notes
- Handleiding HTML bevat eigen `<style>` block met CSS custom properties, dark mode, en component classes — skip daardoor de "Convert to HTML" node in n8n.
- Beide paden (Claude + Ollama) convergeren bij "Cleanup LLM Output" → "Extract Title" → callback.

---

## [2026-03-20] — CI/CD migratie van GitHub Actions naar GitLab CI

### Added
- **GitLab CI pipeline** (`.gitlab-ci.yml`): Complete CI/CD pipeline met 5 jobs (prepare, build-macos, build-android, build-windows [disabled], deploy). Alle jobs draaien op Michel's Mac via shell executor. Mac fungeert als sole runner en intermediair naar EC2 server via SSH.
- **Windows-only GitHub Actions** (`.github/workflows/build-windows.yml`): Windows MSI builds blijven op GitHub Actions (`windows-latest` runner) om de 10x macOS billing multiplier te vermijden. Triggered op `v*`/`dev-v*` tags gepusht naar GitHub.
- **GitLab Release script** (`scripts/create-gitlab-release.py`): Losstaand Python script voor GitLab Release creatie via API (geextraheerd uit inline YAML heredoc die de YAML parser brak).

### Changed
- **Post-commit hook** (`.githooks/post-commit`): `git push github main --tags` verwijderd (geen dual-push meer). Monitor URL gewijzigd naar GitLab pipelines.
- **Deploy scripts** (`scripts/deploy-production.sh`, `scripts/deploy-dev.sh`): `github` remote gewijzigd naar `origin`, comments en URLs gewijzigd naar GitLab.
- **RELEASE.md** (`docs/RELEASE.md`): Alle GitHub referenties gewijzigd naar GitLab CI.

### Removed
- **GitHub Actions release workflow** (`.github/workflows/release.yml`): Monolithische workflow vervangen door GitLab CI + Windows-only GitHub Actions.

### Infrastructure
- **gitlab-runner 18.10.0** geinstalleerd op Mac (Homebrew), geregistreerd als shell executor runner "Michel-Mac" met tags `shell,macos,xcode`.
- **Runner config** (`~/.gitlab-runner/config.toml`): JAVA_HOME, ANDROID_HOME, PATH environment variables geconfigureerd.
- **JDK 21** geinstalleerd via Homebrew voor Android builds op Mac.
- **EC2 security group beperking**: EC2 server (3.69.205.209) kan gitlab.prezent.nl niet bereiken op poort 443. Workaround: Mac fungeert als sole runner, SSHt naar EC2 voor deploys.

### Decisions
- DEC-055: GitLab CI als primair CI/CD platform met Mac als sole runner
- DEC-056: GitHub Actions behouden uitsluitend voor Windows MSI builds

---

## [2026-03-20] — Upload pipeline feedback fix (macOS + Windows)

### Fixed
- **Upload errors now visible** (`macos/ViewModels/RecordingViewModel.swift`): Both `catch` blocks in `uploadFile()` set `recordingState = .error(...)` instead of `.idle`. Previously, all upload failures were silently swallowed — the user saw no error message, no retry option, and no indication that the upload had failed.
- **Retry flow simplified** (`RecordingViewModel.swift`, `RecordingView.swift`): Removed fragile `lastFailedUploadURL`/`showRetrySheet`/`retryLastFailedUpload()` mechanism. Replaced with `lastFailedRecording: SavedRecording?` that simply reopens the existing ReprocessSheet with the failed recording. Error banner shows "Opnieuw" button that opens the same reprocess flow as clicking a saved recording — no special retry state needed.
- **Sheet conflict resolved**: Removed the second `.sheet(isPresented: showRetrySheet)` that could conflict with the ReprocessSheet. Only one sheet modifier remains.
- **ReprocessSheet "Start verwerking" button fixed** (`RecordingView.swift`): Switched from `.sheet(isPresented: $showReprocessSheet)` to `.sheet(item: $selectedReprocessRecording)`. The `isPresented` pattern evaluated the sheet content closure before the `@State` update propagated, causing `recording` to be nil inside the sheet — the button was silently disabled. With `.sheet(item:)`, SwiftUI guarantees the recording parameter is non-nil. `ReprocessSheet.recording` changed from `SavedRecording?` to `SavedRecording`, eliminating the entire class of nil-recording bugs.
- **Offline status banner visible** (`RecordingView.swift`): Added `offlineStatusBanner` view that renders `offlineStatusMessage` with wifi.slash icon and dismiss button. Previously, `offlineStatusMessage` was set but never displayed anywhere. Removed the 5-second auto-dismiss timer — message persists until user dismisses it.
- **Timer crash** (`macos/Services/SystemAudioCapture.swift`): Replaced `MainActor.assumeIsolated` with `Task { @MainActor in }` in the duration Timer callback. The `assumeIsolated` assertion crashed on GCD worker threads (`_dispatch_assert_queue_fail` on Thread 4).
- **Screen capture permission simplified** (`RecordingViewModel.swift`): Removed `CGRequestScreenCaptureAccess()` call. On macOS 15+, `SCShareableContent` automatically triggers the correct "System Audio Recording" permission prompt (not "Screen Recording"). Error message updated to reference "Systeemaudio-opname" instead of "Scherm- en systeemaudio-opname".

### Added
- **Background uploads with global ProcessingBar** (`RecordingViewModel.swift`, `ProcessingBar.swift`, `ContentView.swift`): `uploadFile()` now creates a temporary `TranscriptTask` in `activeTasks` and immediately returns `recordingState` to `.idle`. The user can continue using the app while the upload runs. New `ProcessingBar` component in `ContentView.detailView` shows all active uploads and processing tasks across all tabs — with filename, status, progress percentage, animated progress track, and cancel/dismiss actions. On success, the temp task is replaced with the real server task and SSE takes over. On failure, the task shows the error message inline.
- **`updateTask()` helper** (`RecordingViewModel.swift`): Updates status, progress, and error message on an existing `activeTasks` entry by ID.

### Changed
- **Windows SavedRecordings reprocess** (`windows/src/components/recording/SavedRecordings.tsx`): `handleReprocess()` now uses `uploadAndTrack()` instead of fire-and-forget `api.uploadRecording()`. Reprocessed recordings now appear in the ProcessingBar with progress tracking, error messages, and automatic offline queue fallback.
- **Extracted `uploadAndTrack()` utility** (`windows/src/services/uploadAndTrack.ts`): Core upload+SSE+offline-queue logic extracted from `useGlobalRecordingHandler.ts` into a reusable function. Both the global recording handler and SavedRecordings now share the same upload pipeline.
- **Diagnostic logging added** (`RecordingViewModel.swift`, `APIService.swift`): `os_log` statements at every critical decision point in the upload flow.
- **413 error handling** (`APIService.swift`): HTTP 413 now maps to `APIError.fileTooLarge` with Dutch user-facing message instead of showing raw nginx HTML. Non-JSON responses (nginx error pages) are filtered from `extractErrorInfo()`.
- **Revproxy body size limit** (`revproxy03.prezent.nl`): Increased from 100 MB to 500 MB. Previously, uploads >100 MB were silently rejected with a 413 that was invisible (`.idle` state). Now aligned with n8n_nginx (500M) and backend (500 MB).

### Removed
- `lastFailedUploadURL`, `lastFailedUploadReason`, `showRetrySheet` properties from `RecordingViewModel`
- `retryLastFailedUpload()` method, `uploadFailureReason()` helper, `isRetryMode` branch in `ReprocessSheet`
- `uploadProgressView` from `RecordingView` (replaced by global ProcessingBar)
- `UploadFailureReason` enum is now unused (kept in `Models.swift` for now)

### Decisions
- DEC-052: Simplified retry as reprocess, not special state
- DEC-053: Remove CGRequestScreenCaptureAccess on macOS 15+
- DEC-054: Background uploads with global ProcessingBar

### Notes
- macOS build verified: `xcodebuild ... CODE_SIGNING_ALLOWED=NO` — BUILD SUCCEEDED
- Windows TypeScript verified: `npx tsc --noEmit` — no errors
- Revproxy limit was 100 MB (`client_max_body_size 100m`) — confirmed via binary search with curl. Files ≤100 MB passed (422 from backend), 101+ MB got 413 from revproxy.
- The `UploadFailureReason` enum in `Models.swift` is now dead code — can be cleaned up in a future session.

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
