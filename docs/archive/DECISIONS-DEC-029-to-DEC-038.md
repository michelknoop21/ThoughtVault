# ThoughtVault — Archived Decisions (DEC-029 to DEC-038)

_Archived from main DECISIONS.md on 2026-03-18._

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

**Context:** ThoughtVault is currently a single-tenant system — one backend container, one database, one n8n flow. To serve multiple customers, two approaches were evaluated: (1) multi-tenant — adding an organization layer throughout the entire stack (database, auth, API, clients), estimated at 3-4 weeks of development with high security risk from potential data isolation bugs; (2) multi-instance — deploying a separate backend container + database + Redis index per customer using the same Docker image, requiring only deployment tooling with zero application code changes for the basic setup.

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

**Context:** De repository had inconsistente directory-namen: `ThoughtVault/` (CamelCase) voor de macOS source, `transcript-studio-windows/` (kebab-case) voor Windows, en `RecordingActivityWidget/` (CamelCase) voor de iOS widget. Met de toevoeging van `transcript-studio-android/` werd de naamgeving nog onoverzichtelijker. Nieuwe ontwikkelaars en AI-assistenten moesten telkens raden welke conventie gebruikt werd.

**Decision:** Hernoem naar consistente lowercase platform namen: `macos/`, `windows/`, `ios-widget/`. Laat `ThoughtVault.xcodeproj` en `ThoughtVaultTests` ongemoeid — deze zijn gekoppeld aan Xcode schemes, targets en build settings; hernoemen zou disproportioneel risico opleveren voor minimale winst. Gebruik `git mv` om history te behouden.

**Consequences:**
- Alle build scripts, CI/CD workflows, .gitignore, en documentatie moesten bijgewerkt worden (~20 bestanden).
- Xcode `project.pbxproj` vereiste exacte pad-aanpassingen voor group path, entitlements, en Info.plist referenties.
- Historische plan-bestanden (`docs/plans/`, `.claude/plans/`) zijn niet bijgewerkt — ze zijn snapshots van eerdere sessies.
- Toekomstige platform directories volgen nu automatisch het patroon: `android/`, `web/`, etc.

---

## DEC-035 — YouTube Transcriptie via Backend Download (niet Client Upload)

**Date:** 2026-03-14
**Status:** Accepted

**Context:** YouTube-video's moesten transcribeerbaar worden in ThoughtVault. Twee architecturale opties: (1) client downloadt audio en uploadt naar backend zoals bij normale opnames, of (2) client stuurt alleen de URL, backend downloadt de audio zelf via `yt-dlp`. Optie 1 zou yt-dlp op elke client vereisen (complexe native dependency op macOS/Windows/Android) en grote downloads over het netwerk twee keer verplaatsen (YouTube → client → server).

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

**Context:** Externe systemen (scripts, CI/CD, integraties) moeten de ThoughtVault API kunnen aanspreken zonder interactieve login. Sessie-tokens zijn ongeschikt: ze verlopen na 7 dagen inactiviteit en vereisen username/password om te verkrijgen. Een API key systeem is nodig dat (1) veilig is bij database-lekken, (2) scope-beperking ondersteunt, en (3) geen nieuwe aanvalsvectoren introduceert voor key-replicatie.

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
