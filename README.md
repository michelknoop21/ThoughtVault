# TranscriptStudio

Cross-platform desktop app voor vergaderopnames, transcriptie en automatische notulengeneratie. Native macOS client (Swift 6 / SwiftUI) en Windows client (Tauri 2 / React) met een gedeelde FastAPI + Whisper backend.

**Versie:** 1.0.50
**Bundle ID:** `nl.prezent.TranscriptStudio`
**Repository:** [gitlab.prezent.nl/michelk/transcript-studio-native](https://gitlab.prezent.nl/michelk/transcript-studio-native)
**Backend:** `https://n8n.prezent.nl/tstudio/api/`

---

## Inhoudsopgave

- [Wat doet het](#wat-doet-het)
- [Platforms](#platforms)
- [Vereisten](#vereisten)
- [Installatie en ontwikkeling](#installatie-en-ontwikkeling)
- [Bouwen](#bouwen)
- [Testen](#testen)
- [Configuratie](#configuratie)
- [Projectstructuur](#projectstructuur)
- [Technische stack](#technische-stack)
- [Architectuur](#architectuur)
- [Conventies](#conventies)
- [Versiebeheer](#versiebeheer)
- [Bekende issues](#bekende-issues)
- [Documentatie](#documentatie)

---

## Wat doet het

TranscriptStudio neemt vergaderingen op, transcribeert de audio via GPU-versnelde Whisper, en genereert gestructureerde notulen via een LLM-pipeline. Gebruikers starten een opname in een klik, en ontvangen notulen in HTML-formaat die exporteerbaar zijn naar DOCX, PDF, Markdown en plain text.

Kernfunctionaliteit:
- **Opnemen** — microfoon, systeemaudio, of gecombineerd (beide tegelijk)
- **Transcriberen** — cloud (Whisper GPU) of on-device (SFSpeechRecognizer / whisper-rs)
- **Notulen genereren** — cloud (n8n + Ollama) of lokaal (Ollama / LM Studio / Apple Intelligence)
- **Offline-first** — audio wordt altijd lokaal opgeslagen, uploads worden automatisch herhaald bij reconnect
- **Profielen** — configureerbare notitiestijlen per vergadertype (besluitenlijst, actiepunten, etc.)
- **Kalenderintegratie** — EventKit (macOS) / Microsoft Graph (Windows) voor automatische vergaderdetectie
- **Admin panel** — gebruikersbeheer, invite codes, profielbeheer, systeem metrics

---

## Platforms

| Platform | Technologie | Minimaal | Status |
|----------|------------|----------|--------|
| macOS | Swift 6 / SwiftUI / `@Observable` | macOS 14 Sonoma | Productie |
| Windows | Tauri 2.10 / React 19 / TypeScript | Windows 11 | Actieve ontwikkeling |
| iOS | SwiftUI Live Activity (widget only) | iOS 17 | Productie |

---

## Vereisten

### macOS app
- macOS 14 Sonoma of nieuwer
- Xcode 16 of nieuwer
- Code signing: open `TranscriptStudio.xcodeproj` → Signing & Capabilities → stel je Team in

### Windows app
- Node.js 20+
- Rust toolchain via [rustup](https://rustup.rs)
- Tauri CLI: `cargo install tauri-cli`
- Ontwikkeling vereist een Windows-omgeving (VM of native)

### Backend (niet in deze repo)
- Docker + Docker Compose
- NVIDIA GPU met actuele drivers (voor Whisper GPU-transcriptie)
- Draait op AWS EC2 GPU instance

---

## Installatie en ontwikkeling

### macOS

```bash
# Open in Xcode
open TranscriptStudio.xcodeproj

# Of bouw via CLI (zonder code signing)
xcodebuild -project TranscriptStudio.xcodeproj \
  -scheme TranscriptStudio \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO

# Met code signing (vereist provisioning profile)
xcodebuild -project TranscriptStudio.xcodeproj \
  -scheme TranscriptStudio \
  build
```

### Windows

```bash
cd windows
npm install          # MOET binnen Windows-omgeving draaien
npm run tauri dev    # Start development server + Tauri window
```

### Backend

De backend draait apart. Zie de backend repo voor Docker Compose configuratie.

```bash
docker compose up
```

---

## Bouwen

### Geautomatiseerde release build

```bash
# Volledige pipeline: sync versie → build DMG/MSI → upload naar server
./scripts/release.sh

# Alleen bouwen zonder upload
./scripts/release.sh --no-upload
```

Of dubbelklik op de `.command` bestanden in `scripts/` via Finder.

Zie [docs/RELEASE.md](docs/RELEASE.md) voor de complete pipeline documentatie.

### Handmatige builds

```bash
# macOS
xcodebuild -project TranscriptStudio.xcodeproj \
  -scheme TranscriptStudio \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  build

# Windows
cd windows
npm run tauri build
```

---

## Testen

### macOS

```bash
xcodebuild test \
  -project TranscriptStudio.xcodeproj \
  -scheme TranscriptStudioTests
```

### Windows

```bash
cd windows
npm test
```

---

## Configuratie

Beide clients hebben **geen** `.env` bestanden of environment variabelen nodig. Alle configuratie gaat via de Settings-pagina in de app:

| Instelling | Standaard | Beschrijving |
|-----------|----------|-------------|
| Server URL | `https://n8n.prezent.nl` | Backend API endpoint |
| On-device transcriptie | Uit | Schakel lokale SFSpeechRecognizer / whisper-rs in |
| LLM provider | Cloud (n8n) | Keuze uit: Cloud, Ollama, LM Studio, Apple Intelligence |
| Opnamemodus | Microfoon | Keuze uit: Microfoon, Systeemaudio, Gecombineerd |

---

## Projectstructuur

```
TranscriptStudioApp/
│
├── macos/                             # macOS/iOS app (Swift 6, SwiftUI)
│   ├── App/                           # Entry point, ContentView, AppDelegate
│   │   ├── TranscriptStudioApp.swift  #   Window config (1100x750, min 900x600)
│   │   ├── ContentView.swift          #   Root view, collapsible sidebar + TabView (Home, Opnemen, Taken, Notulen, Instellingen, Admin)
│   │   └── AppDelegate.swift          #   MenuBarExtra, FloatingWidgetController
│   ├── Models/                        # Codable data modellen
│   │   ├── Models.swift               #   TranscriptTask, Profile, User, etc.
│   │   ├── TaskStatus.swift           #   10-state pipeline enum
│   │   ├── RecordingMode.swift        #   microphone / systemAudio / combined
│   │   └── QueuedItem.swift           #   OfflineQueue persistence model
│   ├── Services/                      # Business logic en integraties
│   │   ├── APIService.swift           #   actor: REST, SSE, field mapping, retry
│   │   ├── AudioRecorder.swift        #   AVFoundation mic capture, 60 Hz metering
│   │   ├── SystemAudioCapture.swift   #   ScreenCaptureKit system audio
│   │   ├── OnDeviceTranscriber.swift  #   SFSpeechRecognizer / whisper-rs
│   │   ├── LLMService.swift           #   Protocol + provider implementations
│   │   ├── LLMServiceFactory.swift    #   Provider selectie (N8N/Ollama/LMStudio/Apple)
│   │   ├── NetworkMonitor.swift       #   NWPathMonitor reachability
│   │   ├── OfflineQueue.swift         #   Disk-persisted upload queue met retry
│   │   ├── CalendarService.swift      #   EventKit vergaderdetectie
│   │   ├── BiometricService.swift     #   Face ID / Touch ID via LAContext
│   │   ├── KeychainService.swift      #   Secure token storage (Secure Enclave)
│   │   ├── Analytics.swift            #   Usage event tracking
│   │   ├── CrashReporter.swift        #   Crash capture en reporting
│   │   ├── DebugLogger.swift          #   Structured logging
│   │   └── FloatingWidgetController.swift  # NSPanel overlay tijdens opname
│   ├── ViewModels/                    # @Observable, @MainActor
│   │   ├── AuthViewModel.swift        #   Login, biometrie, token lifecycle
│   │   ├── RecordingViewModel.swift   #   Opname state machine, upload, queue
│   │   └── TranscriptsViewModel.swift #   Zoeken, filteren, tags, bulk ops
│   ├── Views/                         # SwiftUI views
│   │   ├── HomeView.swift             #   Landing screen, quick-start
│   │   ├── LoginView.swift            #   Email/wachtwoord + biometrie
│   │   ├── RecordingView.swift        #   Idle setup vs. actieve opname
│   │   ├── TranscriptsView.swift      #   Transcript bibliotheek
│   │   ├── ProcessingView.swift       #   SSE voortgang tijdens transcriptie
│   │   ├── NotuleResultView.swift     #   HTML notulen + export
│   │   ├── SettingsView.swift         #   App voorkeuren
│   │   ├── ProfilesView.swift         #   Profiel CRUD
│   │   ├── AccountView.swift          #   GDPR: data export, account verwijdering
│   │   ├── AdminView.swift            #   Gebruikersbeheer, invite codes
│   │   └── Components/               #   Herbruikbare UI componenten
│   ├── Extensions/                    # Design tokens en kleuren
│   │   ├── Color+Brand.swift          #   Color.brandPrimary, etc.
│   │   └── Theme.swift                #   TS.Spacing, TS.Font, TS.Radius
│   └── Resources/
│       ├── nl.lproj/Localizable.strings  # Nederlands (primair)
│       ├── en.lproj/Localizable.strings  # Engels (fallback)
│       └── TranscriptStudio.entitlements # Sandbox, audio, calendar, ScreenCaptureKit
│
├── windows/                           # Windows app (Tauri 2, React 19)
│   ├── src/                           # React frontend
│   │   ├── components/                #   calendar/, layout/, onboarding/, recording/, etc.
│   │   ├── services/                  #   api.ts, llm.ts, microsoftGraph.ts, sse.ts
│   │   ├── stores/                    #   Zustand stores (auth, recording, transcripts, etc.)
│   │   └── pages/                     #   Home, Login, Recording, Tasks, Transcripts, Settings, Admin
│   └── src-tauri/                     # Rust backend commands
│       └── src/                       #   Audio (WASAPI), auth (keyring), OAuth PKCE, etc.
│
├── ios-widget/                        # iOS Live Activity (Dynamic Island + lock screen)
│
├── docs/                              # Gedetailleerde documentatie
│   ├── README.md                      #   Developer onboarding
│   ├── PRD.md                         #   Product Requirements Document
│   ├── ARCHITECTURE.md                #   Systeemontwerp en directory structuur
│   ├── API.md                         #   Volledige backend API referentie
│   ├── DECISIONS.md                   #   Architectural Decision Records
│   ├── CHANGELOG.md                   #   Versiehistorie
│   └── RELEASE.md                     #   Build & release pipeline
│
├── .githooks/                         # Git hooks (post-commit versioning)
├── VERSION                            # Huidige versie (auto-bumped op main)
├── CLAUDE.md                          # AI assistant instructies
└── .gitignore
```

---

## Technische stack

### macOS / iOS

| Component | Technologie | Versie |
|-----------|-------------|--------|
| Taal | Swift | 6+ (strict concurrency) |
| UI framework | SwiftUI | macOS 14+ / iOS 17+ |
| State management | `@Observable` macro | Swift 5.9+ |
| Concurrency | `actor`, `@MainActor`, `async/await` | Swift Concurrency |
| Audio capture | AVFoundation + ScreenCaptureKit | macOS 13+ |
| Authenticatie | LocalAuthentication (biometrie) + Keychain | — |
| Kalender | EventKit | — |
| Netwerk | URLSession + NWPathMonitor | — |

### Windows

| Component | Technologie | Versie |
|-----------|-------------|--------|
| Framework | Tauri | 2.10 |
| Frontend | React + TypeScript | React 19 |
| Build tool | Vite | — |
| Styling | Tailwind CSS | — |
| State management | Zustand | — |
| Audio capture | WASAPI (via Rust) | — |
| Kalender | Microsoft Graph API + OAuth PKCE | — |
| Icons | Fluent UI | — |

### Backend (aparte repo)

| Component | Technologie |
|-----------|-------------|
| Framework | FastAPI (Python) |
| Transcriptie | insanely-fast-whisper (GPU) |
| Notulengeneratie | n8n + Ollama (ministral-3:8b) |
| Database | PostgreSQL 15 (productie) / SQLite (development) |
| Deployment | Docker Compose op AWS EC2 GPU instance |

---

## Architectuur

### Lagenstructuur (macOS)

```
View (SwiftUI)
    ↓
ViewModel (@Observable, @MainActor — orchestreert)
    ↓
Service (actor/class — businesslogica, API calls, hardware)
    ↓
Model (Codable structs — data representatie)
```

Dit is MVVM met een servicelaag. ViewModels zijn dun en orchestreren; services bevatten de logica.

### Data flow

```
Opname starten
    → AudioRecorder / SystemAudioCapture schrijft WAV naar disk
    → RecordingViewModel stopt opname
    → APIService.upload() stuurt audio naar backend
    → OfflineQueue vangt op als netwerk niet beschikbaar is
    → NetworkMonitor triggert retry bij reconnect
    → SSE stream levert real-time status updates
    → TranscriptsViewModel toont resultaat
```

### Authenticatie flow

```
1. POST /auth/login { username, password }
   → Zonder 2FA: { token, user_id, role }
   → Met 2FA:    { requires_2fa: true, temp_token }

2. POST /auth/login/verify-2fa { username, temp_token, code }
   → { token, user_id, role }

3. Token opgeslagen in OS Keychain (Secure Enclave op macOS)
4. Biometrische login haalt token op via LAContext
5. Alle requests gebruiken X-User-Token header
```

### Cross-platform conventies

| Conventie | Detail |
|-----------|--------|
| Audio formaat | 16 kHz mono 16-bit PCM WAV op beide platforms |
| Offline-first | OfflineQueue op beide platforms, retry bij reconnect |
| Real-time status | SSE stream (geen polling) |
| UI taal | Nederlands (nl_NL) overal |
| Field mapping | Backend veldnamen worden genormaliseerd aan de API-grens per client |
| Auth header | `X-User-Token` (macOS) of `Authorization: Bearer` (Windows) |
| Configuratie | Geen environment variabelen — alles via Settings UI |

---

## Conventies

### macOS (Swift)

- Gebruik `@Observable` — **niet** `ObservableObject` / `@Published` / Combine
- ViewModels zijn `@MainActor` classes
- Services zijn `actor` (thread-safe) of `@Observable class`
- Alle UI strings in het **Nederlands** via `Localizable.strings`
- Design tokens via `TS.Spacing`, `TS.Font`, `TS.Radius` (Theme.swift)
- Kleuren via `Color.brandPrimary`, `Color.labelPrimary` etc. (Color+Brand.swift)
- Field mapping van backend naar Swift types in `APIService.swift` via `CodingKeys`
- `async/await` overal — geen completion handlers, geen Combine

### Windows (TypeScript)

- Zustand stores voor state management
- Field mapping in `src/services/api.ts` — interne code gebruikt nooit backend veldnamen
- Tailwind CSS voor styling met Fluent UI design language
- Tauri IPC commands voor native functionaliteit (audio, keychain, filesystem)

### Beide platforms

- **Kopieer bestaande patronen.** Kijk hoe iets al gedaan wordt voordat je iets nieuws bedenkt.
- **Klein en lokaal.** Bugfix is een bugfix, geen refactorkans.
- **Geen dead code.** Geen uitgecommentarieerde blokken, geen ongebruikte parameters.
- Code en comments in het **Engels**. UI strings in het **Nederlands**.

---

## Versiebeheer

Versies worden automatisch beheerd via een git post-commit hook:

- Elke commit op `main` bumpt automatisch de **patch** versie
- Versie staat in het `VERSION` bestand (auto-bumped)
- Feature branches en detached HEAD triggeren **geen** bump
- Hook activeren: `git config core.hooksPath .githooks`

Handmatig bumpen:

```bash
# VERSION bestand direct aanpassen voor major/minor bumps
echo "2.0.0" > VERSION
git add VERSION && git commit -m "chore: bump major version to 2.0.0"
```

---

## Bekende issues

| Issue | Locatie | Workaround |
|-------|---------|-----------|
| `notifications(for:)` beschikbaar maar crasht | `AuthViewModel.swift` | Gebruik `notifications(named:)` voor async NotificationCenter |
| Sidebar toggle moet per tab verwijderd worden | Alle NavigationStack tabs | Opgelost in v1.0.32: custom collapsible sidebar vervangt `columnVisibility` (DEC-029). `Shift+Cmd+S` toggle. |
| Combined mode audio mixing | `RecordingViewModel` | Gebruikt `mixAudioFiles()` — element-wise max over PCM frames |
| Backend cleanup verwijdert actieve taken | Server-side | `cleanup_old_tasks()` verwijdert taken >24h, ook als ze nog `queued` zijn |
| Apple telefonie (iPhone-doorschakeling) niet opneembaar via Systeemgeluid | `SystemAudioCapture.swift` | Apple routeert FaceTime/iPhone-relay audio via een privé audiopad (`com.apple.avconference` / CoreTelephony) dat niet beschikbaar is voor ScreenCaptureKit. Gebruik in plaats daarvan een VoIP-app (Teams, Zoom, WhatsApp Desktop) op de Mac, of gebruik Microfoon-modus met speaker aan. Een virtuele audio-driver (BlackHole, Loopback) kan als workaround dienen. |

---

## Documentatie

Gedetailleerde documentatie staat in [`docs/`](docs/):

| Document | Beschrijving |
|----------|-------------|
| [README.md](docs/README.md) | Developer onboarding, vereisten, build commando's |
| [PRD.md](docs/PRD.md) | Product Requirements: doelgroep, features, scope, technische eisen |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Systeemontwerp: backend data flow, service laag, directory structuur per platform |
| [API.md](docs/API.md) | Volledige backend API referentie: alle endpoints, auth flows, datamodellen, rate limits |
| [DECISIONS.md](docs/DECISIONS.md) | Architectural Decision Records (ADRs): rationale voor technische keuzes |
| [CHANGELOG.md](docs/CHANGELOG.md) | Versiehistorie en release notes |
| [RELEASE.md](docs/RELEASE.md) | Build & release pipeline: scripts, shortcuts, server-side setup |
| [PLAN-MULTI-INSTANCE.md](docs/PLAN-MULTI-INSTANCE.md) | Roadmap: multi-instance deployment voor meerdere klanten |

---

*Prezent Internet B.V. — TranscriptStudio v1.0.50*
