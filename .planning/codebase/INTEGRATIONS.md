# External Integrations

**Analysis Date:** 2026-06-03

## APIs & External Services

**TranscriptStudio Backend (primary):**
- FastAPI on AWS EC2 GPU — `https://n8n.prezent.nl/tstudio/api/`
- All audio upload, transcript storage, notule generation, profiles, admin
- macOS client: `macos/Services/APIService.swift` (actor, URLSession, `X-User-Token` header)
- Windows client: `windows/src/services/api.ts` (Tauri `invoke` → Rust `reqwest`)
- Android client: Retrofit 3.0 + OKHttp 5.3
- Auth header: macOS sends `X-User-Token`, Windows sends `Authorization: Bearer` — both accepted by backend
- Streaming: SSE endpoint `GET /task/{id}/stream` — implemented in `SSEClient` (macOS `APIService.swift`) and OKHttp SSE (Android)
- Upload limit: 500 MB (enforced client-side and backend)

**n8n Webhook / Notule Pipeline:**
- n8n workflows on the same server handle notule generation via LLM
- `handleiding` profile routes through Claude proxy (`n8n_claude_code:3100`)
- All other profiles route through Ollama on the backend
- Backend sends `profile_id` in webhook payload (see `docs/ARCHITECTURE.md`)

**Microsoft Graph API:**
- Used for Microsoft 365 calendar access and meeting detection
- macOS: `macos/Services/MicrosoftGraphService.swift` (actor, `AuthenticationServices` PKCE)
- Windows: `windows/src/services/microsoftGraph.ts`
- OAuth endpoint: `https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/authorize`
- Graph endpoint: `https://graph.microsoft.com/v1.0`
- Scopes: `User.Read`, `Calendars.Read`
- Redirect URI: `transcript-studio://auth/callback`
- Config (`clientId`, `tenantId`) fetched from backend `/settings/me` and `/admin/settings`
- Calendar tokens persisted to backend via `/calendar/me` endpoints

**Google OAuth (YouTube captions):**
- macOS: `macos/Services/GoogleAuthService.swift` (actor, `AuthenticationServices` PKCE)
- Scope: `https://www.googleapis.com/auth/youtube.force-ssl`
- Redirect URI: `transcript-studio://google/callback`
- `clientId` fetched from backend `/features` response (`google_oauth_client_id_macos`)
- Refresh token stored in macOS Keychain key `"googleRefreshToken"`
- Used when calling `/transcribe-youtube` endpoint with `X-Google-Token` header

**YouTube Transcription:**
- Backend endpoint `POST /transcribe-youtube` handles yt-dlp extraction
- Optional YouTube proxy, cookies, and extractor args configurable via `/admin/settings`
- Feature flag `youtube_transcription` from `/features` endpoint controls UI visibility

**Ollama (local LLM):**
- Default endpoint: `http://localhost:11434` (configurable in Settings)
- OpenAI-compatible `POST /v1/chat/completions` with SSE streaming
- Default model: `llama3.2` (user-configurable via `UserDefaults` key `"ollamaModel"`)
- Optional Ollama Cloud API key stored in Keychain key `"ollamaApiKey"`
- macOS: `OpenAICompatibleLLMService` in `macos/Services/LLMService.swift`

**LM Studio (local LLM, alternative):**
- Default endpoint: `http://localhost:1234`
- Same `OpenAICompatibleLLMService` implementation as Ollama
- Default model: `local-model` (user-configurable via `UserDefaults` key `"lmStudioModel"`)

**Apple Intelligence (FoundationModels):**
- macOS 26+ / iOS 26+ only; guarded with `#if canImport(FoundationModels)` and `#available(macOS 26, *)`
- `AppleFoundationModelService` in `macos/Services/LLMService.swift`
- Zero-network: runs entirely on-device via Apple's Foundation Models framework
- `NotulenProvider.appleIntelligence` case in `macos/Models/Models.swift`

## Data Storage

**Databases:**
- SwiftData (macOS/iOS) — local transcript and notule storage
  - Model: `macos/Models/TranscriptRecord.swift` (`@Model`)
  - Store management: `macos/Services/LocalTranscriptStore.swift`
  - Container setup: `macos/App/TranscriptStudioApp.swift`
- Room 2.8 (Android) — local SQLite ORM
  - Schema directory: `transcript-studio-android/app/schemas/`

**Backend Database:**
- Managed by backend server (not in this repo) — see `docs/BACKEND.md`

**File Storage:**
- Audio recordings: local temp files via `NSTemporaryDirectory()` (macOS) / system temp (Windows/Android)
- macOS: uploaded via streaming multipart to `/transcribe` — temp file deleted after upload
- No persistent cloud file storage integrated in client

**Caching:**
- None — transcripts fetched from backend on demand; local SwiftData acts as cache

**Credentials / Secrets:**
- macOS: Keychain via `macos/Services/KeychainService.swift` (service `nl.prezent.TranscriptStudio`); keys: `authToken`, `googleRefreshToken`, `ollamaApiKey`
- Windows: OS keyring via Rust `keyring 3` crate; Tauri `invoke("get_credential")` / `invoke("set_credential")`
- Android: Google Tink 1.15 for encrypted storage + `androidx.biometric` for biometric auth

**Settings:**
- macOS: `UserDefaults` (keys: `serverURL`, `localTranscriber`, `whisperModel`, `ollamaURL`, `ollamaModel`, `lmStudioURL`, `lmStudioModel`, `notulenProvider`)
- Windows: Tauri Store plugin (`@tauri-apps/plugin-store 2.2`)
- Android: DataStore Preferences 1.1

## Authentication & Identity

**Auth Provider:**
- Custom — backend-managed email/password with optional TOTP 2FA
- Login endpoint: `POST /auth/login` → returns `token`
- 2FA: `POST /auth/login/verify-2fa` → returns final token
- Token stored in Keychain/keyring, sent as `X-User-Token` (macOS) or `Authorization: Bearer` (Windows)
- No third-party auth SDK (Auth0, Firebase, etc.)
- Logout is client-side only (token deleted, no server endpoint)

**Microsoft OAuth:**
- PKCE flow via `AuthenticationServices.ASWebAuthenticationSession`
- Configuration loaded dynamically from backend at startup

**Google OAuth:**
- PKCE flow via `AuthenticationServices.ASWebAuthenticationSession`
- For YouTube captions only (not app authentication)

## Monitoring & Observability

**Error Tracking:**
- `macos/Services/CrashReporter.swift` — stub only; no real SDK integrated. Comment says "Integrate Sentry here when ready"
- `macos/Services/Analytics.swift` — stub only; DEBUG logs to `OSLog`. Comment mentions TelemetryDeck as candidate
- Backend collects errors at `/admin/errors` endpoint

**Logs:**
- macOS: `OSLog` throughout, subsystem `nl.prezent.TranscriptStudio`, per-file categories
- macOS: `macos/Services/DebugLogger.swift` — supplementary debug log wrapper
- Windows: `console.*` via browser devtools / Tauri log plugin
- Android: standard `android.util.Log` / Logcat

## CI/CD & Deployment

**Hosting:**
- macOS app: distributed via `https://n8n.prezent.nl/tstudio/download/`
- Backend: AWS EC2 GPU instance (`michelk@3.69.205.209`), container `n8n_transcript_studio`

**CI Pipeline:**
- GitLab CI (`.gitlab-ci.yml`) — primary pipeline
  - macOS + Android: shell executor runner (tags `macos`, `xcode`, `shell`)
  - Windows MSI: self-hosted Windows PC (tag `windows`)
- GitHub Actions (`.github/workflows/build-windows.yml`) — Windows fallback
- Trigger scripts: `scripts/deploy-dev.sh` (dev-v* tag), `scripts/deploy-production.sh` (v* tag)

**Version Management:**
- `VERSION` file at repo root (`1.0.130`)
- Post-commit git hook (`.githooks/post-commit`) auto-bumps patch on every `main` commit
- `scripts/sync-version.sh` propagates VERSION to `Cargo.toml`, `tauri.conf.json`, Android `build.gradle.kts`

## Webhooks & Callbacks

**Incoming (deep links):**
- `transcript-studio://auth/callback` — Microsoft OAuth PKCE callback
- `transcript-studio://google/callback` — Google OAuth PKCE callback
- Registered in `windows/src-tauri/tauri.conf.json` (`plugins.deep-link.desktop.schemes`)
- macOS: handled via `NSAppleEventManager` / `onOpenURL`

**Outgoing (from backend to n8n):**
- Backend webhook to n8n notule pipeline (URL in backend `/admin/settings` → `webhookUrl`)
- Notification webhook: `notificationWebhookUrl` (separate n8n flow for meeting notifications)

## Environment Configuration

**Required env vars (development tooling only — see `.env.example`):**
- `JIRA_URL`, `JIRA_EMAIL`, `JIRA_TOKEN` — Jira MCP integration
- `N8N_API_KEY`, `N8N_URL` — n8n management
- `TELEGRAM_BOT_TOKEN` — Telegram notifications (Claude tooling)

**App runtime config (not env vars):**
- Server URL: `UserDefaults` key `serverURL` (macOS) / Tauri Store (Windows)
- OAuth client IDs: fetched from backend `/settings/me` and `/features` at runtime — not bundled

---

*Integration audit: 2026-06-03*
