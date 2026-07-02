# ThoughtVault Windows — Architecture

_Last updated: 2026-03-04_

## System Architecture

Three-layer architecture: React UI in WebView2 communicating via Tauri IPC bridge to Rust backend for native Windows APIs.

```
+-----------------------------+
|     React 19 Frontend       |  WebView2 (Chromium)
|  TypeScript · Tailwind CSS  |
|  Zustand · Fluent UI icons  |
+-----------+-----------------+
            | Tauri IPC
+-----------+-----------------+
|     Rust Backend (Tauri 2)  |  Native process
|  cpal · keyring · reqwest   |
+-----------------------------+
```

## Frontend Stack

| Technology | Purpose |
|-----------|---------|
| React 19 | UI framework |
| TypeScript | Type safety |
| Vite | Build tool |
| Tailwind CSS | Styling |
| Zustand | State management |
| Fluent UI icons | Windows-native icon set |

### Directory Structure

```
src/
  components/
    calendar/       CallAlertOverlay
    layout/         AppShell, Sidebar, TitleBar
    onboarding/     OnboardingWizard
    recording/      RecordingWidget, WaveformVisualizer
  hooks/            useAudioLevel, useOAuthCallback, useWidgetWindow
  pages/            Home, Login, Recording, Transcripts, Settings, Admin
  services/         api, llm, microsoftGraph, offlineQueue, sse, tauriCommands
  stores/           auth, calendar, profiles, recording, settings, transcripts
  styles/           globals.css, widget.css
  types.ts          Shared TypeScript interfaces
```

### State Management (Zustand)

| Store | Responsibility |
|-------|---------------|
| authStore | JWT token, user object, login/logout |
| calendarStore | Microsoft 365 events, upcoming meetings |
| profilesStore | Note-taking profiles and templates |
| recordingStore | Recording state, audio levels, segments |
| settingsStore | Server URL, LLM config, onboarding flag |
| transcriptsStore | Transcript list, search, filters |

## Rust Backend (Tauri 2)

### Command Modules

| Module | Commands |
|--------|---------|
| `audio` | WASAPI recording, level metering (macOS stubs for dev) |
| `auth` | Keyring credential storage with legacy migration |
| `filesystem` | AppData paths, file management, 7-day cleanup |
| `http` | HTTP proxy for API calls, file upload with progress |
| `system` | Process detection, system info utilities |

OAuth PKCE flow handled in `lib.rs` with deep-link callback via Tauri event system.

### Audio Pipeline

```
WASAPI capture → 16kHz mono 16-bit PCM
    ↓
60 Hz level metering → frontend waveform
    ↓
WAV file → AppData/Recordings/
    ↓
Upload (XHR) or OfflineQueue
    ↓
SSE progress tracking → status updates
    ↓
Optional: local LLM generation (Ollama/LM Studio)
```

## External Integrations

| Service | Purpose |
|---------|---------|
| ThoughtVault API (`n8n.prezent.nl`) | Upload, transcription, note generation |
| Microsoft Graph | Calendar access, OAuth PKCE for M365 |
| Ollama / LM Studio | Local LLM generation (configurable) |

## Data Persistence

| Layer | Storage |
|-------|---------|
| Auth & settings | localStorage |
| Offline upload queue | Tauri plugin-store |
| Credentials | OS keychain (keyring crate) |
| Audio recordings | `AppData/Recordings/` (7-day cleanup) |

## Configuration

Zero environment variables. All configuration handled via Settings UI:
- Server URL
- LLM provider and endpoint
- Microsoft 365 OAuth credentials
- Audio input device
