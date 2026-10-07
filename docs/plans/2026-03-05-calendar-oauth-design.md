> Historische documentatie. Actuele desktoparchitectuur en builds: [project-README](/README.md), [releaseproces](/docs/RELEASE.md). Dit document is geen deploy-instructie.

# Kalender OAuth & Per-App Documentatie — Design Document

> Datum: 2026-03-05
> Status: Ontwerp — wacht op review

---

## Samenvatting

Twee deliverables:
1. **Per-applicatie documentatie** — hoe elke platform-app werkt (macOS, Windows)
2. **Kalender OAuth architectuur** — admin-geconfigureerde Microsoft 365 OAuth voor beide platforms, plus Apple Calendar keuze op macOS

---

## 1. Kalender OAuth Architectuur

### 1.1 Probleem

- Windows app heeft `ms365_client_id` en `ms365_tenant_id` nodig maar er is geen admin-endpoint om deze centraal op te slaan
- macOS app biedt alleen EventKit (Apple Calendar), geen Microsoft 365 optie
- OAuth credentials zitten in de lokale Windows settingsStore — niet beheerbaar

### 1.2 Oplossing: Admin-Centraal OAuth Config

```
                    Backend (FastAPI)
                    ─────────────────
  Admin:
    POST /admin/settings  { "ms365_client_id": "...", "ms365_tenant_id": "..." }

  Gebruiker (na login):
    GET /settings/me  → bevat ms365_client_id + ms365_tenant_id
    POST/GET/DELETE /calendar/me  → per-user token opslag (ongewijzigd)

                ▲                          ▲
                │                          │
          ┌─────┴─────┐            ┌───────┴───────┐
          │   macOS   │            │    Windows    │
          │           │            │               │
          │  Keuze:   │            │  Microsoft    │
          │  - Apple  │            │  365 OAuth    │
          │    Calendar│            │  (PKCE flow)  │
          │  - M365   │            │               │
          │    OAuth  │            │               │
          └───────────┘            └───────────────┘
```

### 1.3 Backend Wijzigingen

#### Bestaande admin settings uitbreiden

Het backend key-value systeem (`settings` tabel) ondersteunt al willekeurige keys via `save_setting`/`get_setting`. De admin endpoints `GET/POST /tstudio/api/admin/settings` werken al.

**Nieuwe keys:**

| Key | Waarde | Voorbeeld |
|-----|--------|-----------|
| `ms365_client_id` | Azure App Registration Application (client) ID | `a1b2c3d4-e5f6-...` |
| `ms365_tenant_id` | Azure tenant ID of `common` voor multi-tenant | `common` |

**Geen nieuwe endpoints nodig.** De admin gebruikt het bestaande `POST /tstudio/api/admin/settings` endpoint.

#### Settings/me uitbreiden

`GET /tstudio/api/settings/me` retourneert al per-user settings met profiel-resolutie. Dit endpoint moet de OAuth config meesturen zodat clients weten of Microsoft 365 beschikbaar is:

```json
// GET /tstudio/api/settings/me response (uitbreiding)
{
  "settingsMode": "profile",
  "selectedProfile": "minutes-taker",
  "systemPrompt": "...",
  "notulePrompt": "...",
  "outputTemplate": "...",
  "ms365_client_id": "a1b2c3d4-...",   // NIEUW
  "ms365_tenant_id": "common"           // NIEUW
}
```

Als de admin geen OAuth config heeft ingesteld, worden deze velden weggelaten of `null`. Clients checken op aanwezigheid voordat ze de "Koppel met Microsoft" knop tonen.

#### Calendar endpoints (ongewijzigd)

De bestaande `/calendar/me` endpoints (GET/POST/DELETE) blijven exact hetzelfde. Ze slaan per-user OAuth tokens server-side op.

### 1.4 Windows App Wijzigingen

#### settingsStore aanpassen

De `ms365_client_id` en `ms365_tenant_id` worden nu van de backend gehaald na login in plaats van lokaal opgeslagen:

```typescript
// Na login, in settingsStore of bij app init:
const response = await api.get("/settings/me");
settingsStore.updateSettings({
  ms365_client_id: response.ms365_client_id,
  ms365_tenant_id: response.ms365_tenant_id,
});
```

Uit `AppSettings` interface verwijder je de optionele velden — ze komen van de server.

#### microsoftGraph.ts

Geen wijzigingen nodig. `MicrosoftGraphService.initiateAuth()` leest al `ms365_client_id` en `ms365_tenant_id` uit de settingsStore.

#### SettingsPage kalender-sectie

De "Koppel met Microsoft"-knop wordt conditioneel getoond:
- Geen `ms365_client_id` beschikbaar → toon melding "Agenda-koppeling niet geconfigureerd. Neem contact op met de beheerder."
- Wel beschikbaar + niet gekoppeld → toon "Koppel met Microsoft 365" knop
- Gekoppeld → toon account info + "Ontkoppel" knop (zoals nu)

### 1.5 macOS App Wijzigingen

#### CalendarService uitbreiden

De huidige `CalendarService` wordt uitgebreid met een keuze-mechanisme:

```swift
enum CalendarProvider: String, Codable {
    case apple    // EventKit (huidige implementatie)
    case microsoft // Microsoft Graph OAuth
}
```

**Apple Calendar modus** (default): Werkt exact zoals nu via EventKit. Geen wijzigingen.

**Microsoft 365 modus**: Nieuwe `MicrosoftGraphService` class die:
1. OAuth config ophaalt via `GET /settings/me` (client_id, tenant_id)
2. PKCE OAuth flow start via `ASWebAuthenticationSession`
3. Tokens opslaat via `POST /calendar/me` op de backend
4. Events ophaalt via Microsoft Graph API `/me/calendarView`
5. Events mapt naar bestaand `CalendarEvent` model

De actieve provider wordt opgeslagen in `UserDefaults` (`calendarProvider`).

#### OnboardingView stap 4 (Agenda)

Huidige implementatie vraagt alleen EventKit toegang. Wordt uitgebreid:

```
Stap 4: Agenda
┌─────────────────────────────────────┐
│  Hoe wil je je agenda koppelen?     │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ 🍎 Apple Agenda               │  │
│  │ Gebruikt je macOS kalenders   │  │
│  │ (Outlook, Google, iCloud)     │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ 🔷 Microsoft 365              │  │
│  │ Koppel rechtstreeks met je    │  │
│  │ Microsoft werkaccount         │  │
│  └───────────────────────────────┘  │
│                                     │
│  [ Overslaan ]                      │
└─────────────────────────────────────┘
```

Apple-keuze: vraagt EventKit permission (zoals nu).
Microsoft-keuze: start OAuth flow, toont success/error.
Microsoft-optie alleen zichtbaar als `ms365_client_id` beschikbaar is van backend.

#### SettingsView Agenda-sectie

Huidige sectie toont alleen EventKit status. Wordt uitgebreid met:

- Provider-keuze (Apple/Microsoft) met segmented control
- Bij Apple: huidige EventKit status + meeting lijst (ongewijzigd)
- Bij Microsoft: verbindingsstatus, accountnaam, ontkoppel-knop
- Wisselen van provider reset de vorige verbinding

### 1.6 Token Refresh

**Huidige situatie:** Windows app doet geen token refresh — bij 401 wordt de kalender losgekoppeld.

**Verbetering (beide platforms):** Voeg refresh-logica toe:

```
Token bijna verlopen (< 5 min)?
  → POST naar Microsoft token endpoint met refresh_token
  → Update tokens in calendarStore + backend (/calendar/me)
  → Retry originele request

Refresh mislukt?
  → Disconnect + toon melding
```

Dit wordt geimplementeerd in `MicrosoftGraphService` op beide platforms.

---

## 2. Per-App Documentatie

Drie nieuwe markdown-bestanden in de bestaande docs-directories:

### 2.1 `ThoughtVaultApp/ThoughtVault/docs/APP.md` (macOS)

Inhoud:
- **Overzicht**: Swift 6, SwiftUI, MVVM, @Observable
- **Opname**: drie modi (microfoon, systeemaudio, gecombineerd), AudioRecorder, SystemAudioCapture, waveform visualisatie
- **Transcriptie**: upload naar backend, SSE streaming voortgang, on-device fallback via SFSpeechRecognizer
- **Notulen**: profiel-gebaseerde generatie via n8n, HTML editor, export (DOCX/PDF/TXT)
- **Kalender**: Apple Calendar (EventKit) + Microsoft 365 (OAuth), meeting detectie, CallAlertOverlay
- **Authenticatie**: token-based + biometrisch (Touch ID/Face ID), Keychain opslag
- **Permissies**: Onboarding flow (microfoon, spraak, agenda), System Preferences links
- **Instellingen**: server URL, profiel selectie, on-device transcriptie, permissies, agenda provider

### 2.2 `ThoughtVaultApp/thoughtvault-windows/docs/APP.md` (Windows)

Inhoud:
- **Overzicht**: Tauri 2, React/TypeScript, Zustand stores, Fluent UI
- **Opname**: drie modi, Rust audio backend (cpal/wasapi), waveform visualisatie
- **Transcriptie**: upload naar backend, SSE streaming voortgang
- **Notulen**: profiel-gebaseerde generatie, HTML viewer, export
- **Kalender**: Microsoft 365 OAuth (PKCE), Graph API, CallAlertOverlay, meeting detectie
- **Authenticatie**: token-based, Zustand persistent store
- **Instellingen**: profiel selectie, agenda koppeling, opnamemodus
- **Tauri specifiek**: IPC commands, window management, deep links, system tray

### 2.3 `ThoughtVaultApp/docs/CALENDAR.md` (gedeeld)

Cross-platform kalender-documentatie:
- **Architectuur**: admin OAuth config, per-user tokens, backend opslag
- **Azure App Registration**: stap-voor-stap setup instructies voor admin
- **OAuth flow**: PKCE sequence diagram
- **Microsoft Graph API**: welke endpoints, scopes, data mapping
- **macOS specifiek**: EventKit vs Microsoft 365 keuze, provider switching
- **Windows specifiek**: deep link callback, token refresh
- **Troubleshooting**: veelvoorkomende OAuth fouten, token expiry

---

## 3. Scope & Volgorde

### Fase 1: Backend + Documentatie
1. Admin settings keys (`ms365_client_id`, `ms365_tenant_id`) documenteren
2. `GET /settings/me` uitbreiden om OAuth config mee te sturen
3. Per-app documentatie schrijven (APP.md macOS, APP.md Windows, CALENDAR.md)
4. API.md updaten met OAuth config in admin settings sectie

### Fase 2: Windows OAuth verbetering
5. settingsStore: haal OAuth config van backend i.p.v. lokaal
6. SettingsPage: conditionele "Koppel met Microsoft" knop
7. Token refresh logica in MicrosoftGraphService
8. OnboardingWizard: kalender stap updaten

### Fase 3: macOS Microsoft 365 optie
9. `CalendarProvider` enum + UserDefaults opslag
10. `MicrosoftGraphService.swift` — OAuth PKCE via ASWebAuthenticationSession
11. CalendarService uitbreiden met provider-switching
12. OnboardingView stap 4: keuze Apple/Microsoft
13. SettingsView: provider picker + Microsoft status

### Fase 4: Token refresh (beide platforms)
14. Refresh-logica in Windows MicrosoftGraphService
15. Refresh-logica in macOS MicrosoftGraphService
16. Backend `/calendar/me` tokens updaten bij refresh

---

## 4. Niet in scope

- Google Calendar OAuth (alleen EventKit of Microsoft)
- Kalender-schrijftoegang (alleen lezen)
- Automatisch opname starten bij meeting
- Mobile apps (iOS/iPadOS)
