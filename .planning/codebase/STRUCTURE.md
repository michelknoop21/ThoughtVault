# Codebase Structure

**Analysis Date:** 2026-06-03

## Directory Layout

```
transcript-studio-native/        # Repo root
├── macos/                       # macOS + iOS Swift sources (shared target)
│   ├── App/                     # App entry point + root navigation
│   ├── Models/                  # Value types, enums, SwiftData model
│   ├── ViewModels/              # @MainActor @Observable ViewModels
│   ├── Views/                   # SwiftUI screen views
│   │   └── Components/          # Reusable UI components
│   ├── Services/                # I/O services (networking, audio, storage)
│   ├── Extensions/              # Design tokens (Theme.swift, Color+Brand.swift)
│   ├── Resources/               # Localization strings
│   │   ├── nl.lproj/            # Dutch (primary)
│   │   └── en.lproj/            # English
│   └── Assets.xcassets/         # Images, colors, icons
├── windows/                     # Windows Tauri 2 app
│   ├── src/                     # React/TypeScript frontend
│   │   ├── components/          # Reusable React components
│   │   │   ├── layout/          # TitleBar, Sidebar
│   │   │   ├── brand/           # Brand components
│   │   │   ├── calendar/        # Calendar/meeting overlay
│   │   │   ├── onboarding/      # Onboarding wizard
│   │   │   ├── recording/       # Recording UI components
│   │   │   ├── settings/        # Settings components
│   │   │   ├── transcripts/     # Transcript list/detail components
│   │   │   └── ui/              # Generic UI primitives (ErrorBoundary, InfoBar…)
│   │   ├── pages/               # Top-level route pages
│   │   ├── stores/              # Zustand state stores
│   │   ├── services/            # API calls, SSE, offline queue, crash reporter
│   │   ├── hooks/               # Custom React hooks
│   │   └── types.ts             # Shared TypeScript type definitions
│   └── src-tauri/               # Rust Tauri backend
│       ├── src/
│       │   ├── commands/        # IPC command handlers
│       │   │   ├── audio.rs     # Recording start/stop/pause/resume
│       │   │   ├── auth.rs      # Credential store/load/delete
│       │   │   ├── filesystem.rs# Recordings dir, cleanup, WAV concat
│       │   │   ├── http.rs      # HTTP proxy, upload, SSE stream
│       │   │   └── system.rs    # Network status, meeting app detection
│       │   ├── audio/           # Audio capture types and recorder
│       │   ├── lib.rs           # Tauri app setup, plugin registration
│       │   └── main.rs          # Binary entry point
│       └── capabilities/        # Tauri permission declarations
├── transcript-studio-android/   # Android app (Kotlin + Jetpack Compose)
│   └── app/src/main/java/nl/prezent/transcriptstudio/
│       ├── data/                # local (Room), model, remote (Retrofit), repository
│       ├── di/                  # Hilt dependency injection
│       ├── service/             # Background services
│       └── ui/                  # Compose screens by feature
├── ios-widget/                  # iOS Live Activity widget extension
│   └── RecordingActivityWidget.swift
├── TranscriptStudioTests/       # XCTest test suite
├── TranscriptStudio.xcodeproj/  # Xcode project
├── docs/                        # Architecture, API, decision log, release docs
│   ├── API.md                   # FastAPI endpoint reference
│   ├── ARCHITECTURE.md          # High-level system architecture (human docs)
│   ├── DECISIONS.md             # Decision log (DEC-NNN entries)
│   ├── BACKEND.md               # Backend deploy/ops guide
│   └── PLAN-MULTI-INSTANCE.md   # Multi-tenant deployment plan
├── scripts/                     # Release, deploy, version sync scripts
├── .gitlab-ci.yml               # CI/CD pipeline (macOS + Windows + Android)
├── .github/workflows/           # GitHub Actions (Windows fallback)
├── VERSION                      # Single source of version string
└── CLAUDE.md                    # Project-level AI coding instructions
```

## Directory Purposes

**`macos/App/`:**
- Purpose: App entry point, root navigation shell, menu bar extra
- Key files: `TranscriptStudioApp.swift` (`@main`), `ContentView.swift` (navigation + auth gate)

**`macos/Models/`:**
- Purpose: All shared value types and enums; no SwiftUI or UIKit imports
- Key files: `Models.swift` (all domain enums: `RecordingState`, `RecordingMode`, `ProcessingMode`, `NotulenProvider`, `TaskStatus`, `Transcript`, `TranscriptTask`, `Profile`, `CalendarEvent`…), `TranscriptRecord.swift` (SwiftData `@Model`), `ProfileTemplates.swift` (default profile definitions)

**`macos/ViewModels/`:**
- Purpose: UI-facing state machines; all `@MainActor @Observable final class`
- Key files: `RecordingViewModel.swift`, `AuthViewModel.swift`, `TranscriptsViewModel.swift`, `TasksViewModel.swift`

**`macos/Views/`:**
- Purpose: SwiftUI screen views, one file per screen
- Key files: `RecordingView.swift`, `TranscriptsView.swift`, `HomeView.swift`, `SettingsView.swift`, `LoginView.swift`, `NotuleResultView.swift`

**`macos/Views/Components/`:**
- Purpose: Reusable UI pieces with no navigation logic
- Key files: `WaveformView.swift`, `TranscriptCard.swift`, `ProcessingBar.swift`, `ProfilePicker.swift`, `EditableHTMLWebView.swift`, `StatusBadge.swift`

**`macos/Services/`:**
- Purpose: All I/O: network, audio hardware, on-device ML, local storage, system services
- Key files: `APIService.swift` (Swift `actor`), `AudioRecorder.swift`, `SystemAudioCapture.swift`, `LocalTranscriber.swift`, `LLMService.swift`, `LocalTranscriptStore.swift`, `OfflineQueue.swift`, `KeychainService.swift`

**`macos/Extensions/`:**
- Purpose: Design system tokens; import this instead of hardcoding values
- Key files: `Theme.swift` (`TS.Spacing`, `TS.Font`, `TS.Radius`, `TS.Animation`), `Color+Brand.swift` (`Color.brandPrimary`, `Color.labelPrimary`, etc.)

**`windows/src/stores/`:**
- Purpose: Zustand global state (mirrors macOS ViewModels)
- Key files: `recordingStore.ts`, `authStore.ts`, `transcriptsStore.ts`, `settingsStore.ts`, `uploadQueueStore.ts`

**`windows/src/services/`:**
- Purpose: All async I/O: API calls, SSE, offline queue, crash reporting
- Key files: `api.ts` (all FastAPI calls via Tauri `proxy_request`), `sse.ts`, `offlineQueue.ts`, `tauriCommands.ts`

**`windows/src-tauri/src/commands/`:**
- Purpose: Rust IPC handlers invoked from TypeScript via `invoke()`
- Key files: `audio.rs`, `auth.rs`, `filesystem.rs`, `http.rs`, `system.rs`

## Key File Locations

**Entry Points:**
- `macos/App/TranscriptStudioApp.swift` — `@main`, SwiftUI app lifecycle
- `windows/src/main.tsx` — React render root
- `windows/src-tauri/src/main.rs` — Tauri binary entry point
- `windows/src-tauri/src/lib.rs` — Tauri builder, plugin registration, IPC handler registration

**Configuration:**
- `VERSION` — single version string, read by all platform builds
- `CLAUDE.md` — coding rules and gotchas for this project
- `docs/API.md` — FastAPI endpoint reference (read before adding API calls)
- `docs/DECISIONS.md` — decision log (DEC-NNN format)

**Core Logic:**
- `macos/ViewModels/RecordingViewModel.swift` — central recording + processing state machine
- `macos/Services/APIService.swift` — all backend HTTP calls
- `macos/Services/LLMService.swift` — notulen generation protocol + all implementations
- `macos/Services/LocalTranscriber.swift` — on-device STT protocol + factory
- `macos/Models/Models.swift` — canonical domain types

**Testing:**
- `TranscriptStudioTests/AuthViewModelTests.swift`
- `TranscriptStudioTests/TranscriptsViewModelTests.swift`
- `TranscriptStudioTests/TranscriptDecoderTests.swift`
- `windows/src/services/__tests__/` — Windows service unit tests

## Naming Conventions

**Files (Swift):**
- `PascalCase.swift` matching the primary type name
- ViewModels: `<Name>ViewModel.swift` (e.g., `RecordingViewModel.swift`)
- Views: `<Name>View.swift` (e.g., `RecordingView.swift`)
- Services: `<Name>Service.swift` or descriptive noun (e.g., `AudioRecorder.swift`, `OfflineQueue.swift`)

**Files (TypeScript/React):**
- Components: `PascalCase.tsx`
- Pages: `<Name>Page.tsx`
- Stores: `camelCaseStore.ts` (e.g., `recordingStore.ts`)
- Services: `camelCase.ts` (e.g., `api.ts`, `offlineQueue.ts`)
- Hooks: `use<Name>.ts` (e.g., `useGlobalRecordingHandler.ts`)

**Types (Swift):**
- Enums: `PascalCase` with `camelCase` cases
- Structs/Classes: `PascalCase`
- Protocols: `PascalCase` (e.g., `LLMService`, `LocalTranscriber`)

**Types (TypeScript):**
- Interfaces/types: `PascalCase` (e.g., `RecordingMode`, `TranscriptTask`)
- Zustand stores: `use<Name>Store` (e.g., `useRecordingStore`)

## Where to Add New Code

**New macOS/iOS screen:**
- View: `macos/Views/<Name>View.swift`
- ViewModel (if needed): `macos/ViewModels/<Name>ViewModel.swift` — `@MainActor @Observable final class`
- Register in tab enum: `macos/App/ContentView.swift` → `AppTab`

**New service (I/O, network, hardware):**
- `macos/Services/<Name>Service.swift` or `<Name>.swift`
- Use `actor` for pure I/O; use `@Observable final class` only if the service needs to publish observable state directly to SwiftUI

**New domain model / enum:**
- Add to `macos/Models/Models.swift` unless it is a SwiftData persistent model, in which case: `macos/Models/<Name>.swift` with `@Model`

**New API endpoint (macOS):**
- Add method to `actor APIService` in `macos/Services/APIService.swift`
- Reference `docs/API.md` for endpoint contract before implementing

**New Windows page:**
- Page component: `windows/src/pages/<Name>Page.tsx`
- Route in: `windows/src/App.tsx`
- State: add to or create a store in `windows/src/stores/`

**New Tauri IPC command:**
- Add Rust handler to appropriate file in `windows/src-tauri/src/commands/`
- Register in `windows/src-tauri/src/lib.rs` invoke_handler macro
- Add TypeScript wrapper in `windows/src/services/tauriCommands.ts`

**New design token:**
- Spacing/radius/typography/animation: `macos/Extensions/Theme.swift` under the `TS` enum
- Color: `macos/Extensions/Color+Brand.swift`

**Localized string:**
- Add key to `macos/Resources/nl.lproj/Localizable.strings` (Dutch)
- Mirror key in `macos/Resources/en.lproj/Localizable.strings` (English)

## Special Directories

**`.planning/`:**
- Purpose: AI planning artifacts (codebase maps, phase plans)
- Generated: Yes (by GSD planning commands)
- Committed: Yes

**`docs/`:**
- Purpose: Human-maintained project documentation
- Generated: No
- Committed: Yes

**`builds/`:**
- Purpose: CI build sandbox artifacts
- Generated: Yes
- Committed: No (gitignored in practice)

**`windows/src-tauri/target/`:**
- Purpose: Rust/Cargo build output
- Generated: Yes
- Committed: No

**`scripts/`:**
- Purpose: Release pipeline scripts (`release.sh`, `deploy-dev.sh`, `deploy-production.sh`, `sync-version.sh`)
- Generated: No
- Committed: Yes

---

*Structure analysis: 2026-06-03*
