# TranscriptStudio — Product Requirements Document

_Last updated: 2026-03-05_

---

## 1. Product Overview

TranscriptStudio is a cross-platform desktop application for recording meetings, transcribing audio, and generating structured meeting notes. It targets business professionals who need automated meeting documentation with the option to keep sensitive content entirely on-device.

The product consists of three client surfaces sharing a common backend:

| Platform | Technology | Status |
|----------|-----------|--------|
| macOS 14+ | Swift 6 / SwiftUI / @Observable | Production |
| Windows 11 (ARM64 + x64) | Tauri 2 / React 19 / TypeScript | Active development |
| iOS 17+ (Widget only) | SwiftUI Live Activity | Production |

**Backend:** FastAPI (Python) + insanely-fast-whisper + n8n workflow orchestration, deployed at `https://n8n.prezent.nl`.

---

## 2. Target Users

### Primary
- **Business professionals** who attend back-to-back meetings and need automated meeting documentation without manual note-taking.
- **Prezent / Yinga subscribers** who access the product as part of an existing service subscription.

### Secondary
- **Privacy-conscious users** who require local LLM processing for sensitive meeting content (legal, HR, board meetings).
- **Administrators** managing multi-user team deployments via invite codes and user management.

### User needs
- Recording starts in one tap/click — no configuration required before recording.
- Notes are delivered in under 3 user interactions from the start of recording.
- Offline reliability: audio must never be lost if network is unavailable during or after recording.
- Configurable note templates per profile (e.g. "Sales call" vs "Team standup").

---

## 3. Core Features

### 3.1 Audio Recording

| Capability | Detail |
|-----------|--------|
| Microphone recording | AVFoundation (macOS/iOS) / WASAPI (Windows) |
| System audio capture | ScreenCaptureKit (macOS) / WASAPI loopback (Windows) |
| Combined mode | Microphone + system audio mixed; element-wise `max()` for level metering |
| Real-time waveform | Live level metering at 60 Hz drawn as animated waveform |
| Pause / Resume | Session can be paused without discarding audio |
| Offline-first | Audio written to local disk immediately; upload queued when reconnected |

**Audio format:** 16 kHz · mono · 16-bit PCM WAV — optimal for Whisper transcription at manageable file size.

**Retention:** Audio files are kept for 7 days to support re-transcription. Files referenced by the OfflineQueue are never deleted early.

### 3.2 Cloud Transcription

- Audio uploaded to `POST /tstudio/api/upload` immediately after recording stops (or when network becomes available).
- Backend queues a GPU-accelerated Whisper job (insanely-fast-whisper).
- Client receives real-time status via Server-Sent Events at `GET /tstudio/api/task/{id}/stream`.
- Status pipeline: `pending → uploading → converting → transcribing → transcribed → processingWebhook → completed`.
- Re-transcription supported within 7-day audio retention window.

### 3.3 Local / On-Device Transcription

- Fallback mode when network is unavailable or when user prefers full privacy.
- macOS: `OnDeviceTranscriber` service using Apple Speech framework (SFSpeechRecognizer) or `whisper-rs` local model.
- Windows: `whisper-rs` GGML local model (optional dependency, not enabled by default).
- User toggles on-device transcription in Settings; app routes accordingly in `RecordingViewModel`.

### 3.4 Meeting Notes Generation

| Provider | Mechanism |
|---------|-----------|
| Cloud (default) | n8n workflow + Claude AI pipeline via backend |
| Ollama | Local HTTP endpoint (configurable URL) |
| LM Studio | OpenAI-compatible local endpoint |
| Apple Intelligence | Apple Foundation Models (macOS 26+ / iOS 26+) |

- Notes delivered as HTML stored in `Task.result` (`notuleHtml` on macOS, `notule_html` on Windows).
- **Profiles** define custom system prompts per note type (e.g. "Besluitenlijst", "Actiepunten").
- Exports: DOCX, PDF, Markdown, HTML, plain text.

### 3.5 Profiles

- Users can create multiple profiles with different note templates and LLM prompts.
- A default profile is always present; custom profiles can be added, edited, and deleted.
- Settings per profile: prompt text, language, tone (formal / informal).
- Calendar integration auto-suggests a profile based on meeting title keywords.

### 3.6 Offline Queue

- `OfflineQueue` service persists failed or queued uploads to disk.
- `NetworkMonitor` (NWPathMonitor) watches reachability and triggers automatic retry on reconnect.
- Queue items reference the local audio file path; files are protected from cleanup while queued.
- Status visible in UI: pending upload count shown in recording controls.

### 3.7 Authentication and Security

- Token-based authentication with `X-User-Token` request header.
- Tokens remain valid until server-side `SESSION_INACTIVITY_DAYS` expiry.
- Biometric login (Face ID / Touch ID) on macOS via `BiometricService` + `KeychainService`.
- Auth token stored in Keychain with `kSecAttrAccessibleWhenUnlocked` and Secure Enclave access control.
- Admin user management: invite codes, enable/disable users, role assignment.
- GDPR: data export (JSON) and account deletion flows in `AccountView`. `PrivacyInfo.xcprivacy` manifest included.

### 3.8 Calendar Integration

| Platform | Integration |
|---------|-----------|
| macOS | EventKit (local + Exchange calendars) |
| Windows | Microsoft Graph API (Microsoft 365) |

- Detects upcoming meetings and shows an overlay alert when a call starts.
- Meeting title used to auto-suggest profile for note generation.
- Change detection: `EKEventStoreChangedNotification` (macOS) + timer polling as fallback.

### 3.9 UI Surfaces (macOS)

1. **Main window** — default 1100×750 px, minimum 900×600 px. Tab-based navigation: Home, Recording, Transcripts, Settings.
2. **MenuBarExtra** — recording controls + live duration counter + task progress bar accessible from menu bar at all times.
3. **FloatingWidgetPanel** — overlay widget visible during active recording showing timer and waveform.
4. **Live Activity (iOS)** — lock screen and Dynamic Island widget via `RecordingActivityWidget` target.

---

## 4. Technical Requirements

| Requirement | Value |
|------------|-------|
| macOS minimum | macOS 14 Sonoma |
| iOS minimum | iOS 17 |
| Windows minimum | Windows 11 (ARM64 or x64) |
| Swift version | Swift 6 (strict concurrency) |
| Xcode minimum | Xcode 16 |
| Bundle ID (macOS/iOS) | `nl.prezent.TranscriptStudio` |
| Architecture pattern | MVVM with `@Observable` (no Combine) |
| Concurrency | `@MainActor` for ViewModels; `actor` for APIService |
| Audio format | 16 kHz, mono, 16-bit PCM WAV |
| Localization | Dutch (nl_NL) primary; English strings as fallback |

### Required entitlements (macOS)
- `com.apple.security.device.audio-input`
- `com.apple.security.personal-information.calendars`
- ScreenCaptureKit (system audio capture)
- `com.apple.security.app-sandbox`

---

## 5. Out of Scope

The following capabilities are explicitly excluded from the current product scope:

- **Real-time live transcription** during recording (transcription happens post-recording only)
- **Video recording** of any kind
- **Direct plugin integration** with Teams, Zoom, or Google Meet (calendar detection only, no SDK)
- **Mobile app** (iOS app is widget-only; no full iOS recording interface)
- **Android support**
- **End-to-end encryption** of audio or transcripts in transit
- **Collaborative editing** of generated notes

---

## 6. Success Criteria

| Metric | Target |
|--------|--------|
| App launch time | Under 3 seconds |
| Recording → notes | Delivered in under 3 user interactions |
| Offline queue reliability | 100% of queued recordings processed on reconnect |
| Platform parity | All core features available on macOS and Windows |
| Transcription accuracy | Whisper large-v3 baseline on Dutch speech |

---

## 7. Open Questions

- Windows Hello biometric authentication: implementation approach to be decided.
- `cpal` stream `Send`-safety for system audio capture on Windows: investigation ongoing.
- Timeline for activating `whisper-rs` local transcription as non-optional dependency on Windows.
- Apple Intelligence (Foundation Models) API stability for local LLM generation on macOS 26+.
