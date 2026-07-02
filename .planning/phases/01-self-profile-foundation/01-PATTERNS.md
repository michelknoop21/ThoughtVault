# Phase 1: Self-Profile Foundation - Pattern Map

**Mapped:** 2026-06-04
**Files analyzed:** 10 new/modified files
**Analogs found:** 10 / 10

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `macos/Models/PersonProfile.swift` | model | CRUD | `macos/Models/TranscriptRecord.swift` | exact |
| `macos/Models/AppMigrationPlan.swift` | config | CRUD | `macos/Services/LocalTranscriptStore.swift` (init block) | role-match |
| `macos/Services/LocalTranscriptStore.swift` | service | CRUD | itself (modify) | exact |
| `macos/Views/ProfileSettingsView.swift` | component | request-response | `macos/Views/SettingsView.swift` (profielenSection) | exact |
| `macos/Views/OnboardingView.swift` | component | request-response | itself (modify) | exact |
| `macos/Models/Models.swift` | model | — | itself (comment-only edit) | exact |
| `windows/src/stores/personProfileStore.ts` | store | CRUD | `windows/src/stores/profilesStore.ts` | exact |
| `windows/src/types.ts` | config | — | itself (modify) | exact |
| `windows/src/components/onboarding/OnboardingWizard.tsx` | component | request-response | itself (modify) | exact |
| `windows/src/components/settings/ProfileSettings.tsx` | component | request-response | `windows/src/components/onboarding/OnboardingWizard.tsx` (StepContent pattern) | role-match |
| `ThoughtVaultTests/PersonProfileTests.swift` | test | CRUD | `ThoughtVaultTests/TranscriptsViewModelTests.swift` | role-match |
| `ThoughtVaultTests/MigrationTests.swift` | test | CRUD | `ThoughtVaultTests/ThoughtVaultTests.swift` | role-match |

---

## Pattern Assignments

### `macos/Models/PersonProfile.swift` (model, CRUD)

**Analog:** `macos/Models/TranscriptRecord.swift`

**Imports pattern** (lines 1-9):
```swift
// TranscriptRecord.swift
// ThoughtVault
// nl.prezent.ThoughtVault
//
// [one-line description of the model's purpose]

import Foundation
import SwiftData
```

**Core @Model pattern** (lines 13-57):
```swift
@Model
final class TranscriptRecord {
    @Attribute(.unique) var id: String       // unique string ID — copy this for PersonProfile
    var tags: [String]                       // [String] arrays work natively — no transformer
    var createdAt: Date

    init(
        id: String = UUID().uuidString,      // default UUID string
        tags: [String] = [],                 // default empty array
        createdAt: Date = Date()             // default now
    ) {
        self.id = id
        // ... assign every property explicitly
    }
}
```

**Key facts extracted from analog:**
- `@Attribute(.unique)` on `id: String` — line 17
- `var tags: [String]` stored natively without any attribute annotation — line 25
- `init` assigns every property explicitly (no shorthand) — lines 31-57
- File header comment format: `// FileName.swift\n// ThoughtVault\n// nl.prezent.ThoughtVault\n//\n// [purpose]`

---

### `macos/Models/AppMigrationPlan.swift` (config, CRUD) — new file

**Analog:** `macos/Services/LocalTranscriptStore.swift` (init block, lines 23-48)

No direct analog exists for a `VersionedSchema` / `SchemaMigrationPlan` file. Use RESEARCH.md Pattern 1 as the implementation blueprint. The file header must follow the project convention (see TranscriptRecord.swift above).

**ModelContainer init to replace** (LocalTranscriptStore.swift line 37):
```swift
// CURRENT (line 37):
container = try ModelContainer(for: TranscriptRecord.self, configurations: config)

// REPLACE WITH:
container = try ModelContainer(
    for: TranscriptRecord.self, PersonProfile.self,
    migrationPlan: AppMigrationPlan.self,
    configurations: config
)

// In-memory fallback (line 43) — no migrationPlan needed:
container = try! ModelContainer(for: TranscriptRecord.self, PersonProfile.self, configurations: config)
```

**migrateFromDefaultStore must NOT change** (lines 62-82): it opens only `TranscriptRecord.self` in its own `ModelContainer` without a migration plan — this is correct and must remain untouched.

---

### `macos/Services/LocalTranscriptStore.swift` (service, CRUD) — modify

**File to modify:** `macos/Services/LocalTranscriptStore.swift`

**Existing service pattern to copy for `upsertSelfProfile`** (lines 84-160 show CRUD method shape):
```swift
// Pattern: FetchDescriptor predicate + context.insert/save (lines 109-119, 86-89)
func record(forTaskId taskId: String) -> TranscriptRecord? {
    let descriptor = FetchDescriptor<TranscriptRecord>(
        predicate: #Predicate { $0.taskId == taskId }
    )
    return try? context.fetch(descriptor).first
}

func save(_ record: TranscriptRecord) throws {
    context.insert(record)
    try context.save()
}
```

**Error type pattern** (lines 163-173):
```swift
enum LocalStoreError: LocalizedError {
    case recordNotFound

    var errorDescription: String? {
        switch self {
        case .recordNotFound: return "Het lokale record kon niet worden gevonden."
        }
    }
}
```
Add a `personProfileNotFound` case to this enum if needed (NL error string).

**Logger pattern** (line 12):
```swift
private let logger = Logger(subsystem: "nl.prezent.ThoughtVault", category: "LocalTranscriptStore")
```

---

### `macos/Views/ProfileSettingsView.swift` (component, request-response) — new file

**Analog:** `macos/Views/SettingsView.swift` — `profielenSection` (lines 195-227) and `verbindingSection` save pattern (lines 100-193)

**Imports pattern** (SettingsView.swift lines 1-13):
```swift
import SwiftUI
// No AVFoundation/Speech needed for ProfileSettingsView — just SwiftUI
```

**Section structure pattern** (lines 197-227):
```swift
private var profielenSection: some View {
    Section {
        // content rows
    } header: {
        Text("Profielen")
    } footer: {
        Text("Het standaard profiel wordt automatisch geselecteerd...")
            .font(TS.Font.caption)
            .foregroundStyle(Color.labelTertiary)
    }
}
```

**Save button + isSaving state pattern** (lines 126-156):
```swift
@State private var showServerURLSaved: Bool = false   // -> @State private var isSaving: Bool = false

Button("Opslaan") {
    // validate -> call service -> show confirmation
}
.buttonStyle(SecondaryButtonStyle())
.disabled(/* no changes */ || isSaving)
```

**TextField pattern** (lines 108-118):
```swift
TextField("placeholder", text: $binding)
    .textFieldStyle(.plain)
    .font(TS.Font.body)
    .autocorrectionDisabled()
```

**Empty state pattern** (lines 207-210):
```swift
} else if profiles.isEmpty {
    Text("Geen profielen gevonden")
        .font(TS.Font.footnote)
        .foregroundStyle(Color.labelTertiary)
}
```

**Form wrapper** — `ProfileSettingsView` is a sub-view embedded inside `SettingsView`'s `Form { }`. It returns a `Section`, not a standalone `Form`. Follow the `profielenSection` shape exactly.

---

### `macos/Views/OnboardingView.swift` (component, request-response) — modify

**File to modify:** `macos/Views/OnboardingView.swift`

**OnboardingStep enum** (lines 30-84) — insertion point:
```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome        = 0
    case microphoon     = 1
    case spraak         = 2
    case agenda         = 3
    case schermopname   = 4
    // INSERT HERE:
    case profiel        = 5
    case klaar          = 6   // was 5, becomes 6
}
```

**Properties to add to the enum** (follow existing shape lines 38-83):
- `title`: NL string e.g. `"Jouw profiel"`
- `icon`: SF Symbol e.g. `"person.crop.circle"`
- `gradientColors`: pick from existing palette e.g. `[Color.gradientPurple, Color.brandPrimary.opacity(0.4)]`
- `isAvailableOnCurrentPlatform`: return `true` (no platform guard needed)

**stepContent switch** (lines 173-181) — add one case:
```swift
case .profiel: profielStep
```

**navigationFooter** (lines 554-599) — guard `currentStep == .klaar` already uses enum case, NOT raw value — safe, no change needed.

**advanceStep / goBackStep** (lines 697-715) — use `visibleSteps.firstIndex(of:)` index arithmetic — safe, no change needed.

**Skip button pattern from agendaStep** (lines 402-408):
```swift
Button("Overslaan") {
    advanceStep()
}
.buttonStyle(.plain)
.font(TS.Font.footnote)
.foregroundStyle(Color.labelSecondary)
```

**Step view structure pattern** (lines 186-217, welcomeStep):
```swift
private var profielStep: some View {
    VStack(spacing: TS.Spacing.xl) {
        Spacer()
        // hero icon: ZStack { Circle(...) + Image(systemName:) }
        // VStack title + description
        // form fields
        // Overslaan button
        Spacer()
        Spacer()
    }
}
```

---

### `macos/Models/Models.swift` — comment-only edit

Add immediately above the `struct Profile` declaration (around line 221):
```swift
// WARNING: Do NOT rename or reuse `Profile` for person-identity concepts.
// `PersonProfile` (@Model, PersonProfile.swift) is the new type for people/self-profile.
// `Profile` here is the notule-style template (zakelijk, informeel, etc.) — keep separate.
struct Profile: Identifiable, Codable, Hashable, Sendable {
```

---

### `windows/src/stores/personProfileStore.ts` (store, CRUD) — new file

**Analog:** `windows/src/stores/profilesStore.ts` (full file, 38 lines)

**Imports + create/persist pattern** (profilesStore.ts lines 1-5, 15-38):
```typescript
import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Profile } from "../types";         // -> PersonProfile

export const useProfilesStore = create<ProfilesState>()(
  persist(
    (set, get) => ({
      // state + actions
    }),
    {
      name: "profiles-store",                    // -> "person-profile-store" (MUST differ)
    }
  )
);
```

**Action shape** (profilesStore.ts lines 17-36 — update/get pattern):
```typescript
updateProfile: (id, updates) =>
  set((state) => ({
    profiles: state.profiles.map((p) =>
      p.id === id ? { ...p, ...updates } : p
    ),
  })),
getProfile: (id) => get().profiles.find((p) => p.id === id),
```

For `personProfileStore`, the store holds a single `profile: PersonProfile | null` (not an array). The upsert action is a spread-merge (see RESEARCH.md Pattern 5). Store name MUST be `"person-profile-store"` to avoid collision with `"profiles-store"`.

---

### `windows/src/types.ts` — modify (additive)

**Analog:** existing `Profile` interface (lines 76-93)

**Pattern to follow for new interface** (lines 76-93):
```typescript
export interface Profile {
  id: string;
  name: string;
  description?: string;
  // ...optional fields typed explicitly
}
```

Add `PersonProfile` after the existing `Profile` interface. All fields are required (not optional) except where the model allows absence. Use `string[]` for `aliases` and `meetingTypes` — consistent with existing `tags: string[]` in `Transcript` (line 70).

---

### `windows/src/components/onboarding/OnboardingWizard.tsx` — modify

**File to modify:** `windows/src/components/onboarding/OnboardingWizard.tsx`

**Step type and STEPS array** (lines 16-18):
```typescript
// CURRENT:
type Step = 0 | 1 | 2 | 3 | 4;
const STEPS = ["Welkom", "Server", "Microfoon", "Agenda", "Klaar"];

// AFTER:
type Step = 0 | 1 | 2 | 3 | 4 | 5;
const STEPS = ["Welkom", "Server", "Microfoon", "Agenda", "Profiel", "Klaar"];
```

**handleNext guard** (line 26):
```typescript
// CURRENT:
if (step < 4) setStep((s) => (s + 1) as Step);
// AFTER:
if (step < 5) setStep((s) => (s + 1) as Step);
```

**Navigation footer conditions** (lines 224-243):
```typescript
// CURRENT: step < 4 shows Volgende; step === 4 shows Beginnen
// AFTER:   step < 5 shows Volgende; step === 5 shows Beginnen
```

**New step content block** — insert between `step === 3` and `step === 4` (the current Klaar block becomes `step === 5`):
```tsx
{step === 4 && (
  <StepContent
    icon={<StepIcon icon={<Person24Regular style={{ fontSize: 28 }} />} />}
    title="Jouw profiel"
    description="Vertel ons wie je bent. Dit wordt later gebruikt om je vergaderingen te verrijken. Je kunt dit overslaan."
  >
    {/* form fields + Overslaan button */}
  </StepContent>
)}
```

**StepContent component** (lines 274-297) — reuse as-is, no changes needed.

**StepIcon component** (lines 254-272) — reuse as-is.

**handleComplete** (lines 33-36) — call `personProfileStore.upsertProfile(...)` before `setHasCompletedOnboarding(true)` when fields are filled; skip store call when skipped.

---

### `windows/src/components/settings/ProfileSettings.tsx` (component, request-response) — new file

**Analog:** `windows/src/components/onboarding/OnboardingWizard.tsx` (StepContent + form field inline style pattern, lines 99-130)

**Input field pattern** (OnboardingWizard.tsx lines 107-127):
```tsx
<input
  type="text"
  value={value}
  onChange={(e) => setValue(e.target.value)}
  style={{
    width: "100%",
    padding: "7px 10px",
    background: "var(--fill-control-default)",
    border: "1px solid var(--stroke-control-secondary)",
    borderBottom: "1px solid var(--stroke-control-default)",
    borderRadius: "var(--radius-sm)",
    color: "var(--text-primary)",
    fontSize: 13,
    outline: "none",
    fontFamily: "inherit",
    boxSizing: "border-box",
  }}
/>
```

**Label pattern** (lines 105-107):
```tsx
<label style={{ fontSize: 13, fontWeight: 500, color: "var(--text-secondary)" }}>
  Veldnaam
</label>
```

**Section heading pattern** — use `<h3>` with `color: "var(--text-primary)"` and `fontSize: 14/15` to match existing inline style convention.

**Save button** — use `className="btn btn-accent"` (same class as OnboardingWizard navigation buttons, line 169).

---

### `ThoughtVaultTests/PersonProfileTests.swift` (test, CRUD) — new file

**Analog:** `ThoughtVaultTests/TranscriptsViewModelTests.swift`

**Test file header + framework** (lines 1-8):
```swift
// PersonProfileTests.swift
// ThoughtVaultTests
// nl.prezent.ThoughtVault

import Testing
import Foundation
@testable import ThoughtVault
```

**Suite + @MainActor pattern** (lines 9-15):
```swift
@Suite("PersonProfile Tests")
struct PersonProfileTests {

    @Test("upsertSelfProfile creates record on empty store")
    @MainActor
    func upsertCreatesRecord() {
        // ...
    }
}
```

**Assertion style** — use Swift Testing `#expect(...)` throughout (NOT `XCTAssert`). See lines 25, 40, 55, 86 of TranscriptsViewModelTests.swift.

**In-memory container pattern for SwiftData tests** — use `ModelConfiguration(isStoredInMemoryOnly: true)` (same as LocalTranscriptStore fallback path, LocalTranscriptStore.swift line 42). Create the container in the test body or a helper, not as a stored property.

---

### `ThoughtVaultTests/MigrationTests.swift` (test, CRUD) — new file

**Analog:** `ThoughtVaultTests/ThoughtVaultTests.swift` (simpler XCTest style for one-off model tests)

**File header + framework** (ThoughtVaultTests.swift lines 1-3):
```swift
import XCTest
@testable import ThoughtVault
```

Use `XCTestCase` subclass (not Swift Testing `@Suite`) for migration tests that require setup/teardown of temporary store files — XCTest's `setUpWithError`/`tearDownWithError` pair is cleaner for filesystem-based tests. `ThoughtVaultTests.swift` demonstrates both assertion styles; migration tests can use `XCTAssertEqual` / `XCTAssertNotNil`.

---

## Shared Patterns

### @MainActor service class
**Source:** `macos/Services/LocalTranscriptStore.swift` lines 14-21
**Apply to:** `LocalTranscriptStore` (existing), `ProfileSettingsView` (reads via service)
```swift
@MainActor
final class LocalTranscriptStore {
    static let shared = LocalTranscriptStore()
    private var context: ModelContext { container.mainContext }
}
```
All new SwiftData context operations (`upsertSelfProfile`, `fetchSelfProfile`) go on `LocalTranscriptStore` — never access `ModelContext` directly from a View.

### OSLog logger
**Source:** `macos/Services/LocalTranscriptStore.swift` line 12
**Apply to:** Any new service-level file
```swift
private let logger = Logger(subsystem: "nl.prezent.ThoughtVault", category: "LocalTranscriptStore")
```

### FetchDescriptor predicate
**Source:** `macos/Services/LocalTranscriptStore.swift` lines 109-114
**Apply to:** `upsertSelfProfile` in `LocalTranscriptStore`
```swift
let descriptor = FetchDescriptor<TranscriptRecord>(
    predicate: #Predicate { $0.taskId == taskId }
)
return try? context.fetch(descriptor).first
```

### Settings Form/Section
**Source:** `macos/Views/SettingsView.swift` lines 44-93 (Form shell) + 197-227 (Section shape)
**Apply to:** `ProfileSettingsView`
```swift
// ProfileSettingsView returns a Section (not a Form) — embedded in SettingsView's Form
Section {
    // rows
} header: {
    Text("Profiel")
} footer: {
    Text("...")
        .font(TS.Font.caption)
        .foregroundStyle(Color.labelTertiary)
}
```

### zustand persist store
**Source:** `windows/src/stores/settingsStore.ts` lines 1-23
**Apply to:** `personProfileStore.ts`
```typescript
export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({ ...DEFAULT_SETTINGS, /* actions */ }),
    { name: "settings-store" }   // -> "person-profile-store"
  )
);
```

### Onboarding skip button
**Source:** `macos/Views/OnboardingView.swift` lines 402-408 (agendaStep "Overslaan")
**Apply to:** `profielStep` in OnboardingView (macOS), step 4 content in OnboardingWizard (Windows)
```swift
Button("Overslaan") {
    advanceStep()
}
.buttonStyle(.plain)
.font(TS.Font.footnote)
.foregroundStyle(Color.labelSecondary)
```

### Design tokens (macOS)
**Source:** Used throughout `SettingsView.swift` and `OnboardingView.swift`
**Apply to:** All new macOS views
- Spacing: `TS.Spacing.xs/sm/md/lg/xl`
- Font: `TS.Font.body`, `TS.Font.footnote`, `TS.Font.caption`, `TS.Font.title2Bold`
- Radius: `TS.Radius.sm`, `TS.Radius.md`
- Colors: `Color.brandPrimary`, `Color.labelPrimary/Secondary/Tertiary`, `Color.surfacePrimary/Secondary`, `Color.statusSuccess/Error`

### CSS variables (Windows)
**Source:** `windows/src/components/onboarding/OnboardingWizard.tsx` inline styles throughout
**Apply to:** `ProfileSettings.tsx`, onboarding profiel step
- `var(--fill-control-default)`, `var(--stroke-control-secondary)`, `var(--text-primary/secondary/tertiary)`
- `var(--fill-accent-default)`, `var(--radius-sm/md)`
- Button classes: `btn btn-accent`, `btn btn-ghost`

---

## No Analog Found

All files have analogs. No entries.

---

## Metadata

**Analog search scope:** `macos/Models/`, `macos/Services/`, `macos/Views/`, `windows/src/stores/`, `windows/src/components/onboarding/`, `windows/src/types.ts`, `ThoughtVaultTests/`
**Files scanned:** 10 source files read in full or targeted sections
**Pattern extraction date:** 2026-06-04
