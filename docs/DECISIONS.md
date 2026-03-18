# TranscriptStudio — Architectural Decision Records

_Append-only log. Each entry records context, decision, and consequences._

_Decisions DEC-001 through DEC-028 archived to [archive/DECISIONS-DEC-001-to-DEC-028.md](archive/DECISIONS-DEC-001-to-DEC-028.md)._

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
**Status:** Superseded by DEC-045

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

---

## DEC-037 — Database-Backed Feature Flags met Env Var Fallback

**Date:** 2026-03-15
**Status:** Accepted

**Context:** Feature flags (zoals `FEATURE_YOUTUBE_ENABLED`) waren puur env var-gestuurd. Wijzigen vereiste container restart en SSH-toegang tot de server. Als admin wil je features direct in de UI kunnen in/uitschakelen zonder deployment.

**Decision:** Feature flags worden opgeslagen in de bestaande `Settings` tabel (key-value store) met key `feature_{name}`. De `is_feature_enabled(key, env_default)` functie in `routes/features.py` checkt eerst de database; als er geen DB-entry is, valt het terug op de env var. Admin endpoints `GET /admin/features` en `POST /admin/features/{key}` bieden CRUD. Bekende features zijn gedefinieerd in `FEATURE_FLAGS` dict in `routes/admin.py` met display metadata (label, beschrijving, icoon).

**Consequences:**
- Admin kan features togglen via de web UI zonder container restart of SSH.
- Env vars blijven werken als fallback — bestaande deployments breken niet.
- Nieuwe features toevoegen = 1 entry in `FEATURE_FLAGS` dict + env var default in `config.py`.
- Geen schema-migratie nodig — hergebruikt bestaande `Settings` tabel.
- Feature state is per-instance (niet per-user) — alle gebruikers zien dezelfde features.

---

## DEC-038 — YouTube Anti-Bot Mitigatie met Browser Cookies + EJS Challenge Solver

**Date:** 2026-03-15
**Status:** Accepted

**Context:** YouTube blokkeerde yt-dlp requests vanaf de EC2 server met `ERROR: [youtube] Sign in to confirm you're not a bot`. Root cause analyse toonde drie ontbrekende componenten: (1) geen browser cookies — YouTube ziet geen geauthenticeerde sessie vanaf een datacenter IP, (2) geen JavaScript runtime — yt-dlp 2026.x vereist een JS runtime (Node 20+, Deno 2+, Bun, of QuickJS) om YouTube's Proof of Origin challenges op te lossen, (3) geen EJS scripts — de challenge solver distributie (`yt-dlp-ejs`) was niet geïnstalleerd. Node v12 (Ubuntu 22.04 default) bleek te oud; `quickjs` Python binding werkte evenmin.

**Decision:** Drie wijzigingen in de backend: (1) `youtube_service.py` — `_extra_ytdlp_args()` voegt `--cookies /app/cookies.txt` en `--js-runtimes node:/usr/local/bin/node` toe aan alle yt-dlp subprocess calls. `_ytdlp_cmd()` gebruikt `sys.executable -m yt_dlp` i.p.v. het binary om conda/pip dependency conflicten te vermijden. (2) `Dockerfile` — Node.js 20.18.3 LTS binary geïnstalleerd in `/usr/local/bin/node` (tar download, geen apt). `yt-dlp` vervangen door `yt-dlp[default]` dat `yt-dlp-ejs` als dependency meebrengt. (3) `config.py` — `YOUTUBE_COOKIES_FILE` env var (default `/app/cookies.txt`) configureerbaar. Cookies geëxporteerd vanuit Firefox via `yt-dlp --cookies-from-browser firefox`.

**Consequences:**
- YouTube transcriptie werkt weer vanaf de EC2 server (geverifieerd: metadata ophalen + audio download succesvol).
- Cookies zijn niet permanent — ze verlopen en moeten periodiek vernieuwd worden vanuit een browser met actieve YouTube login.
- Node.js 20 LTS en yt-dlp-ejs zijn persistent in de Docker image — overleven container rebuilds.
- De cookies.txt staat op de bind-mounted code directory (`/app/cookies.txt`), niet in de Docker image — bewust om credentials uit het image te houden.

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
