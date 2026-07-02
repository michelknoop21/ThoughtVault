# ThoughtVault Windows — Product Requirements

_Last updated: 2026-03-04_

## Overview

ThoughtVault Windows is a Tauri 2 desktop application for recording meetings, transcribing audio, and generating structured meeting notes. It provides feature parity with the macOS SwiftUI version using web technology (React 19 / TypeScript) wrapped in a native Windows desktop shell.

## Target Users

- Business professionals who attend back-to-back meetings
- Teams automating meeting notes as part of Prezent/Yinga service subscriptions
- Privacy-conscious users needing local LLM processing for sensitive content
- Administrators managing multi-user deployments

## Core Features

### Audio Recording
- WASAPI audio capture via cpal crate (Rust backend)
- Microphone and system audio recording modes
- Real-time waveform visualization at 60 Hz
- Output: 16 kHz mono 16-bit PCM WAV
- Pause / resume support
- Audio files stored in `AppData/Recordings` with 7-day retention

### Cloud Transcription
- Upload to ThoughtVault API at `n8n.prezent.nl`
- GPU-accelerated Whisper transcription on server
- SSE streaming for real-time progress updates
- Status pipeline: pending -> uploading -> converting -> transcribing -> transcribed -> processingWebhook -> completed

### Local LLM Generation
- Ollama integration (configurable endpoint URL and model)
- LM Studio integration (OpenAI-compatible API)
- Streaming response via SSE
- Configurable per-profile prompts and templates

### Notes Management
- View, search, and filter transcripts
- Export formats: DOCX, PDF, Markdown, HTML, plain text
- Re-transcription within 7-day audio retention window

### Calendar Integration
- Microsoft 365 OAuth PKCE integration via Microsoft Graph API
- Video call detection with overlay alerts
- Native Windows notifications for upcoming meetings
- Auto-suggest profile based on meeting title

### Profiles
- Custom note-taking templates with configurable prompts
- Language and tone settings per profile
- Default profile always available

### Offline Queue
- Automatic upload queue when network unavailable
- Persistent queue via Tauri plugin-store
- Retry on network reconnect
- Audio files protected from cleanup while queued

### Multi-User Admin
- Invite code management
- User enable/disable
- Role-based access

## Out of Scope

- Real-time live transcription during recording
- Video recording
- Direct Teams/Zoom/Meet plugin integration
- Mobile versions (iOS/Android)
- End-to-end encryption

## Success Criteria

| Metric | Target |
|--------|--------|
| App startup | Under 3 seconds |
| Recording to notes | 3 clicks or fewer |
| Feature parity | Match macOS SwiftUI version |
| Offline reliability | 100% queued recordings processed on reconnect |

## Open Questions

- Timing for activating `whisper-rs` local transcription dependency
- Windows Hello biometric authentication implementation approach
- `cpal` stream `Send`-safety for system audio capture
