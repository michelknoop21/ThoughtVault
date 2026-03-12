# TranscriptStudio Backend API — Volledige Referentie

> Gedeelde documentatie voor alle platforms (macOS, Windows, Web).
> Backend: FastAPI op `https://n8n.prezent.nl/tstudio/api/`

## Inhoud

- [Architectuuroverzicht](#architectuuroverzicht)
- [Authenticatie](#authenticatie)
- [Middleware & Beveiliging](#middleware--beveiliging)
- [Auth Endpoints](#auth-endpoints)
- [Transcriptie Endpoints](#transcriptie-endpoints)
- [Task & SSE Streaming](#task--sse-streaming)
- [Transcripts CRUD](#transcripts-crud)
- [Notes (Notulen)](#notes-notulen)
- [Profielen](#profielen)
- [Instellingen](#instellingen)
- [Kalender](#kalender)
- [Feedback](#feedback)
- [Admin Endpoints](#admin-endpoints)
- [n8n Workflow Integratie](#n8n-workflow-integratie)
- [Datamodellen](#datamodellen)
- [Foutafhandeling](#foutafhandeling)
- [Rate Limiting](#rate-limiting)

---

## Architectuuroverzicht

```
┌──────────────┐     ┌──────────────┐     ┌─────────────────────────┐
│  macOS App   │     │ Windows App  │     │   Web (HTMX)            │
│  Swift/SwiftUI│     │ Tauri/React  │     │   Server-rendered        │
└──────┬───────┘     └──────┬───────┘     └───────────┬─────────────┘
       │                    │                         │
       │  X-User-Token      │  Authorization: Bearer   │  Cookie/Token
       │                    │  (via Tauri proxy)       │
       └────────────────────┼─────────────────────────┘
                            │
                ┌───────────▼───────────┐
                │   FastAPI Backend     │
                │   /tstudio/api/*      │
                │   (Python)            │
                └───────────┬───────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
     ┌────────▼──┐  ┌──────▼──────┐  ┌───▼────────┐
     │ PostgreSQL│  │  Whisper    │  │  n8n       │
     │ Database  │  │  GPU        │  │  Workflow   │
     └───────────┘  └─────────────┘  └────────────┘
                                          │
                                     ┌────▼────┐
                                     │ Ollama  │
                                     │ LLM     │
                                     └─────────┘
```

De backend draait als FastAPI applicatie met SQLAlchemy en PostgreSQL (productie). SQLite wordt ondersteund als fallback voor lokale development. Audio wordt getranscribeerd met Insanely Fast Whisper op GPU. Notulen worden gegenereerd via een n8n workflow die Ollama (ministral-3:8b) aanstuurt.

---

## Authenticatie

### Token-gebaseerde authenticatie

De backend gebruikt **opaque UUID tokens** (geen JWT). Na succesvolle login wordt een token gegenereerd en opgeslagen in de `users.auth_token` kolom.

### Token verzenden

**macOS app** — custom header:
```
X-User-Token: <token>
```

**Windows app** — Bearer header (via Tauri proxy):
```
Authorization: Bearer <token>
```

**Beide worden geaccepteerd door de backend.** De auth-middleware checkt eerst `X-User-Token`, dan `Authorization: Bearer`.

### Admin authenticatie

Server-to-server communicatie (n8n callbacks) gebruikt:
```
X-Admin-API-Key: <ADMIN_KEY>
```
De `ADMIN_KEY` is een environment variable op de server.

### Token levensduur

- Sliding window van **7 dagen** inactiviteit
- Elke succesvolle request verlengt de expiry
- Bij logout wordt het token uit de database verwijderd

### 2FA flow

```
Stap 1: POST /auth/login { username, password }
  → requires_2fa: true, temp_token: "..."

Stap 2: POST /auth/login/verify-2fa { username, temp_token, code }
  → token: "...", user_id: "...", role: "user"
```

De `temp_token` is 5 minuten geldig en wordt in-memory bewaard.

---

## Middleware & Beveiliging

| Middleware | Beschrijving |
|-----------|-------------|
| **CORS** | Origins via `CORS_ORIGINS` env var. Standaard: `https://n8n.prezent.nl`. Methoden: GET, POST, PUT, DELETE, OPTIONS |
| **CSRF** | Valideert `Origin`/`Referer` op POST/PUT/DELETE/PATCH. Exempt: `/callback`, `/queue/callback`, `/task/`, `/health` |
| **Rate Limiting** | Via SlowAPI, per-endpoint (zie [Rate Limiting](#rate-limiting)) |
| **Error Logging** | Vangt unhandled exceptions, logt naar `error_logs` tabel |

---

## Auth Endpoints

### POST `/tstudio/api/auth/login`
Login stap 1. **Rate limit: 5/minuut.**

```json
// Request
{ "username": "user@email.com", "password": "wachtwoord" }

// Response (geen 2FA)
{ "requires_2fa": false, "user_id": "uuid", "token": "uuid", "role": "user" }

// Response (2FA vereist)
{ "requires_2fa": true, "temp_token": "uuid", "message": "2FA code vereist" }
```

> **Let op:** Het veld heet `username`, niet `email`. De macOS app stuurt het e-mailadres als username.

### POST `/tstudio/api/auth/login/verify-2fa`
Login stap 2 bij actieve 2FA. **Rate limit: 5/5 minuten.**

```json
// Request
{ "username": "user@email.com", "temp_token": "uuid", "code": "123456" }

// Response
{ "requires_2fa": false, "user_id": "uuid", "token": "uuid", "role": "user" }
```

### POST `/tstudio/api/auth/register`
Registratie (vereist invite code).

```json
// Request
{ "username": "user@email.com", "password": "wachtwoord", "invite_code": "ABC123" }

// Response
{
  "user_id": "uuid",
  "username": "user@email.com",
  "qr_code": "data:image/png;base64,...",
  "totp_secret": "BASE32SECRET",
  "require_2fa_setup": true
}
```

### POST `/tstudio/api/auth/verify-2fa-setup`
Bevestig 2FA na registratie.

```json
// Request
{ "username": "user@email.com", "code": "123456" }

// Response
{ "token": "uuid" }
```

### POST `/tstudio/api/auth/logout`
Invalideer sessie-token. Auth optioneel (werkt ook zonder).

### GET `/tstudio/api/auth/validate`
Valideer of het huidige token geldig is.

### GET `/tstudio/api/auth/me`
Haal huidige gebruiker op. **Vereist authenticatie.**

```json
// Response
{
  "user_id": "uuid",
  "username": "user@email.com",
  "name": "Jan Jansen",
  "role": "user"
}
```

### POST `/tstudio/api/auth/change-password`
Wijzig eigen wachtwoord. **Vereist authenticatie.**

```json
{ "current_password": "oud", "new_password": "nieuw" }
```

### POST `/tstudio/api/auth/update-email`
Update username naar e-mailadres. **Vereist authenticatie.**

### 2FA beheer

| Endpoint | Methode | Beschrijving |
|----------|---------|-------------|
| `/tstudio/api/auth/2fa/setup` | POST | Start 2FA setup, retourneert QR code |
| `/tstudio/api/auth/2fa/verify-setup` | POST | Bevestig 2FA, retourneert backup codes |
| `/tstudio/api/auth/2fa/disable` | POST | Schakel 2FA uit (vereist wachtwoord) |
| `/tstudio/api/auth/2fa/regenerate-backup-codes` | POST | Genereer nieuwe backup codes |
| `/tstudio/api/auth/2fa/status` | GET | 2FA status opvragen |

### Wachtwoord reset

| Endpoint | Methode | Rate Limit | Beschrijving |
|----------|---------|-----------|-------------|
| `/tstudio/api/auth/password-reset/request` | POST | 3/15min | Vraag reset code aan (per e-mail) |
| `/tstudio/api/auth/password-reset/verify` | POST | 5/5min | Verifieer code, krijg reset_token |
| `/tstudio/api/auth/password-reset/complete` | POST | 3/5min | Stel nieuw wachtwoord in met reset_token |

---

## Transcriptie Endpoints

### POST `/tstudio/api/transcribe`
Upload audiobestand voor transcriptie. **Rate limit: 10/uur.**

```
Content-Type: multipart/form-data
Velden:
  - file: audio/wav bestand (max 200 MB)
  - profile_id: "default" of custom profile ID
  - mode: "microphone" | "combined" (optioneel)
```

```json
// Response
{ "task_id": "uuid", "status": "queued", "queue_position": 1, "message": "..." }
```

### POST `/tstudio/api/transcribe-text`
Stuur al getranscribeerde tekst (voor on-device transcriptie). **Rate limit: 20/uur.**

```json
// Request
{ "transcription": "Volledige tekst...", "profile_id": "default" }

// Response
{ "task_id": "uuid", "status": "queued" }
```

### POST `/tstudio/api/task/{task_id}/regenerate`
Genereer notulen opnieuw met ander profiel.

```json
// Request
{ "task_id": "uuid", "new_profile_id": "minutes-taker" }
```

### POST `/tstudio/api/queue/webhook`
Handmatig een task in de n8n webhook queue plaatsen.

```json
// Request
{
  "task_id": "uuid",
  "webhook_url": "optioneel — gebruikt globale instelling",
  "transcription": "optioneel override",
  "system_prompt": "optioneel",
  "notule_prompt": "optioneel",
  "output_template": "optioneel",
  "profile_id": "optioneel"
}
```

### POST `/tstudio/api/notify-admin`
Meld guardrails-blokkering aan admin per e-mail. **Vereist authenticatie.**

### GET `/tstudio/api/health`
Health check (geen auth vereist).

```json
// Response
{ "model": "...", "device": "cuda", "max_upload_size": 200 }
```

---

## Task & SSE Streaming

### GET `/tstudio/api/task/{task_id}`
Poll task status. Auth optioneel.

```json
// Response: TranscriptTask
{
  "task_id": "uuid",
  "status": "transcribing",
  "progress": 45.0,
  "raw_transcription": null,
  "notule_html": null,
  "error_message": null,
  "filename": "recording.wav",
  "profile_id": "default",
  "created_at": "2026-03-05T10:00:00Z"
}
```

### GET `/tstudio/api/task/{task_id}/stream`
**Server-Sent Events** stream voor real-time voortgang.

```
Accept: text/event-stream
Auth: X-User-Token header OF ?token=<encoded_token> query parameter
```

SSE data format:
```
event: update
data: {"task_id":"uuid","status":"transcribing","progress":45.0,...}

event: done
data: {"task_id":"uuid","status":"completed","notule_html":"<p>...</p>",...}
```

Terminale events: `done`, `completed`. Terminale statussen: `completed`, `error`, `failed`, `cancelled`.

### GET `/tstudio/api/tasks/active`
Lijst actieve taken voor huidige gebruiker.

### Task Status Flow

```
pending → uploading → converting → transcribing → transcribed → queued → processing_webhook → completed
                                          ↘ no_speech (hallucination detected)              → error
```

| Status | Beschrijving |
|--------|-------------|
| `pending` | Task aangemaakt, wacht op verwerking |
| `uploading` | Bestand wordt ontvangen |
| `converting` | Audio wordt geconverteerd naar juist formaat |
| `transcribing` | Whisper verwerkt audio |
| `transcribed` | Transcriptie klaar, wacht op notulen |
| `queued` | In webhook queue voor n8n |
| `processing_webhook` | n8n verwerkt notulengeneratie |
| `completed` | Alles klaar, notulen beschikbaar |
| `no_speech` | Hallucination detection: audio bevat geen herkenbare spraak (Whisper output was garbled/repetitief) |
| `error` | Fout opgetreden |

---

## Transcripts CRUD

Alle endpoints vereisen `X-User-Token` authenticatie.

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/transcripts` | Lijst transcripties. Query: `?search=&tags=tag1,tag2` |
| GET | `/tstudio/api/transcripts/tags` | Alle unieke tags van de gebruiker |
| GET | `/tstudio/api/transcripts/{task_id}` | Enkel transcript met metadata en gelinkte notulen |
| PUT | `/tstudio/api/transcripts/{task_id}` | Update tekst, titel of tags |
| DELETE | `/tstudio/api/transcripts/{task_id}` | Verwijder transcript |
| PATCH | `/tstudio/api/transcripts/{task_id}/tags` | Tags toevoegen/verwijderen |
| GET | `/tstudio/api/transcripts/{task_id}/notes` | Notulen opvragen |
| POST | `/tstudio/api/transcripts/{task_id}/regenerate` | Notulen opnieuw genereren |
| GET | `/tstudio/api/transcripts/{task_id}/export` | Exporteer. Query: `?format=txt\|docx` |
| POST | `/tstudio/api/transcripts/bulk-delete` | Bulk verwijderen: `{ "ids": [...] }` |
| POST | `/tstudio/api/transcripts/bulk-export` | Bulk export als ZIP: `?format=txt\|docx` |
| POST | `/tstudio/api/transcripts/bulk-tags` | Bulk tags: `{ "ids": [...], "tags": [...], "action": "add\|remove" }` |

### PUT `/tstudio/api/transcripts/{task_id}`

```json
{
  "transcription": "bewerkte tekst of null",
  "title": "nieuwe titel of null",
  "tags": ["tag1", "tag2"],
  "reset_to_original": false
}
```

### PATCH `/tstudio/api/transcripts/{task_id}/tags`

```json
{ "add": ["nieuwe-tag"], "remove": ["oude-tag"] }
```

---

## Notes (Notulen)

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/notes` | Lijst eigen notulen |
| POST | `/tstudio/api/notes` | Maak notule aan |
| GET | `/tstudio/api/notes/{note_id}` | Haal notule op. Query: `?format=json\|pdf\|html` |
| PUT | `/tstudio/api/notes/{note_id}` | Update notule HTML (maakt versie-backup) |
| DELETE | `/tstudio/api/notes/{note_id}` | Verwijder notule |
| POST | `/tstudio/api/notes/bulk-delete` | Bulk verwijderen: `{ "ids": [...] }` |
| POST | `/tstudio/api/notes/bulk-download` | Download als ZIP: `{ "ids": [...], "format": "pdf" }` |

### POST `/tstudio/api/notes`

```json
{ "title": "optionele titel", "html": "<p>Inhoud</p>", "source_file": "audio.mp3" }
```

### PUT `/tstudio/api/notes/{note_id}`

```json
{ "html": "<p>Bijgewerkte inhoud</p>", "title": "optionele nieuwe titel" }
```

---

## Profielen

### Publieke profielen (geen auth)

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/settings/profiles` | Alle profielen (id, naam, beschrijving, icoon) |

### Eigen profielen (auth vereist)

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/profiles/me` | Eigen profielen + count/limit info |
| POST | `/tstudio/api/profiles/me` | Maak profiel aan (max 10 per gebruiker) |
| GET | `/tstudio/api/profiles/me/{profile_id}` | Enkel profiel ophalen |
| PUT | `/tstudio/api/profiles/me/{profile_id}` | Profiel bijwerken |
| DELETE | `/tstudio/api/profiles/me/{profile_id}` | Profiel verwijderen |
| PATCH | `/tstudio/api/profiles/me/{profile_id}/visibility` | Toggle publieke zichtbaarheid |

### Template Store

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/profiles/public` | Browse publieke profielen. Query: `?search=&sort=popular&limit=20&offset=0` |
| GET | `/tstudio/api/profiles/{profile_id}/preview` | Preview met voorbeelddata |
| POST | `/tstudio/api/profiles/{profile_id}/copy` | Kopieer naar eigen collectie |
| GET | `/tstudio/api/profiles/accessible` | Alle toegankelijke profielen (default + eigen + publiek) |

### Profiel aanmaken

```json
{
  "name": "Vergadernotulen",
  "description": "Voor teamvergaderingen",
  "icon": "📋",
  "systemPrompt": "Je bent een vergadersecretaris...",
  "notulePrompt": "Maak gestructureerde notulen...",
  "outputTemplate": "<h1>{{title}}</h1>...",
  "isPublic": false
}
```

---

## Instellingen

| Methode | Endpoint | Auth | Beschrijving |
|---------|----------|------|-------------|
| GET | `/tstudio/api/settings` | Nee | Globale instellingen |
| POST | `/tstudio/api/settings` | Nee | Globale instellingen opslaan (legacy) |
| GET | `/tstudio/api/settings/me` | Ja | Per-gebruiker instellingen met profiel-resolutie |
| POST | `/tstudio/api/settings/me` | Ja | Per-gebruiker instellingen opslaan |

### GET `/tstudio/api/settings/me`

Response bevat per-gebruiker instellingen met profiel-resolutie. Indien de admin Microsoft 365 OAuth heeft geconfigureerd, worden `ms365_client_id` en `ms365_tenant_id` meegestuurd:

```json
{
  "settingsMode": "profile",
  "selectedProfile": "minutes-taker",
  "systemPrompt": "...",
  "notulePrompt": "...",
  "outputTemplate": "...",
  "ms365_client_id": "a1b2c3d4-e5f6-...",
  "ms365_tenant_id": "common"
}
```

> `ms365_client_id` en `ms365_tenant_id` zijn optioneel — alleen aanwezig als de admin deze via `/admin/settings` heeft ingesteld. Clients tonen de "Koppel met Microsoft" knop alleen als deze velden aanwezig zijn.

### POST `/tstudio/api/settings/me`

Profiel-modus:
```json
{ "settingsMode": "profile", "selectedProfile": "minutes-taker" }
```

Custom modus:
```json
{
  "settingsMode": "custom",
  "systemPrompt": "...",
  "notulePrompt": "...",
  "outputTemplate": "..."
}
```

---

## Kalender

Microsoft 365 OAuth tokens worden server-side opgeslagen voor cross-device sync.

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/calendar/me` | Haal OAuth tokens op |
| POST | `/tstudio/api/calendar/me` | Sla OAuth tokens op |
| DELETE | `/tstudio/api/calendar/me` | Ontkoppel kalender |

### POST `/tstudio/api/calendar/me`

```json
{
  "accessToken": "eyJ...",
  "refreshToken": "0.AAAA...",
  "tokenExpiry": 1735689600000,
  "accountName": "Jan Jansen",
  "accountEmail": "jan@bedrijf.com",
  "monitoringEnabled": true
}
```

---

## Feedback

### Gebruiker

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| POST | `/tstudio/api/feedback` | Dien feedback in (triggert admin e-mail) |
| GET | `/tstudio/api/feedback/my` | Eigen feedback met admin-reacties |
| GET | `/tstudio/api/feedback/unread-count` | Aantal ongelezen reacties |
| POST | `/tstudio/api/feedback/{id}/mark-read` | Markeer als gelezen |

### POST `/tstudio/api/feedback`

```json
{ "category": "bug|feature|general", "title": "Titel", "description": "Beschrijving..." }
```

### Admin

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/admin/feedback` | Alle feedback. Query: `?status=&category=&user_id=` |
| GET | `/tstudio/api/admin/feedback/{id}` | Detail |
| PUT | `/tstudio/api/admin/feedback/{id}` | Status/reactie bijwerken |
| DELETE | `/tstudio/api/admin/feedback/{id}` | Verwijderen |
| GET | `/tstudio/api/admin/feedback/pending-count` | Aantal nieuw/onbeoordeeld |

---

## Admin Endpoints

Alle admin endpoints accepteren `X-User-Token` (admin-rol) **of** `X-Admin-API-Key`.

### Gebruikersbeheer

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/admin/users` | Alle gebruikers met note count |
| POST | `/tstudio/api/admin/users` | Gebruiker aanmaken |
| POST | `/tstudio/api/admin/users/{id}/password` | Wachtwoord resetten |
| DELETE | `/tstudio/api/admin/users/{id}` | Gebruiker + alle data verwijderen |
| POST | `/tstudio/api/admin/users/{id}/2fa/reset` | 2FA resetten |
| GET | `/tstudio/api/admin/users/{id}/2fa/status` | 2FA status |

### Uitnodigingen

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| POST | `/tstudio/api/admin/invites` | Maak invite code: `{ "max_uses": 1, "expires_hours": 48 }` |
| GET | `/tstudio/api/admin/invites` | Lijst alle invite codes |
| DELETE | `/tstudio/api/admin/invites/{code}` | Verwijder invite code |

### Profielen (admin)

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/admin/profiles` | Alle profielen met volledige prompts |
| GET | `/tstudio/api/admin/profiles/{id}` | Enkel profiel |
| PUT | `/tstudio/api/admin/profiles/{id}` | Profiel bijwerken |
| POST | `/tstudio/api/admin/profiles/{id}/reset` | Reset naar defaults |

### Logging & Metrics

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/admin/errors` | Error logs. Query: `?limit=&severity=&user_id=&search=&start_date=&end_date=` |
| GET | `/tstudio/api/admin/activity` | Activity logs. Query: `?limit=&user_id=&action_type=&start_date=&end_date=` |
| GET | `/tstudio/api/admin/metrics` | Dashboard metrics (simpel) |
| GET | `/tstudio/api/admin/dashboard/metrics` | Dashboard metrics (gedetailleerd). Query: `?days=7` |
| POST | `/tstudio/api/admin/errors/export` | Exporteer error logs als CSV |
| POST | `/tstudio/api/admin/logs/cleanup` | Verwijder oude logs. Query: `?days=90` |

### Instellingen (admin)

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/admin/settings` | Globale settings (webhookUrl, notificationWebhookUrl, ms365_client_id, ms365_tenant_id) |
| POST | `/tstudio/api/admin/settings` | Globale settings bijwerken |

**POST body (alle velden optioneel):**
```json
{
  "webhookUrl": "https://...",
  "notificationWebhookUrl": "https://...",
  "ms365_client_id": "Azure App Registration client ID",
  "ms365_tenant_id": "Azure tenant ID of 'common' voor multi-tenant"
}
```

### Notulen (admin)

| Methode | Endpoint | Beschrijving |
|---------|----------|-------------|
| GET | `/tstudio/api/admin/notes` | Alle notulen van alle gebruikers |
| DELETE | `/tstudio/api/admin/notes/{id}` | Verwijder notule |

---

## n8n Workflow Integratie

De backend communiceert asynchroon met n8n voor notulengeneratie:

```
1. Client uploadt audio → Backend transcribeert met Whisper
2. Backend stuurt POST naar n8n webhook URL (/tstudio)
   Body: { task_id, transcription, system_prompt, notule_prompt, output_template, callback_url, user_email }
3. n8n verwerkt via Ollama (ministral-3:8b) + guardrails
4. n8n stuurt resultaat terug via POST /tstudio/api/callback/notule
```

### POST `/tstudio/api/callback/notule` (n8n → backend)

**Auth:** `X-Admin-API-Key` header of `callback_admin_key` in body. CSRF exempt.

```json
{
  "task_id": "uuid",
  "title": "Vergadernotulen 5 maart",
  "html": "<h1>Notulen</h1><p>...</p>",
  "notule": null,
  "htmlOutput": null,
  "output": null,
  "filename": "recording.mp3",
  "requested_by": "user@email.com",
  "error": null,
  "callback_admin_key": "optioneel"
}
```

> **Bekende issue:** De `cleanup_old_tasks()` functie verwijdert taken ouder dan 24 uur bij serverstart, ook als ze nog `queued` of `processing_webhook` zijn. Dit kan 404-fouten veroorzaken bij n8n callbacks.

---

## Datamodellen

### TranscriptTask

Centraal object, geretourneerd door `/transcribe`, `/transcribe-text`, `/task/{id}`, en SSE stream:

```json
{
  "task_id": "uuid",
  "status": "pending|uploading|converting|transcribing|transcribed|queued|processing_webhook|completed|error",
  "progress": 0.0-100.0,
  "raw_transcription": "string|null",
  "notule_html": "string|null",
  "error_message": "string|null",
  "filename": "string",
  "profile_id": "string|null",
  "tags": ["string"],
  "created_at": "ISO8601"
}
```

### Transcript

```json
{
  "id": "string",
  "title": "string",
  "raw_transcription": "string|null",
  "notule_html": "string|null",
  "tags": ["string"],
  "created_at": "ISO8601",
  "duration": 120.5,
  "profile_name": "string|null"
}
```

### Profile

```json
{
  "id": "string",
  "name": "string",
  "description": "string|null",
  "icon": "string|null",
  "system_prompt": "string",
  "notule_prompt": "string",
  "output_template": "string|null",
  "is_default": true,
  "is_public": false,
  "user_id": "string|null"
}
```

### User (auth response)

```json
{
  "user_id": "string",
  "username": "string (e-mail)",
  "name": "string|null",
  "role": "user|admin"
}
```

---

## Foutafhandeling

### Response formaat

Bij fouten retourneert de backend JSON met een van deze velden:
- `"detail"` (FastAPI/Pydantic validatiefouten)
- `"message"` (applicatiefouten)
- `"error"` (generieke fouten)

### HTTP statuscodes

| Code | Betekenis |
|------|----------|
| 200 | Succes |
| 201 | Aangemaakt |
| 400 | Ongeldige request |
| 401 | Niet geauthenticeerd / sessie verlopen |
| 403 | Geen toegang (verkeerde rol) |
| 404 | Resource niet gevonden |
| 422 | Validatiefout (check veldnamen!) |
| 429 | Rate limit bereikt |
| 500 | Serverfout |

### Sessiebeheer bij 401

**macOS:** `APIError.sessionExpired` → post `authDidInvalidate` notification → 10 seconden grace period (max 3 fouten) → force logout.

**Windows:** Token wordt gewist uit Zustand store → redirect naar login pagina.

---

## Rate Limiting

| Endpoint | Limiet |
|----------|--------|
| POST `/auth/login` | 5/minuut |
| POST `/auth/login/verify-2fa` | 5/5 minuten |
| POST `/auth/password-reset/request` | 3/15 minuten |
| POST `/auth/password-reset/verify` | 5/5 minuten |
| POST `/auth/password-reset/complete` | 3/5 minuten |
| POST `/transcribe` | 10/uur |
| POST `/transcribe-text` | 20/uur |

---

## Versie check

### GET `/tstudio/api/version`

Geen auth vereist.

```json
{
  "minimum_version": "1.0.0",
  "current_version": "1.2.0",
  "is_supported": true
}
```

De macOS app vergelijkt semantic versions en blokkeert verouderde clients.
