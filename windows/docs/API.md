# TranscriptStudio Windows — Backend API Communicatie

> Platform-specifieke documentatie voor de Tauri 2 / React / TypeScript Windows app.
> Zie ook: `../../docs/API.md` voor de volledige backend API referentie.

## Architectuur

```
React Components
    → Zustand Stores
        → API Service (api.ts)
            → Tauri invoke("proxy_request")
                → Rust reqwest::Client
                    → https://n8n.prezent.nl/tstudio/api/*

SSE:
    → EventSource (browser-native, NIET via Tauri proxy)
        → ?token=<encoded> query parameter
```

**Belangrijk:** Alle HTTP requests (behalve SSE en lokale LLM) gaan via de Tauri Rust proxy om WebView CORS-restricties te omzeilen.

### Bestanden

| Bestand | Rol |
|---------|-----|
| `src/services/api.ts` | Alle API endpoints + request helper |
| `src/services/sse.ts` | SSE client (EventSource) |
| `src/services/llm.ts` | Lokale LLM communicatie |
| `src/services/tauriCommands.ts` | Tauri IPC command wrappers |
| `src/services/offlineQueue.ts` | Offline upload queue |
| `src/stores/authStore.ts` | Auth state + token persistence |
| `src/types.ts` | TypeScript type definities |
| `src-tauri/src/commands/http.rs` | Rust HTTP proxy commands |
| `src-tauri/src/commands/auth.rs` | Keyring credential opslag |

---

## Configuratie

| Setting | Waarde | Bron |
|---------|--------|------|
| Base URL | `https://n8n.prezent.nl` | `localStorage["settings-store"]` → `state.server_url` |
| Token | UUID string | `localStorage["auth-store"]` → `state.token` |

---

## Authenticatie

### Token header

```
Authorization: Bearer <token>
```

De Windows app gebruikt **Bearer auth**, anders dan de macOS app (die `X-User-Token` gebruikt). De backend accepteert beide.

### Token opslag

- **Primair:** Zustand persist → `localStorage["auth-store"]` → `{ token, user }`
- **Secure:** OS Keyring via Tauri command `store_credential` / `load_credential`
  - Service: `nl.prezent.transcript-studio`
  - Backend: Windows Credential Manager

### JWT fallback

Als de `LoginResponse` geen `user` object bevat, decodeert de client het token als JWT:

```typescript
const payload = JSON.parse(atob(token.split(".")[1]));
// payload.sub / payload.user_id, payload.email, payload.name, payload.role
```

### Login flow

```typescript
// Stap 1
const response = await api.login(email, password);
// POST /tstudio/api/auth/login { email, password }

if (response.requires_2fa) {
  // Bewaar temp_token in component state
  const final = await api.verify2FA(tempToken, code);
  // POST /tstudio/api/auth/2fa/verify { temp_token, code }
  authStore.setToken(final.token, final.user);
} else {
  authStore.setToken(response.token, response.user);
}
```

> **Let op:** De Windows app stuurt `{ email, password }` maar de backend verwacht `{ username, password }`. Dit veroorzaakt HTTP 422 fouten. De backend accepteert `email` niet als veldnaam.

### Logout

```typescript
await api.logout(); // POST /tstudio/api/auth/logout
authStore.clear();  // Zustand: { token: null, user: null, isAuthenticated: false }
```

---

## Tauri HTTP Proxy Commands

### `proxy_request` — Generieke HTTP proxy

```rust
// Input
struct HttpRequest {
    url: String,
    method: String,      // GET, POST, PUT, PATCH, DELETE, HEAD
    headers: Option<HashMap<String, String>>,
    body: Option<String>, // JSON string
}

// Output
struct HttpResponse {
    status: u16,
    body: String,
    headers: HashMap<String, String>,
}
```

Timeout: **30 seconden.**

### `http_upload_file` — Multipart upload

```rust
// Parameters
url: String,
file_path: String,            // absoluut pad op schijf
field_name: String,           // "file"
additional_fields: Option<HashMap<String, String>>,  // { profile_id, mode }
headers: Option<HashMap<String, String>>,
```

Timeout: **120 seconden.** Leest bestandsbytes via `tokio::fs::read`, bouwt multipart/form-data met MIME type `audio/wav`.

### `http_sse_stream` — Tauri SSE (beschikbaar maar ongebruikt)

```rust
// Parameters
app: AppHandle,
url: String,
headers: Option<HashMap<String, String>>,
event_name: String,  // Tauri event naam per chunk
```

Timeout: **300 seconden.** Emit `event_name` per `data:` regel, `event_name + "-done"` bij `[DONE]` of stream-einde.

> De huidige SSE implementatie gebruikt browser-native `EventSource` (zie hieronder), niet deze Tauri command.

---

## SSE Streaming

De `SSEClient` class in `sse.ts` gebruikt de browser `EventSource` API:

```typescript
const urlWithAuth = `${baseUrl}/tstudio/api/tasks/${taskId}/stream?token=${encodeURIComponent(token)}`;
const eventSource = new EventSource(urlWithAuth);
```

Token wordt als **query parameter** meegegeven omdat `EventSource` geen custom headers ondersteunt.

Terminale statussen: `completed`, `failed`, `cancelled` → automatische disconnect.

---

## Endpoints API calls

### Upload (transcriptie)

```typescript
const result = await api.uploadRecording(filePath, profileId, mode);
// Tauri: invoke("http_upload_file", {
//   url: `${baseUrl}/tstudio/api/transcribe`,
//   filePath, fieldName: "file",
//   additionalFields: { profile_id, mode },
//   headers: { Authorization: `Bearer ${token}` }
// })
// Response: { task_id: string }
```

### Transcripts

```typescript
// Lijst
const transcripts = await api.getTranscripts({ search, tags, limit, offset });
// GET /tstudio/api/transcripts?search=&tags=a,b&limit=N&offset=N

// Detail
const transcript = await api.getTranscript(id);
// GET /tstudio/api/transcripts/:id

// Update
await api.updateTranscript(id, { title, tags });
// PATCH /tstudio/api/transcripts/:id

// Verwijderen
await api.deleteTranscript(id);
// DELETE /tstudio/api/transcripts/:id

// Regenereren
const { task_id } = await api.regenerateTranscript(id, profileId);
// POST /tstudio/api/transcripts/:id/regenerate { profile_id }
```

### Profielen

```typescript
const profiles = await api.getProfiles();
// GET /tstudio/api/profiles

const profile = await api.createProfile({ name, system_prompt, notule_prompt, notule_template });
// POST /tstudio/api/profiles

await api.updateProfile(id, updates);
// PUT /tstudio/api/profiles/:id

await api.deleteProfile(id);
// DELETE /tstudio/api/profiles/:id
```

### Admin

```typescript
const users = await api.getAdminUsers();
// GET /tstudio/api/admin/users → AdminUser[] | { items?: [], users?: [] }

const user = await api.createAdminUser({ email, password, name, role });
// POST /tstudio/api/admin/users

await api.deleteAdminUser(userId);
// DELETE /tstudio/api/admin/users/:userId

const reports = await api.getBugReports();
// GET /tstudio/api/admin/bug-reports

const health = await api.getSystemHealth();
// GET /tstudio/api/admin/health

const invite = await api.createInviteCode();
// POST /tstudio/api/admin/invite-codes
```

---

## Offline Queue

Bestand: `src/services/offlineQueue.ts`
Opslag: `offline-queue.json` via `@tauri-apps/plugin-store`

Bij geen netwerkverbinding:
1. Upload wordt gequeued met `{ file_path, profile_id, mode }`
2. `processQueue()` herprobeert `api.uploadRecording()` tot max **5 pogingen**
3. Na 5 mislukkingen wordt het item verwijderd

---

## Lokale LLM communicatie

Bij `ollama` of `lm-studio` provider, directe `fetch()` vanuit WebView (geen Tauri proxy):

```typescript
// POST http://localhost:11434/v1/chat/completions (Ollama)
// POST http://localhost:1234/v1/chat/completions  (LM Studio)

const body = {
  model: modelName,
  messages: [
    { role: "system", content: profile.system_prompt },
    { role: "user", content: `${profile.notule_prompt}\n\n---\n\n${transcription}` }
  ],
  stream: true
};
```

Response: streaming SSE met `choices[0].delta.content` chunks.

`cloud` provider: gooit direct error — cloud generatie is volledig server-side.

---

## Platform-specifieke verschillen t.o.v. macOS

| Aspect | macOS | Windows |
|--------|-------|---------|
| Auth header | `X-User-Token: <token>` | `Authorization: Bearer <token>` |
| HTTP client | URLSession (direct) | reqwest via Tauri proxy |
| SSE auth | Header (`X-User-Token`) | Query param (`?token=`) |
| Token opslag | Keychain (`kSecAttr...`) | Zustand/localStorage + Keyring |
| Login veld | `{ username: email }` | `{ email: email }` (bug: 422 error) |
| Logout | Client-side only | POST `/auth/logout` + client-side |
| Retry | 2x exponential (1s, 2s) | Geen retry in api.ts |
| Biometrisch | Face ID / Touch ID via LAContext | Windows Hello (geplanned) |
| Upload timeout | 300s (resource) | 120s (Tauri) |

---

## Bekende issues

1. **Login veld mismatch:** De Windows `api.ts` stuurt `{ email, password }` maar de backend verwacht `{ username, password }`. Dit geeft HTTP 422. Fix: verander `email` naar `username` in de login request body.

2. **Recording page mock:** De RecordingPage handlers gebruiken `setTimeout` stubs i.p.v. Tauri audio commands. UI is compleet maar niet verbonden met de Rust backend.

3. **Admin users response:** Backend retourneert soms `{ items: [...] }` of `{ users: [...] }` i.p.v. een directe array. De client handelt beide formats af.
