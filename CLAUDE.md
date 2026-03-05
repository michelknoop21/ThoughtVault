# TranscriptStudioApp - Claude Code Instructies

## Project overzicht
Native macOS/iOS app (Swift 6, SwiftUI) voor vergaderopnames, transcriptie en notulengeneratie.
- **macOS app**: `/TranscriptStudio/` — Swift 6, SwiftUI, @Observable
- **Windows app**: `/transcript-studio-windows/` — Tauri 2, React/TypeScript
- **Widget**: `/RecordingActivityWidget/` — iOS Live Activity

## Architectuur
- **MVVM**: ViewModels (AuthViewModel, RecordingViewModel, TranscriptsViewModel)
- **Services**: APIService, AudioRecorder, SystemAudioCapture, BiometricService, KeychainService, etc.
- **Backend API**: https://n8n.prezent.nl — endpoints onder `/tstudio/api/`

## Bouwen
```bash
# macOS app bouwen
xcodebuild -project TranscriptStudio.xcodeproj -scheme TranscriptStudio -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Build met signing (vereist provisioning profile)
xcodebuild -project TranscriptStudio.xcodeproj -scheme TranscriptStudio build
```

## Belangrijke patronen
- Gebruik `@Observable` (NIET `ObservableObject/@Published`) — migratie voltooid
- Alle strings in Dutch (nl_NL) via `Localizable.strings`
- Design tokens via `TS.Spacing`, `TS.Font`, `TS.Radius` (Theme.swift)
- Kleuren via `Color.brandPrimary`, `Color.labelPrimary` etc. (Color+Brand.swift)
- Bundle ID: `nl.prezent.TranscriptStudio`

## Bekende issues
- `AuthViewModel.swift`: gebruik `notifications(named:)` niet `notifications(for:)` voor async NotificationCenter
- Combined recording mode: gebruikt `mixAudioFiles()` in RecordingViewModel
- Sidebar toggle: `.toolbar(removing: .sidebarToggle)` op elk individueel NavigationStack tabblad

## Tests
```bash
xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests
```
