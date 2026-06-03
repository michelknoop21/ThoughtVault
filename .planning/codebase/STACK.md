# Technology Stack

**Analysis Date:** 2026-06-03

## Languages

**Primary:**
- Swift 6.0 - macOS/iOS native app (`macos/`, `ios-widget/`)
- TypeScript 5.7 - Windows frontend (`windows/src/`)
- Kotlin 2.3.0 - Android app (`transcript-studio-android/`)
- Rust (Tauri 2) - Windows native shell (`windows/src-tauri/`)

**Secondary:**
- Python (FastAPI) - Backend server (separate repo `../transcript-studio-backend/`)

## Runtime

**macOS/iOS:**
- macOS 14.0+ deployment target
- iOS 17.0+ deployment target
- Swift 6.0 strict concurrency

**Windows:**
- Node.js (no pinned version — no `.nvmrc`)
- Rust (Tauri 2 build toolchain)
- Bundler: Vite 6.0

**Android:**
- compileSdk 36, minSdk 28 (Android 9+), targetSdk 36
- Java 21 / Kotlin JVM toolchain 21

## Package Manager

**Windows:**
- npm (lockfile: `windows/package-lock.json` inferred from `package.json`)

**Android:**
- Gradle (version catalog at `transcript-studio-android/gradle/libs.versions.toml`)

## Frameworks

**macOS/iOS Core:**
- SwiftUI - UI framework
- SwiftData - Local persistence for transcripts/notulen (`macos/Models/TranscriptRecord.swift`, `macos/Services/LocalTranscriptStore.swift`)
- `@Observable` (Observation framework) - State management; `ObservableObject` is forbidden
- `async/await` + Swift Concurrency (actors, `@MainActor`) throughout; no Combine

**Windows Core:**
- Tauri 2.2 - Native shell / IPC bridge (`windows/src-tauri/`)
- React 19.0 - UI framework (`windows/src/`)
- React Router DOM 7.1 - Client-side routing
- Zustand 5.0 - Global state management (`windows/src/stores/`)
- Tailwind CSS 3.4 - Styling
- Vite 6.0 - Build tool / dev server

**Android Core:**
- Jetpack Compose (BOM 2026.02.01) - UI framework
- Hilt 2.59 - Dependency injection
- Room 2.8 - Local database / offline storage
- Retrofit 3.0 + OKHttp 5.3 - HTTP networking
- Navigation Compose 2.9 - Navigation
- Lifecycle 2.8 - ViewModel/lifecycle management
- DataStore Preferences 1.1 - Settings storage
- Google Tink 1.15 - Cryptography

**Testing:**
- Xcode XCTest - macOS unit tests (`TranscriptStudioTests/`)
- Vitest 4.1 - Windows frontend tests (`windows/package.json`)

**Build/Dev:**
- Xcode (macOS/iOS) — `xcodebuild` commands in `CLAUDE.md`
- Tauri CLI 2.2 + `npm run tauri` (Windows)
- Android Gradle Plugin 9.1, KSP 2.3.0

## Key Dependencies

**macOS:**
- `WhisperKit` (argmaxinc/WhisperKit, SPM) — CoreML Whisper on-device transcription; default model `openai_whisper-large-v3-v20240930_626MB`; conditionally compiled with `#if canImport(WhisperKit)`
- `Apple Speech` (`Speech` framework) — fallback on-device transcription via `SFSpeechRecognizer`
- `FoundationModels` (Apple Intelligence SDK) — local LLM for notulen generation; requires macOS 26+ / iOS 26+; guarded with `#if canImport(FoundationModels)` and `#available(macOS 26, *)`
- `AVFoundation` / `AVAudioEngine` — audio recording and mixing
- `AuthenticationServices` — OAuth PKCE flows (Microsoft, Google)
- `EventKit` — Apple Calendar access (`macos/Services/CalendarService.swift`)
- `OSLog` — structured logging throughout
- `Security` (Keychain) — token storage (`macos/Services/KeychainService.swift`)

**Windows (Rust, `windows/src-tauri/Cargo.toml`):**
- `tauri 2` — core shell
- `tauri-plugin-store 2` — persistent settings
- `tauri-plugin-deep-link 2` — `transcript-studio://` URI scheme
- `tauri-plugin-single-instance 2` — single-instance enforcement
- `cpal 0.15` + `hound 3.5` — audio recording (WASAPI on Windows)
- `reqwest 0.12` — HTTP client with multipart streaming
- `keyring 3` — OS credential storage
- `window-vibrancy 0.5` — Windows 11 Mica/Acrylic effects

**Windows (npm, `windows/package.json`):**
- `@fluentui/react-icons 2.0` — Fluent UI icon set
- `@tauri-apps/plugin-fs 2.4` — filesystem access from frontend
- `marked 15.0` — Markdown rendering
- `dompurify 3.3` — HTML sanitisation

**Android (`transcript-studio-android/gradle/libs.versions.toml`):**
- Retrofit 3.0 + `converter-kotlinx-serialization` — typed API client
- OKHttp 5.3 + `okhttp-sse` — HTTP + SSE streaming
- Room 2.8 — SQLite ORM
- Hilt 2.59 — DI
- Tink 1.15 — encryption

## Configuration

**macOS:**
- Server URL stored in `UserDefaults` key `"serverURL"`, default `https://n8n.prezent.nl/tstudio/api`
- Auth token in Keychain via `KeychainService` (service `nl.prezent.TranscriptStudio`)
- Design tokens: `macos/Extensions/Theme.swift` (`TS.Spacing`, `TS.Font`, `TS.Radius`)
- Brand colours: `macos/Extensions/Color+Brand.swift`
- UI strings via `macos/Resources/Localizable.strings` (Dutch)

**Windows:**
- CSP in `windows/src-tauri/tauri.conf.json` allows `https://n8n.prezent.nl`, `https://graph.microsoft.com`, `https://login.microsoftonline.com`
- Deep-link scheme: `transcript-studio://`
- Bundle identifier: `nl.prezent.transcript-studio`
- `useLocalToolsDir: true` — required for Windows CI runner (SYSTEM account)

**Build:**
- Version source of truth: `VERSION` file (root), currently `1.0.130`
- Version sync script: `scripts/sync-version.sh` propagates to `Cargo.toml`, `tauri.conf.json`, Android `build.gradle.kts`
- Xcode project: `TranscriptStudio.xcodeproj/`

## Platform Requirements

**Development:**
- macOS with Xcode (Swift 6, macOS 14+ SDK)
- Node.js + Rust toolchain for Windows
- Android Studio + JDK 21 for Android

**Production / CI:**
- GitLab CI (`.gitlab-ci.yml`): macOS shell runner (`macos, xcode` tags) + Windows self-hosted (`windows` tag)
- GitHub Actions (`.github/workflows/build-windows.yml`): fallback Windows MSI build
- Release scripts: `scripts/deploy-dev.sh` (dev-v* tag), `scripts/deploy-production.sh` (v* tag)
- Downloads served from `https://n8n.prezent.nl/tstudio/download/`

---

*Stack analysis: 2026-06-03*
