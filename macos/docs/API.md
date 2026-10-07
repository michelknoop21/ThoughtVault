# ThoughtVault macOS — Backend API Communicatie

> Platform-specifieke documentatie voor de Swift/SwiftUI macOS app.
> Zie ook: `../../docs/API.md` voor de volledige backend API referentie.

## Architectuur

```
SwiftUI Views
    → ViewModels (@Observable)
        → APIService (actor, thread-safe)
            → URLSession
                → https://n8n.prezent.nl/tstudio/api/*
```

### Bestanden

| Bestand | Rol |
|---------|-----|
| `Services/APIService.swift` | Alle HTTP communicatie (actor) |
| `Services/KeychainService.swift` | Token opslag in macOS Keychain |
| `Services/LLMService.swift` | Lokale LLM communicatie (Ollama/LM Studio/Apple Intelligence) |
| `Models/Models.swift` | Alle request/response types |
| `ViewModels/AuthViewModel.swift` | Authenticatie flow |

---

## Configuratie

| Setting | Waarde | Bron |
|---------|--------|------|
| Base URL | `https://n8n.prezent.nl` | `UserDefaults["serverURL"]`, wijzigbaar |
| HTTPS | Verplicht | `URLValidationError.httpsRequired` |
| Request timeout | 30 seconden | `URLSessionConfiguration` |
| Resource timeout | 300 seconden | `URLSessionConfiguration` |

---

## Authenticatie

### Token header

```
X-User-Token: <token>
```

Alle authenticated requests gebruiken deze custom header. Dit is **niet** Bearer auth.

### Token opslag

- **Keychain service:** `com.buildmind.ThoughtVault`
- **Key:** `authToken`
- **Accessibility:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- **Biometrisch:** Tweede item `biometricToken` voor Face ID / Touch ID login

### Sessie-invalidatie

Bij HTTP 401 → `APIError.sessionExpired` → `Notification.Name("authDidInvalidate")`:
- 10 seconden grace period
- Max 3 fouten getolereerd
- Daarna force logout (Keychain tokens verwijderd)

### Login flow

```swift
// Stap 1: Login
let response = try await APIService.shared.login(username: email, password: password)

// Response check
if response.requires_two_factor == true {
    // Bewaar temp_token, toon 2FA invoer
    let finalResponse = try await APIService.shared.verify2FA(
        tempToken: response.temp_token!,
        code: userCode
    )
    // Sla finalResponse.token op in Keychain
} else {
    // Sla response.token op in Keychain
}
```

---

## Endpoints overzicht

### Audio upload

```swift
// Multipart/form-data upload
let task = try await APIService.shared.uploadAudio(
    fileURL: wavURL,        // max 200 MB
    profileId: "default",
    progressHandler: { progress in /* 0.0 - 1.0 */ }
)
// task: TranscriptTask met task_id en status
```

Multipart boundary: `Boundary-<UUID>`
Velden: `file` (audio/wav), `profile_id` (string)

### Tekst upload (on-device transcriptie)

```swift
let task = try await APIService.shared.uploadTranscriptionText(
    transcription: "Volledige tekst...",
    profileId: "default"
)
```

### SSE streaming

```swift
let (url, token) = try await APIService.shared.taskStreamInfo(taskId: "uuid")
// url: https://n8n.prezent.nl/tstudio/api/task/<id>/stream
// token: X-User-Token waarde

let sseClient = SSEClient()
sseClient.connect(to: url, token: token) { event in
    // event.data → TranscriptTask JSON
    // Terminal: event.type == "done" || "completed"
}
```

Headers op SSE request:
```
Accept: text/event-stream
X-User-Token: <token>
Cache-Control: no-cache
```

Reconnect: exponential backoff, max 5 pogingen, cap 16 seconden.

### Transcripts

```swift
// Lijst ophalen
let response = try await APIService.shared.getTranscripts(
    page: 1, limit: 20, search: "zoekterm", sortBy: "desc"
)
// response.items: [Transcript], response.total: Int?

// Enkel transcript
let transcript = try await APIService.shared.getTranscript(id: "uuid")

// Verwijderen
try await APIService.shared.deleteTranscript(id: "uuid")

// Titel wijzigen
try await APIService.shared.renameTranscript(id: "uuid", title: "Nieuwe titel")

// Tags wijzigen
try await APIService.shared.updateTranscriptTags(id: "uuid", tags: ["tag1", "tag2"])

// Regenereren
let task = try await APIService.shared.regenerateTranscript(
    transcriptId: "uuid", profileId: "minutes-taker"
)
```

### Profielen

```swift
let profiles = try await APIService.shared.getProfiles()
let profile = try await APIService.shared.createProfile(
    name: "Vergadering",
    systemPrompt: "...",
    notulePrompt: "...",
    template: "optioneel"
)
try await APIService.shared.deleteProfile(id: "uuid")
```

### Admin

```swift
let users = try await APIService.shared.getAdminUsers()
let stats = try await APIService.shared.getAdminStats()
let invitations = try await APIService.shared.getAdminInvitations()
let bugReports = try await APIService.shared.getAdminBugReports()
let errors = try await APIService.shared.getAdminErrors()

try await APIService.shared.createAdminUser(email: "...", role: "user", name: "...")
try await APIService.shared.deleteAdminUser(id: "uuid")
try await APIService.shared.createAdminInvitation(email: "...", role: "user")
try await APIService.shared.updateBugReportStatus(id: "uuid", status: "resolved")
```

### Versie check

```swift
let version = try await APIService.shared.checkMinimumVersion()
// version.minimum_version, version.is_supported
```

---

## Retry logica

Niet-auth, niet-decode fouten worden **2x** herhaald:
- 1 seconde na eerste fout
- 2 seconden na tweede fout

SSE reconnects: `2^attempt` seconden, cap 16s, max 5 pogingen.

---

## Lokale LLM communicatie

Wanneer `NotulenProvider` is `ollama` of `lmStudio`:

```
POST http://localhost:11434/v1/chat/completions  (Ollama)
POST http://localhost:1234/v1/chat/completions   (LM Studio)
```

```json
{
  "model": "<model_name>",
  "stream": true,
  "messages": [
    { "role": "system", "content": "<systemPrompt>" },
    { "role": "user", "content": "<notulePrompt + transcription [+ template]>" }
  ]
}
```

Headers: `Content-Type: application/json`, `Accept: text/event-stream`

Beschikbaarheidscheck:
- Ollama: `GET http://localhost:11434/api/tags`
- LM Studio: `GET http://localhost:1234/v1/models`

Lange transcripties (> 8.000 tekens Ollama/LM Studio, > 12.000 Apple Intelligence) worden eerst in chunks samengevat.

`cloud` provider: stub — generatie volledig server-side via n8n.
`appleIntelligence` provider: `FoundationModels.LanguageModelSession` (macOS 26+).

---

## Bekende veldnaam-mismatch

Het login endpoint verwacht `"username"` (niet `"email"`). De Swift APIService stuurt het e-mailadres correct als username-veld:

```json
{ "username": "user@email.com", "password": "..." }
```

> **Gotcha:** Als je het veld `"email"` stuurt krijg je HTTP 422 terug.
