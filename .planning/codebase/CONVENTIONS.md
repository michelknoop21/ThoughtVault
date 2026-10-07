# Coding Conventions

**Analysis Date:** 2026-06-03

---

## Platform Overview

This is a multi-platform project. Conventions differ by platform:
- **macOS/iOS** — Swift 6, SwiftUI, `@Observable`
- **Windows** — TypeScript, React, Zustand (Tauri 2)
- **Backend** — FastAPI (Python, in separate repo)

---

## macOS / iOS (Swift)

### Naming Patterns

**Files:**
- `PascalCase.swift` for all Swift files
- ViewModels: `<Feature>ViewModel.swift` (e.g., `RecordingViewModel.swift`)
- Services: `<Feature>Service.swift` (e.g., `APIService.swift`, `KeychainService.swift`)
- Views: `<Feature>View.swift` (e.g., `RecordingView.swift`, `HomeView.swift`)
- Components: `<Name>.swift` in `macos/Views/Components/` (e.g., `TranscriptCard.swift`, `StatusBadge.swift`)
- Models: `Models.swift` (single file for core domain models), or `<Name>.swift` for standalone models

**Types / Classes:**
- `PascalCase` for all types: `final class AuthViewModel`, `struct TSUserInfo`, `actor APIService`
- Enums use `PascalCase` with `camelCase` cases: `TaskStatus.processingWebhook`, `APIError.sessionExpired`
- Protocols: `PascalCase`, usually suffixed with capability: `LLMService`, `Sendable`

**Functions / Properties:**
- `camelCase` for all functions and variables
- Boolean properties use `is`/`has`/`requires` prefix: `isAuthenticated`, `hasNotes`, `requiresTwoFactor`
- Computed properties without side effects (no `get` keyword for single-expression)

**Constants:**
- Module-level private loggers use lowercase: `private let logger = Logger(...)`
- Design tokens use qualified enum path: `TS.Spacing.md`, `TS.Font.bodySemibold`, `TS.Radius.sm`
- Colors use `Color.brandPrimary`, `Color.labelPrimary`, `Color.statusError` (never raw `Color(red:green:blue:)` inline in views)

### Concurrency Model

**ViewModels:** always `@MainActor @Observable final class`
```swift
@MainActor
@Observable
final class RecordingViewModel {
    var isRecording: Bool = false
    ...
}
```

**Services:** always `actor` (never `class`)
```swift
actor APIService {
    static let shared = APIService()
    ...
}
```

**Exception:** `AudioRecorder` uses `@Observable final class ... @unchecked Sendable` because it wraps AVFoundation callbacks.

**Rule:** NEVER use `ObservableObject` / `@Published`. Always use `@Observable`. NEVER use Combine or completion handlers — use `async/await`.

**Task usage:**
- Fire-and-forget background work: `Task { ... }` inside `@MainActor` context
- Cancellable tasks stored as `@ObservationIgnored private var someTask: Task<Void, Never>?`

### Observation & State

**`@ObservationIgnored`** is required on properties that must not trigger SwiftUI observation:
- `@AppStorage` properties
- Stored `Task` handles
- Service references that are actors

**`@Environment` injection** in views:
```swift
@Environment(RecordingViewModel.self) var recordingVM
```
Never `@EnvironmentObject`. Never `@StateObject`.

**`@State`** for local view state only: `@State private var isHovered = false`

### Code Organization — MARK comments

Every Swift file uses `// MARK: -` sections. Standard order within a class/struct:
1. `// MARK: - Published State` (or `// MARK: - State` for views)
2. `// MARK: - Dependencies` (view injected VMs)
3. `// MARK: - AppStorage`
4. `// MARK: - Private`
5. `// MARK: - Init`
6. `// MARK: - <Feature Name>` (one per logical group of methods)

Top-level `// MARK: - TypeName` precedes each type declaration in a file.

### File Header

All Swift files start with a 3-line comment header:
```swift
// FileName.swift
// ThoughtVault
// nl.prezent.ThoughtVault
```

Longer files include a 4th line: `//` followed by a one-line description.

### Error Handling

**Swift errors are typed enums conforming to `LocalizedError`:**
```swift
enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int, String?, String?)
    case sessionExpired
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Je sessie is verlopen. Log opnieuw in om door te gaan."
        ...
        }
    }
}
```

- All `errorDescription` strings are Dutch (user-facing).
- `errorCode: String?` used for machine-readable backend error codes.
- Services `throw` typed errors; ViewModels `catch` and set `errorMessage: String?` on `@Observable` state.
- Never swallow errors silently. Failed background tasks log via `logger.warning(...)` and may set `errorMessage`.

### Logging

**Framework:** `OSLog` (`import OSLog`)

**Pattern:** module-level private logger per file:
```swift
private let logger = Logger(subsystem: "nl.prezent.ThoughtVault", category: "AuthViewModel")
```
- `logger.info(...)` — normal operations
- `logger.warning(...)` — non-fatal failures
- `logger.error(...)` — serious failures

### Localization

**All user-visible strings** are Dutch, loaded from `macos/Resources/nl.lproj/Localizable.strings`.

**Key format:** `<screen>.<element>` or `<domain>.<action>`:
```
"tab.recording"       = "Opnemen";
"state.uploading"     = "Uploaden…";
"transcripts.title"   = "Notulen";
```

**Usage in views:** `Text("tab.recording")` — SwiftUI auto-looks up the key. For formatted strings: `String(format: NSLocalizedString("upload.progress", comment: ""), percent)`.

**Code and comments** are in English. Error descriptions in Swift are Dutch (user-facing). Internal comments are English.

### Design Tokens

Always use `TS.*` tokens — never magic numbers for spacing, radii, or fonts:

| Token | Values | Use |
|-------|--------|-----|
| `TS.Spacing.xs/sm/md/lg/xl/xxl` | 4/8/16/24/32/48 pt | Padding, gaps |
| `TS.Radius.xs/sm/md/lg/xl` | 6/12/16/20/25 pt | Corner radii |
| `TS.Font.*` | System text styles | Typography |
| `TS.Animation.smooth/quick/gentle/hover` | Spring/ease presets | Animations |

**Colors:** Always use semantic tokens from `Color+Brand.swift`:
- Brand: `Color.brandPrimary` (magenta), `Color.brandSecondary` (blue), `Color.brandAccent` (green)
- Labels: `Color.labelPrimary`, `Color.labelSecondary`, `Color.labelTertiary`
- Surfaces: `Color.surfacePrimary`, `Color.surfaceSecondary`
- Status: `Color.statusError`, `Color.statusWarning`, `Color.statusSuccess`

### View Modifiers & Components

**Card style:** `.modernCard(isHovered:)` modifier (from `Theme.swift`).

**Button styles:** `PrimaryButtonStyle(isDestructive:)` and `SecondaryButtonStyle` (from `Theme.swift`).

**Reusable components** live in `macos/Views/Components/`:
`TranscriptCard.swift`, `StatusBadge.swift`, `WaveformView.swift`, `ProcessingBar.swift`, `ProfilePicker.swift`, `PermissionBanner.swift`

---

## Windows (TypeScript / React)

### Naming Patterns

**Files:**
- `PascalCase.tsx` for React components and pages
- `camelCase.ts` for services, stores, hooks, utilities
- Pages: `<Feature>Page.tsx` in `windows/src/pages/`
- Components: `<Name>.tsx` in `windows/src/components/<category>/`
- Stores: `<feature>Store.ts` in `windows/src/stores/`
- Services: `<name>.ts` in `windows/src/services/`
- Hooks: `use<Name>.ts` in `windows/src/hooks/`

**Types:**
- `PascalCase` for interfaces and type aliases: `interface AuthState`, `type TaskStatus`
- Zustand stores: `interface <Feature>State` with actions included in the same interface

**Functions:**
- `camelCase` for all functions
- React components: named exports with `PascalCase` function name: `export function RecordingPage()`
- Hooks: `export function use<Name>()` in dedicated files

**Constants:**
- `SCREAMING_SNAKE_CASE` for module-level constants: `const CREDENTIAL_KEY = "auth_token"`

### TypeScript Strictness

`tsconfig.json` enforces:
- `"strict": true`
- `"noUnusedLocals": true`
- `"noUnusedParameters": true`
- `"noFallthroughCasesInSwitch": true`

### State Management

**Zustand** for all global state. Pattern:
```typescript
export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      ...
      logout: () => set({ token: null, user: null, isAuthenticated: false }),
    }),
    { name: "auth-store" }
  )
);
```

- One store per domain: `authStore`, `recordingStore`, `tasksStore`, `transcriptsStore`, `settingsStore`, `profilesStore`, `uploadQueueStore`
- Actions defined inside the store interface (not separate)
- Timer handles (e.g., `setInterval`) stored as module-level variables outside Zustand (not serializable)
- Internal store state read via `useXxxStore.getState()` in services (not hooks)

### API / Service Layer

All HTTP calls go through `windows/src/services/api.ts` via the `api` singleton.

**Error extraction helper** used throughout:
```typescript
function extractErrorMessage(err: unknown): string {
  if (typeof err === "string") return err;
  if (err instanceof Error) return err.message;
  // Tauri wraps Rust errors as { message: string }
  if (err && typeof err === "object") { ... }
  return "Onbekende fout";
}
```

- Tauri `invoke` calls go through `windows/src/services/tauriCommands.ts`
- Upload goes through `api.uploadRecording()` / `api.uploadRecordingWithProgress()` which wraps `invoke("proxy_upload", ...)`
- Auth header: `Authorization: Bearer <token>`

### Error Handling (Windows)

- Catch in Zustand actions, set `error: string | null` on store state
- Error messages are Dutch: `"Onbekende fout"`, `"Annuleren mislukt"`, `"Upload mislukt: ..."`
- Typed errors not used; string comparison on error messages for retry/non-retry logic
- `isNetworkError(err)` helper in `authStore.ts` for transient-vs-fatal classification

### Import Organization

1. React core (`import { useState, useEffect } from "react"`)
2. Third-party libraries (`react-router-dom`, `@fluentui/react-icons`, `zustand`)
3. Internal stores (`../stores/...`)
4. Internal services (`../services/...`)
5. Internal components (`../components/...`)
6. Types (`../types`)

No path aliases configured — all imports use relative paths.

### UI / Styling

**Tailwind CSS** for all styling in `.tsx` files. No inline `style={{}}` except for icon size overrides (e.g., `style={{ fontSize: 14 }}`).

**Icons:** Fluent UI React Icons (`@fluentui/react-icons`) exclusively. Naming: `<Icon>24Regular` or `<Icon>16Regular`.

**User-facing strings** in Windows are Dutch, inline in JSX (no separate i18n file).

### Module Exports

- Named exports only: `export function MyComponent()`, `export const useMyStore = create(...)`
- No default exports
- Types file: `windows/src/types.ts` (single barrel for all shared types)

---

## Comments

**When to comment:**
- `///` doc comments on public Swift functions/protocols with non-obvious behavior
- `//` inline for complex logic, non-obvious decisions, or workarounds
- No commented-out code in commits

**Language:** English for all code comments. Dutch only in user-visible strings and `LocalizedError.errorDescription`.

---

*Convention analysis: 2026-06-03*
