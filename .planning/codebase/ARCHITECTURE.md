<!-- refreshed: 2026-06-03 -->
# Architecture

**Analysis Date:** 2026-06-03

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                         Client Platforms                                 │
├────────────────────┬───────────────────────┬────────────────────────────┤
│  macOS / iOS       │       Windows          │         Android            │
│  Swift 6 + SwiftUI │  Tauri 2 + React/TS   │  Kotlin + Jetpack Compose  │
│  `macos/`          │  `windows/`            │  `transcript-studio-       │
│                    │                        │   android/`                │
└────────┬───────────┴──────────┬────────────┴──────────┬─────────────────┘
         │                      │                        │
         │   (HTTP + SSE)        │   (HTTP + SSE)         │  (HTTP + SSE)
         ▼                      ▼                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    FastAPI Backend (Cloud)                                │
│           `https://n8n.prezent.nl/tstudio/api/`                          │
│   Audio upload → Whisper transcription → n8n webhook → notulen (Claude) │
└─────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Local-First Offline Path (macOS/iOS)                  │
│  WhisperKit / Apple Speech → Ollama / LM Studio / Apple Intelligence     │
│  SwiftData (`TranscriptRecord`)                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| ThoughtVaultApp | App entry point, environment injection, scene setup | `macos/App/ThoughtVaultApp.swift` |
| RootView / ContentView | Onboarding gate, sidebar navigation (macOS), TabView (iOS) | `macos/App/ContentView.swift` |
| RecordingViewModel | Recording state machine, upload routing, local processing orchestration | `macos/ViewModels/RecordingViewModel.swift` |
| AuthViewModel | Auth state, token lifecycle, 2FA | `macos/ViewModels/AuthViewModel.swift` |
| TranscriptsViewModel | Transcript list, pagination, search/filter, local+cloud merge | `macos/ViewModels/TranscriptsViewModel.swift` |
| TasksViewModel | Active task polling, SSE task updates | `macos/ViewModels/TasksViewModel.swift` |
| APIService | All HTTP calls to FastAPI backend, SSE client | `macos/Services/APIService.swift` |
| AudioRecorder | Microphone capture via AVFoundation | `macos/Services/AudioRecorder.swift` |
| SystemAudioCapture | System audio capture via ScreenCaptureKit (macOS only) | `macos/Services/SystemAudioCapture.swift` |
| LocalTranscriber | Protocol + factory for on-device STT (WhisperKit or Apple Speech) | `macos/Services/LocalTranscriber.swift` |
| OnDeviceTranscriber | WhisperKit wrapper, model download management | `macos/Services/OnDeviceTranscriber.swift` |
| LLMService | Protocol for notulen generation; impls: OpenAI-compat (Ollama/LM Studio), Apple Intelligence | `macos/Services/LLMService.swift` |
| LLMServiceFactory | Selects correct LLMService impl from `NotulenProvider` enum | `macos/Services/LLMService.swift` |
| LocalTranscriptStore | SwiftData container/CRUD for local `TranscriptRecord` | `macos/Services/LocalTranscriptStore.swift` |
| OfflineQueue | JSON-persisted queue of failed uploads, survives restarts | `macos/Services/OfflineQueue.swift` |
| KeychainService | Secure token storage | `macos/Services/KeychainService.swift` |
| CalendarService | Apple Calendar + Microsoft Graph calendar events | `macos/Services/CalendarService.swift` |
| NetworkMonitor | NWPathMonitor connectivity status | `macos/Services/NetworkMonitor.swift` |
| Windows App (React) | Same feature set as macOS, Zustand stores mirror Swift ViewModels | `windows/src/` |
| Windows Tauri backend | Rust commands: audio, auth credentials, filesystem, HTTP proxy, system | `windows/src-tauri/src/` |

## Pattern Overview

**Overall:** Hybrid local-first MVVM with protocol-based service abstraction

**Key Characteristics:**
- All ViewModels are `@MainActor @Observable final class` — never `ObservableObject/@Published`
- Services are singletons: `actor APIService`, `@Observable final class` for observable services, plain `final class` for stateless ones
- `ProcessingMode.local` routes entirely on-device; `ProcessingMode.cloud` uses FastAPI + n8n
- `NotulenProvider` enum selects the LLM backend at runtime (cloud/ollama/lmStudio/appleIntelligence)
- Windows mirrors the same domain logic via Zustand stores + Tauri Rust commands

## Layers

**View Layer:**
- Purpose: SwiftUI views, zero business logic
- Location: `macos/Views/`, `macos/Views/Components/`
- Contains: Screen views, reusable UI components
- Depends on: ViewModels (via `@Environment`), design tokens
- Used by: nothing (top of stack)

**ViewModel Layer:**
- Purpose: State machine, UI-facing business logic, async coordination
- Location: `macos/ViewModels/`
- Contains: `RecordingViewModel`, `AuthViewModel`, `TranscriptsViewModel`, `TasksViewModel`
- Depends on: Services (direct calls), Models
- Used by: Views via `@Environment`

**Service Layer:**
- Purpose: External I/O, hardware access, persistence
- Location: `macos/Services/`
- Contains: `APIService` (actor), `AudioRecorder`, `LocalTranscriber`, `LLMService`, `LocalTranscriptStore`, `OfflineQueue`, `KeychainService`, etc.
- Depends on: Models, system frameworks (AVFoundation, SwiftData, Network, ScreenCaptureKit)
- Used by: ViewModels

**Model Layer:**
- Purpose: Value types, enums, shared data structures
- Location: `macos/Models/`
- Contains: `Models.swift` (all domain enums/structs), `TranscriptRecord.swift` (SwiftData), `ProfileTemplates.swift`
- Depends on: nothing
- Used by: all layers

**Windows Equivalent Layers:**
- Views: React components in `windows/src/components/` and `windows/src/pages/`
- State: Zustand stores in `windows/src/stores/`
- Services: TypeScript services in `windows/src/services/`
- Rust backend: commands in `windows/src-tauri/src/commands/`

## Data Flow

### Cloud Path (online, cloud mode)

1. User taps record → `RecordingViewModel.startRecording()` (`macos/ViewModels/RecordingViewModel.swift:260`)
2. `AudioRecorder` and/or `SystemAudioCapture` write PCM to disk (`macos/Services/AudioRecorder.swift`)
3. User stops → `RecordingViewModel.stopAndUpload()` (`macos/ViewModels/RecordingViewModel.swift:369`)
4. `NetworkMonitor.isConnected` checked; cloud path → `uploadFile()` (`macos/ViewModels/RecordingViewModel.swift:494`)
5. `APIService.shared.uploadAudio()` POSTs to backend (`macos/Services/APIService.swift:517`)
6. Backend returns `task_id`; SSE stream opened via `SSEClient` (`macos/Services/APIService.swift:1008`)
7. Backend runs Whisper → n8n webhook → Claude notulen generation; SSE pushes status updates
8. `RecordingViewModel.handleSSEEvent()` updates `activeTasks` → UI reflects progress (`macos/ViewModels/RecordingViewModel.swift:1045`)
9. On `completed`: transcript + notulen available via `APIService.getTranscript()`

### Local Path (offline/local mode)

1. User stops → `stopAndUpload()` detects `isLocalMode == true` → `processLocally(url:profileId:)` (`macos/ViewModels/RecordingViewModel.swift:646`)
2. `LocalTranscriberFactory.make()` returns WhisperKit or Apple Speech transcriber (`macos/Services/LocalTranscriber.swift`)
3. Transcription runs; result immediately persisted to SwiftData via `LocalTranscriptStore.shared.save()` (`macos/Services/LocalTranscriptStore.swift:37`)
4. `LLMServiceFactory.service(for: provider)` creates Ollama/LM Studio/Apple Intelligence service (`macos/Services/LLMService.swift:81`)
5. `service.generateNotulen()` streams HTML chunks; each chunk appended via `appendTaskNotuleHtml()`
6. Final HTML + extracted title saved via `LocalTranscriptStore.shared.finalizeNotule()` (`macos/Services/LocalTranscriptStore.swift`)

### Offline Queue Path

1. `stopAndUpload()` → `NetworkMonitor.isConnected == false` → `handleOfflineRecording(url:)` (`macos/ViewModels/RecordingViewModel.swift:806`)
2. `OfflineQueue.shared.enqueue()` persists item to `offline_queue.json` in Documents (`macos/Services/OfflineQueue.swift`)
3. On next launch or connectivity restoration: `processQueueOnStartupIfNeeded()` drains the queue (`macos/ViewModels/RecordingViewModel.swift:819`)

### On-Device Transcription + Cloud Notulen Path

1. `preferOnDeviceTranscription == true && onDeviceTranscriptionAvailable == true && mode == .microphone`
2. `transcribeOnDeviceThenUpload(url:profileId:)` runs WhisperKit locally, then POSTs text-only to backend for notulen generation (`macos/ViewModels/RecordingViewModel.swift:594`)

**State Management:**
- macOS: `@Observable` singletons injected via SwiftUI `@Environment`; `LocalTranscriptStore` injected as `.modelContainer`
- Windows: Zustand stores (`windows/src/stores/`); `recordingStore.ts` owns recording phase state machine

## Key Abstractions

**RecordingState (enum):**
- Purpose: Drives the entire recording UI state machine
- File: `macos/Models/Models.swift:195`
- Values: `idle`, `preparing`, `recording`, `paused`, `stopping`, `uploading`, `.error(String)`

**ProcessingMode (enum):**
- Purpose: Switches between full local-first vs. cloud processing at app level
- File: `macos/Models/Models.swift:122`
- Values: `local`, `cloud`

**NotulenProvider (enum):**
- Purpose: Runtime selection of LLM backend for notulen generation
- File: `macos/Models/Models.swift:138`
- Values: `cloud`, `ollama`, `lmStudio`, `appleIntelligence`

**LocalTranscriber (protocol):**
- Purpose: Abstraction over on-device STT engines
- File: `macos/Services/LocalTranscriber.swift:49`
- Implementations: `WhisperKitTranscriber`, `AppleSpeechTranscriber`

**LLMService (protocol):**
- Purpose: Abstraction over LLM providers for notulen generation
- File: `macos/Services/LLMService.swift:30`
- Implementations: `OpenAICompatibleLLMService` (Ollama/LM Studio), `AppleFoundationModelService`

**Profile:**
- Purpose: User-selected notulen generation configuration (system prompt, notule prompt, template)
- File: `macos/Models/ProfileTemplates.swift`, `macos/Models/Models.swift`
- Source: Loaded from API, falls back to `Profile.defaults` when offline

## Entry Points

**macOS/iOS App:**
- Location: `macos/App/ThoughtVaultApp.swift:5` (`@main`)
- Triggers: App launch
- Responsibilities: Creates `AuthViewModel`, `RecordingViewModel`, `TasksViewModel`; injects into environment; configures `LocalTranscriptStore.shared.container` as `.modelContainer`

**Windows App:**
- Location: `windows/src/main.tsx`
- Triggers: Tauri webview load
- Responsibilities: Renders `App.tsx` with BrowserRouter, initializes crash reporter, sets up global recording handler

**Tauri Rust Backend:**
- Location: `windows/src-tauri/src/lib.rs:9` (`pub fn run()`)
- Triggers: App launch
- Responsibilities: Registers Tauri plugins (store, deep-link, shell, notification, single-instance), exposes IPC commands, applies Windows Mica effect

## Architectural Constraints

- **Threading (macOS):** All ViewModels are `@MainActor`; `APIService` is a Swift `actor` (its own executor); `AudioRecorder`, `OfflineQueue`, `NetworkMonitor` are `@Observable final class` with `@unchecked Sendable` (internal locking)
- **Global state:** `APIService.shared`, `LocalTranscriptStore.shared`, `OfflineQueue.shared`, `OnDeviceTranscriber.shared`, `KeychainService.shared`, `NetworkMonitor.shared`, `CalendarService.shared` — all are module-level singletons
- **Local mode auth bypass:** `ContentView` gates on `authVM.isAuthenticated || recordingVM.isLocalMode` — local mode users skip login entirely (`macos/App/ContentView.swift:81`)
- **macOS-only features:** `SystemAudioCapture` (ScreenCaptureKit), `FloatingWidgetController`, `VideoCallDetectionService`, menu bar extra — all guarded by `#if os(macOS)`
- **Combined audio mixing:** `mixAudioFiles()` in `RecordingViewModel` does element-wise PCM max merge; falls back to mic-only if system audio fails

## Anti-Patterns

### Using `actor` keyword for services that need UI-bound observability

**What happens:** Some services that expose `@Observable` state (e.g., `AudioRecorder`, `CalendarService`) are `final class` with `@unchecked Sendable` rather than true `actor` types.
**Why it's wrong:** `@unchecked Sendable` suppresses Swift concurrency checking; internal synchronization must be manually managed.
**Do this instead:** For services that are purely I/O with no published state, use `actor`. For services that publish `@Observable` state directly read by SwiftUI, use `@MainActor @Observable final class` as done in `RecordingViewModel`.

### Services not matching the CLAUDE.md-prescribed actor pattern

**What happens:** `APIService` is a Swift `actor` (correct), but `AudioRecorder`, `CalendarService`, `OfflineQueue` are `@Observable final class: @unchecked Sendable`.
**Why it's wrong:** Inconsistent concurrency model across the service layer.
**Do this instead:** Follow the rule in `CLAUDE.md`: Services → `actor`; ViewModels → `@MainActor class`. Observable services that need SwiftUI binding are an exception; document the reason.

## Error Handling

**Strategy:** `async throws` throughout; errors surface to ViewModel state (`.error(String)` case in `RecordingState`); UI shows localized Dutch messages

**Patterns:**
- `APIError` enum with `LocalizedError` conformance covers all HTTP failure cases (`macos/Services/APIService.swift:25`)
- `LocalTranscriberError`, `LLMError`, `AudioRecorderError` follow same pattern
- `LocalTranscriptStore` falls back to in-memory container on init failure rather than crashing (`macos/Services/LocalTranscriptStore.swift:28`)
- Offline queue enqueues failed uploads silently; user sees banner on next app launch

## Cross-Cutting Concerns

**Logging:** `OSLog` / `Logger` throughout macOS (`subsystem: "nl.prezent.ThoughtVault"`); category per file
**Validation:** Input validation in ViewModels before service calls; API response validation in `APIService`
**Authentication:** Token in Keychain (`KeychainService`); header is `X-User-Token` on macOS, `Authorization: Bearer` on Windows; 401 triggers `authDidInvalidate` notification
**Localization:** UI strings in Dutch via `Localizable.strings` (`macos/Resources/nl.lproj/`); code/comments in English

---

*Architecture analysis: 2026-06-03*
