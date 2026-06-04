# Phase 1: Self-Profile Foundation — Research

**Researched:** 2026-06-04
**Domain:** SwiftData versioned migration + SwiftUI onboarding + zustand persist (macOS + Windows)
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Introduce explicit `VersionedSchema` in `LocalTranscriptStore`. `SchemaV1` = `TranscriptRecord` only, `SchemaV2` = `TranscriptRecord` + `PersonProfile`. Use `MigrationStage.lightweight(fromVersion: SchemaV1, toVersion: SchemaV2)` via `SchemaMigrationPlan`, passed to `ModelContainer(for:migrationPlan:configurations:)`.
- **D-02:** The existing `migrateFromDefaultStore` one-time copy path must continue working after the versioned schema is introduced.
- **D-03:** `PersonProfile` is a full shared `@Model` reused by Phase 2 directory — not a minimal self-only model.
- **D-04:** Fields: `id` (UUID-string, `@Attribute(.unique)`), `name`, `role`, `organization`, `aliases: [String]`, `meetingTypes: [String]`, `isSelf: Bool`, `isInternal: Bool` (default `true`), `createdAt`, `updatedAt`. Phase 1 writes only the `isSelf == true` record.
- **D-05:** Name collision with existing `Profile` (notule-style, `Models.swift:221`) avoided by consistently naming the new type `PersonProfile` + a collision-warning comment in `Models.swift`.
- **D-06:** Self-profile onboarding step inserted between `schermopname` and `klaar` (macOS); before last step on Windows.
- **D-07:** Fully skippable via an explicit "Overslaan" button; all fields optional. Skipping creates no `PersonProfile` record.
- **D-08:** New dedicated Settings section ("Profiel" / "Over jou") on both platforms, separate from existing notule-Profile settings.
- **D-09:** Exactly one `isSelf == true` `PersonProfile` (singleton), via upsert: fetch `isSelf == true`, create if absent, edit in-place otherwise. Absent/empty profile is valid.

### Claude's Discretion
- Exact SwiftUI layout of onboarding step and Settings editor (within `TS.Spacing/Font/Radius` + `Color.brand*` tokens; Windows within Tailwind + Fluent).
- Windows storage: zustand `persist` store (localStorage, schemaless JSON — no migration risk) or a dedicated store; planner chooses.
- NL `Localizable.strings` / Windows i18n keys and exact copy (copy contract is in UI-SPEC).
- `meetingTypes`/`aliases` input: comma-separated chosen (per UI-SPEC).

### Deferred Ideas (OUT OF SCOPE)
- People directory (colleagues/externals), calendar-seed (Microsoft Graph attendees) — Phase 2 (B-01..B-03).
- `{{PEOPLE_CONTEXT}}` injection into notule generation — Phase 3 (C-01..C-04).
- Name→person mapping + editable owner assignment, `TranscriptRecord` attribution fields — Phase 4 (D-01..D-04).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| A-01 | Skippable onboarding step: naam, rol, organisatie, aliassen, meeting-types | OnboardingView.swift enum pattern confirmed; insertion point between `schermopname` (raw value 4) and `klaar` (raw value 5); Windows wizard step-type literal with STEPS array shift to 6 |
| A-02 | PersonProfile stored locally on-device, isSelf flag, works in local-mode without account | SwiftData @Model + VersionedSchema confirmed; Windows zustand persist (localStorage) confirmed via settingsStore.ts pattern |
| A-03 | Profile viewable/editable via Settings section on both platforms | macOS: Form + Section in SettingsView.swift confirmed pattern; Windows: SettingsPage.tsx section pattern confirmed |
| A-04 | App upgrade preserves existing transcript history via versioned SwiftData migration | MigrationStage.lightweight for additive new @Model is confirmed lightweight-safe per multiple sources; no data wipe |
</phase_requirements>

---

## Summary

Phase 1 adds the user's self-profile (name, role, organisation, aliases, meeting-types) as a first-class on-device data model on both macOS and Windows. The heaviest technical work is on macOS: the existing `LocalTranscriptStore` must be refactored from a bare `ModelContainer(for: TranscriptRecord.self, ...)` to a `VersionedSchema` / `SchemaMigrationPlan` pattern so that the new `PersonProfile` @Model is introduced without wiping `TranscriptRecord` history. Research confirms that adding a brand-new @Model type to a `VersionedSchema` V2 qualifies as a lightweight migration — no custom stage or data transformation is required.

On Windows the equivalent is simpler: a new dedicated `personProfileStore.ts` using the same zustand `persist` middleware already in use for `settingsStore.ts`. Since localStorage stores schemaless JSON there is no migration risk. Both platforms add an onboarding step (skippable) and a Settings section.

The single biggest risk is the `LocalTranscriptStore` migration: the existing initialiser passes only `TranscriptRecord.self` and has no migration plan. The refactoring must (a) wrap both old and new schemas in `VersionedSchema` enums, (b) route the `ModelContainer` init through `migrationPlan:`, and (c) ensure the pre-existing `migrateFromDefaultStore` path — which runs before the container is created — is unaffected. All other work (UI, Windows store, Settings) is straightforward pattern-following.

**Primary recommendation:** Implement the SwiftData migration first (task 1 of Wave 1), verify on-device with real data before writing any UI, then layer onboarding and Settings on top.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| PersonProfile persistence (macOS) | Database / Storage (`LocalTranscriptStore`, SwiftData) | — | Data ownership belongs in the store actor; UI reads via @Query or service calls |
| PersonProfile persistence (Windows) | Client (zustand persist / localStorage) | — | No backend; schemaless JSON store, same pattern as settingsStore |
| Onboarding step (macOS) | Frontend / SwiftUI View | — | Pure UI insertion in existing enum-driven TabView flow |
| Onboarding step (Windows) | Frontend / React component | — | Step index insertion in OnboardingWizard |
| Upsert logic (isSelf singleton) | Service / @MainActor class | — | SwiftData context operations must be on MainActor; Windows: store action |
| Settings editor (macOS) | Frontend / SwiftUI View | Service (upsert) | Form reads/writes via service, not raw ModelContext |
| Settings editor (Windows) | Frontend / React component | Store (zustand) | Direct store reads/writes |
| SwiftData schema migration | Database / Storage (LocalTranscriptStore init) | — | Migration runs at container creation time, before any UI |

---

## Standard Stack

### Core (macOS)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | iOS 17+ / macOS 14+ | Persistent @Model storage + migration | Already in use; `TranscriptRecord` is a SwiftData @Model |
| SwiftUI | iOS 17+ / macOS 14+ | UI layer | Project standard; `@Observable` ViewModels |
| Foundation | — | UUID, Date, etc. | Standard library |

### Core (Windows)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| zustand | (existing) | State + localStorage persistence | Already used in `settingsStore.ts` and `profilesStore.ts` |
| zustand/middleware `persist` | (existing) | JSON serialise to localStorage | Established pattern — zero migration risk |
| React | (existing) | Component UI | Project standard |
| @fluentui/react-icons | (existing) | `Person24Regular` icon for hero | Already imported in OnboardingWizard |

### No New Packages Required

This phase introduces zero new npm or Swift Package dependencies. All required capabilities (SwiftData migration, zustand persist, Fluent icons) are already in the project.

**Package Legitimacy Audit:** N/A — no new packages installed.

---

## Architecture Patterns

### System Architecture Diagram

```
[App launch]
     │
     ▼
LocalTranscriptStore.init()
     │
     ├─► VersionedSchema detection
     │       SchemaV1 (TranscriptRecord only)
     │       SchemaV2 (TranscriptRecord + PersonProfile)
     │
     ├─► ModelContainer(for: PersonProfile.self, TranscriptRecord.self,
     │                  migrationPlan: AppMigrationPlan.self,
     │                  configurations: config)
     │       └─► lightweight stage: SchemaV1 → SchemaV2 (adds PersonProfile table)
     │
     ├─► migrateFromDefaultStore (unchanged, runs only once if old store exists)
     │
     ▼
[Onboarding gate] ── hasCompletedOnboarding == false?
     │                       │
     │ yes                   │ no
     ▼                       ▼
ContentView          OnboardingView / OnboardingWizard
                            │
                     [profiel step]
                            │
                     ┌──────┴──────┐
                     │ filled      │ "Overslaan"
                     ▼             ▼
              upsert isSelf    no record
              PersonProfile    created
                     │
                     ▼
              [klaar / Beginnen]
                     │
                     ▼
              ContentView + Settings available

[Settings — Profiel section]
     │
     ├─► fetch isSelf==true PersonProfile (macOS: @Query / service; Windows: store selector)
     │
     ├─► empty state → "Profiel aanmaken" CTA
     └─► populated → edit in-place → "Profiel opslaan"
```

### Recommended File Structure

**macOS — new files:**
```
macos/
├── Models/
│   ├── PersonProfile.swift          # new @Model, SchemaV2 member
│   └── AppMigrationPlan.swift       # VersionedSchema enums + SchemaMigrationPlan
├── Views/
│   └── ProfileSettingsView.swift    # Settings editor (Form, upsert)
└── Services/
    └── LocalTranscriptStore.swift   # MODIFIED: add VersionedSchema + migrationPlan init
```

**Windows — new files:**
```
windows/src/
├── stores/
│   └── personProfileStore.ts        # new zustand persist store
├── types.ts                         # MODIFIED: add PersonProfile interface
└── components/
    ├── onboarding/
    │   └── OnboardingWizard.tsx      # MODIFIED: insert step 4, shift Klaar to 5
    └── settings/
        └── ProfileSettings.tsx      # new settings section component
```

### Pattern 1: SwiftData VersionedSchema with additive @Model

**What:** Wrapping existing and new @Model types in numbered VersionedSchema enums, linked by a SchemaMigrationPlan with a lightweight stage.
**When to use:** Any time a new @Model is added to an existing store.

```swift
// Source: atomicrobot.com/blog/an-unauthorized-guide-to-swiftdata-migrations/
// + donnywals.com/a-deep-dive-into-swiftdata-migrations/

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [TranscriptRecord.self]
    // TranscriptRecord definition lives in TranscriptRecord.swift (unchanged)
}

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [TranscriptRecord.self, PersonProfile.self]
    // Both models listed; PersonProfile is the addition
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self, AppSchemaV2.self]
    static var stages: [MigrationStage] = [v1ToV2]

    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )
}
```

**ModelContainer initialiser:**
```swift
// In LocalTranscriptStore.init()
let config = ModelConfiguration(url: newURL)
container = try ModelContainer(
    for: TranscriptRecord.self, PersonProfile.self,
    migrationPlan: AppMigrationPlan.self,
    configurations: config
)
```

**Critical:** The `for:` varargs list must include ALL model types used in the current schema (both `TranscriptRecord.self` and `PersonProfile.self`). [CITED: donnywals.com/a-deep-dive-into-swiftdata-migrations/]

### Pattern 2: PersonProfile @Model with [String] arrays

**What:** SwiftData natively handles `[String]` without `@Attribute(.externalStorage)` or transformable. The existing `TranscriptRecord.tags: [String]` is proof this already works in the project store.

```swift
// Source: existing TranscriptRecord.swift line 25 — [String] works natively
@Model
final class PersonProfile {
    @Attribute(.unique) var id: String
    var name: String
    var role: String
    var organization: String
    var aliases: [String]          // native SwiftData array — no transformer needed
    var meetingTypes: [String]     // same
    var isSelf: Bool
    var isInternal: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "",
        role: String = "",
        organization: String = "",
        aliases: [String] = [],
        meetingTypes: [String] = [],
        isSelf: Bool = false,
        isInternal: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) { ... }
}
```

### Pattern 3: isSelf Singleton Upsert (macOS)

```swift
// @MainActor service method on LocalTranscriptStore
func upsertSelfProfile(
    name: String, role: String, organization: String,
    aliases: [String], meetingTypes: [String]
) throws {
    let descriptor = FetchDescriptor<PersonProfile>(
        predicate: #Predicate { $0.isSelf == true }
    )
    if let existing = try? context.fetch(descriptor).first {
        existing.name = name
        existing.role = role
        existing.organization = organization
        existing.aliases = aliases
        existing.meetingTypes = meetingTypes
        existing.updatedAt = Date()
    } else {
        context.insert(PersonProfile(
            name: name, role: role, organization: organization,
            aliases: aliases, meetingTypes: meetingTypes,
            isSelf: true, isInternal: true
        ))
    }
    try context.save()
}
```

### Pattern 4: macOS OnboardingStep Insertion

**Existing enum (raw values are Int):**
```
welcome=0, microphoon=1, spraak=2, agenda=3, schermopname=4, klaar=5
```

**After insertion:**
```
welcome=0, microphoon=1, spraak=2, agenda=3, schermopname=4, profiel=5, klaar=6
```

The `advanceStep()` and `goBackStep()` methods use `visibleSteps` index arithmetic, not raw values — so raw value renumbering is safe. The `stepContent(_:)` switch must add a new case `.profiel`. The `navigationFooter` guard `currentStep == .klaar` uses the enum case, not raw value — safe.

**The `isAvailableOnCurrentPlatform` computed property** currently only gates `.schermopname`. The new `.profiel` step is available on all platforms (no guard needed).

### Pattern 5: Windows OnboardingWizard Step Insertion

**Current state:** `type Step = 0 | 1 | 2 | 3 | 4`, `STEPS = ["Welkom","Server","Microfoon","Agenda","Klaar"]`, `handleNext` guards on `step < 4`.

**After insertion:** New step at index 4 ("Profiel"), "Klaar" becomes index 5. Type union becomes `0|1|2|3|4|5`, `handleNext` guards on `step < 5`, `handleComplete` triggers at `step === 5`.

```tsx
// personProfileStore.ts — new dedicated store
import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { PersonProfile } from "../types";

interface PersonProfileState {
  profile: PersonProfile | null;
  upsertProfile: (updates: Partial<Omit<PersonProfile, "id" | "isSelf" | "createdAt">>) => void;
  clearProfile: () => void;
}

export const usePersonProfileStore = create<PersonProfileState>()(
  persist(
    (set, get) => ({
      profile: null,
      upsertProfile: (updates) =>
        set((state) => ({
          profile: state.profile
            ? { ...state.profile, ...updates, updatedAt: new Date().toISOString() }
            : {
                id: crypto.randomUUID(),
                isSelf: true,
                isInternal: true,
                name: "", role: "", organization: "",
                aliases: [], meetingTypes: [],
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
                ...updates,
              },
        })),
      clearProfile: () => set({ profile: null }),
    }),
    { name: "person-profile-store" }
  )
);
```

### Pattern 6: Collision-Warning Comment (D-05)

```swift
// In Models.swift, immediately above struct Profile:

// ⚠️ COLLISION WARNING: Do NOT rename or reuse `Profile` for person-identity concepts.
// `PersonProfile` (@Model, PersonProfile.swift) is the new type for people/self-profile.
// `Profile` here is the notule-style template (zakelijk, informeel, etc.) — keep separate.
struct Profile: Identifiable, Codable, Hashable, Sendable {
```

### Anti-Patterns to Avoid

- **Reusing `ProfilesStore` for `PersonProfile` (Windows):** `profilesStore.ts` manages notule-style `Profile` objects (zakelijk, informeel, etc.). Creating a separate `personProfileStore.ts` avoids type confusion and name collision. [VERIFIED: codebase]
- **Using `@Attribute(.externalStorage)` on `[String]` fields:** SwiftData natively stores `[String]` without annotation (proven by `TranscriptRecord.tags`). Adding `externalStorage` is unnecessary and may cause migration friction. [VERIFIED: codebase]
- **Hardcoding raw int values for OnboardingStep navigation:** The `advanceStep()` / `goBackStep()` methods use `visibleSteps.firstIndex(of: currentStep)` — index arithmetic, not raw values. Adding a new case does not break navigation as long as it is added to `OnboardingStep.allCases`. [VERIFIED: codebase]
- **Initialising ModelContainer without migrationPlan on upgrade:** Without `migrationPlan:`, SwiftData will either reject the store (schema mismatch) or silently recreate it. Always pass `migrationPlan:` once versioning is introduced. [CITED: atomicrobot.com, donnywals.com]
- **Running migrateFromDefaultStore after migrationPlan:** The existing `shouldMigrate` logic checks `!FileManager.default.fileExists(atPath: newURL.path)`. This runs before the container is even created, so it remains unaffected by adding `migrationPlan:` to the container init. [VERIFIED: codebase]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SwiftData schema migration | Custom SQLite schema diff + copy script | `MigrationStage.lightweight` | Handles all additive cases automatically; hand-rolled migration is a data-loss risk |
| Persistent JSON storage (Windows) | Custom localStorage read/write | zustand `persist` middleware | Already in project, handles serialisation, hydration, and partial updates |
| UUID generation (Swift) | Custom ID factory | `UUID().uuidString` (as in TranscriptRecord) | Consistent with existing model pattern |
| UUID generation (Windows) | Custom random string | `crypto.randomUUID()` | Web-standard, available in Tauri context |
| Comma-split on [String] save/load | Manual `split(",")` roundtrip | Store `[String]` directly in SwiftData / as JSON array in zustand | SwiftData handles arrays natively; zustand persist serialises arrays as JSON automatically |

**Key insight:** The project already has working patterns for every problem in this phase — this phase is wiring them together in a new configuration, not building new infrastructure.

---

## Common Pitfalls

### Pitfall 1: VersionedSchema.models incomplete list
**What goes wrong:** A VersionedSchema that omits `TranscriptRecord.self` from its `models` array will cause SwiftData to lose track of the existing model, leading to schema conflicts or a missing table error.
**Why it happens:** Easy to only list the "new" model in V2.
**How to avoid:** Every VersionedSchema version must list ALL models used by that version — both `TranscriptRecord.self` and `PersonProfile.self` in V2.
**Warning signs:** `ModelContainer` throws on init with "missing entity" or similar error.

### Pitfall 2: ModelContainer `for:` list not updated
**What goes wrong:** Passing only `TranscriptRecord.self` in the `for:` varargs while the migration plan expects `PersonProfile.self` causes a runtime crash.
**Why it happens:** `for:` is easy to overlook when adding `migrationPlan:`.
**How to avoid:** The `for:` list must mirror the current schema's `models` array — add `PersonProfile.self` alongside `TranscriptRecord.self`.
**Warning signs:** EXC_BAD_ACCESS or "could not find model class for entity PersonProfile" at launch.

### Pitfall 3: Two PersonProfile records with isSelf == true
**What goes wrong:** Race condition or double-tap on "Opslaan" creates a second `isSelf == true` record. Subsequent reads return an unexpected array.
**Why it happens:** Upsert fetch + insert is not atomic without a unique constraint on `isSelf`.
**How to avoid:** The upsert method (service-level) does fetch-first; additionally, the Settings view disables the save button while saving (`@State private var isSaving`). `@Attribute(.unique)` on `id` guards against duplicate IDs but not duplicate `isSelf`. Accept this: the upsert pattern is correct as long as called from the MainActor service, not directly from two concurrent UI paths.
**Warning signs:** `allProfiles.filter { $0.isSelf }` returns count > 1.

### Pitfall 4: Windows store name collision with profilesStore
**What goes wrong:** Using the same zustand store name `"profiles-store"` for `personProfileStore` would cause data corruption — zustand persist merges by key.
**Why it happens:** Copy-paste from profilesStore.ts.
**How to avoid:** Name the new store `"person-profile-store"` (distinct from `"profiles-store"` and `"settings-store"`).
**Warning signs:** Existing profile selector data unexpectedly mutated after saving PersonProfile.

### Pitfall 5: OnboardingWizard navigation logic not updated for 6 steps
**What goes wrong:** After adding step 4 (Profiel) and shifting Klaar to 5, if `handleNext` still guards `step < 4` or the "Beginnen" button still shows at `step === 4`, navigation skips Profiel or completes at the wrong step.
**Why it happens:** Step count hardcoded in multiple places in OnboardingWizard.tsx.
**How to avoid:** Update all three locations: `type Step` union, `handleNext` guard (`< 5`), and "Beginnen" condition (`=== 5`).
**Warning signs:** Clicking "Volgende" on Agenda jumps straight to Klaar.

### Pitfall 6: migrateFromDefaultStore opens old store without migration plan
**What goes wrong:** `migrateFromDefaultStore` creates its own `ModelContainer(for: TranscriptRecord.self, ...)` to read the old store. This does not need a migration plan because the old store schema matches `TranscriptRecord` exactly — but if PersonProfile is listed in `for:` here, it will expect the old store to have it and fail.
**Why it happens:** Unintentionally adding PersonProfile to the old-store container.
**How to avoid:** The `migrateFromDefaultStore` method opens only `TranscriptRecord.self` (no PersonProfile, no migration plan) — this is already correct in the current code and must not change.
**Warning signs:** Migration logs "No compatible local store to migrate" on first launch after upgrade.

---

## Code Examples

### Full LocalTranscriptStore migration refactor sketch

```swift
// AppMigrationPlan.swift (new file)
import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [TranscriptRecord.self]
}

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [TranscriptRecord.self, PersonProfile.self]
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self, AppSchemaV2.self]
    static var stages: [MigrationStage] = [v1ToV2]
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )
}

// LocalTranscriptStore.swift — changed init (diff only):
// OLD: container = try ModelContainer(for: TranscriptRecord.self, configurations: config)
// NEW:
container = try ModelContainer(
    for: TranscriptRecord.self, PersonProfile.self,
    migrationPlan: AppMigrationPlan.self,
    configurations: config
)
// The in-memory fallback changes similarly (no migrationPlan needed for in-memory).
```

### PersonProfile @Model (new file)

```swift
// macos/Models/PersonProfile.swift
import Foundation
import SwiftData

@Model
final class PersonProfile {
    @Attribute(.unique) var id: String
    var name: String
    var role: String
    var organization: String
    var aliases: [String]
    var meetingTypes: [String]
    var isSelf: Bool
    var isInternal: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "",
        role: String = "",
        organization: String = "",
        aliases: [String] = [],
        meetingTypes: [String] = [],
        isSelf: Bool = false,
        isInternal: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.organization = organization
        self.aliases = aliases
        self.meetingTypes = meetingTypes
        self.isSelf = isSelf
        self.isInternal = isInternal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

### Windows PersonProfile type (addition to types.ts)

```typescript
// windows/src/types.ts — add after existing interfaces
export interface PersonProfile {
  id: string;
  name: string;
  role: string;
  organization: string;
  aliases: string[];          // stored as JSON array in localStorage
  meetingTypes: string[];
  isSelf: boolean;
  isInternal: boolean;
  createdAt: string;          // ISO-8601
  updatedAt: string;
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ModelContainer(for: TranscriptRecord.self, configurations: config)` | `ModelContainer(for: ..., migrationPlan: AppMigrationPlan.self, configurations: config)` | Phase 1 (this phase) | Single point of change; no other callers |
| No PersonProfile type on either platform | `PersonProfile` @Model (macOS) + `PersonProfile` interface + zustand store (Windows) | Phase 1 (this phase) | Foundation for Phase 2-4 |
| 6-step OnboardingWizard (Windows: 5 steps) | 7-step (macOS: +profiel); 6-step (Windows: +Profiel) | Phase 1 (this phase) | Step count guards and type unions must be updated |

**Deprecated/outdated:**
- None — this phase introduces new things rather than replacing existing ones.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Adding a brand-new @Model type (no change to existing model) qualifies as lightweight migration — confirmed "likely" by multiple community sources but not by an authoritative Apple doc page (403/404) | Standard Stack, Common Pitfalls | If wrong: custom migration stage needed (still safe, just more code). Existing data not at risk either way — lightweight success = no wipe, custom stage = explicit copy. Verify on device before shipping. |
| A2 | `[String]` on PersonProfile stores natively without `@Attribute(.externalStorage)` — inferred from `TranscriptRecord.tags: [String]` already working in the same store | Code Examples | If wrong: add `@Attribute(.externalStorage)` or switch to `Data` with JSON codec. Low risk given existing evidence. |
| A3 | `ModelContainer(for: A.self, B.self, migrationPlan:, configurations:)` is the correct varargs overload — confirmed by community sources but Apple docs 404d | Standard Stack | If wrong: may need `Schema([A.self, B.self])` + explicit `ModelConfiguration` construction. Xcode compiler will surface this immediately. |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed.
*(Table is not empty — A1 should be validated by a quick test on a device with existing data before the PR ships.)*

---

## Open Questions (RESOLVED)

1. **Does lightweight migration fire for a fresh install (no V1 store)?**
   - What we know: SwiftData creates a new store with the current schema on first launch. The migration plan only runs if an older schema version is detected.
   - What's unclear: Whether SwiftData assigns V1 or V2 version stamp to a fresh install — relevant if a future V3 needs to migrate from V1 vs V2.
   - RESOLVED: Not blocking for Phase 1. Plan 01-01 Task 2 documents the fresh-install behaviour in a comment in `AppMigrationPlan.swift`.

2. **Windows: dedicated `personProfileStore` vs. embedding PersonProfile in `settingsStore`?**
   - What we know: Both patterns are feasible; `settingsStore` already holds `AppSettings`. The decision is marked Claude's Discretion.
   - RESOLVED: Dedicated `personProfileStore.ts` (Plan 01-03 Task 1) — cleaner separation, mirrors macOS model isolation, avoids growing `settingsStore` with people-domain data needed in Phase 2+.

---

## Environment Availability

No new external tools, services, runtimes, or CLI utilities are required. All dependencies (SwiftData, zustand, Fluent icons) are already in the project.

Step 2.6: SKIPPED (no new external dependencies — all required capabilities already present in project).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (macOS) |
| Config file | `TranscriptStudio.xcodeproj` scheme `TranscriptStudioTests` |
| Quick run command | `xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests -only-testing:TranscriptStudioTests/LocalTranscriptStoreTests CODE_SIGNING_ALLOWED=NO` |
| Full suite command | `xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests CODE_SIGNING_ALLOWED=NO` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| A-04 | Existing `TranscriptRecord` data survives migration to V2 schema | unit (in-memory container) | `xcodebuild test ... -only-testing:TranscriptStudioTests/MigrationTests` | ❌ Wave 0 |
| A-02 | `upsertSelfProfile` creates record on empty store | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/PersonProfileTests` | ❌ Wave 0 |
| A-02 | `upsertSelfProfile` updates in-place when isSelf record exists | unit | same | ❌ Wave 0 |
| A-02 | Skipping onboarding creates no PersonProfile record | unit | same | ❌ Wave 0 |
| A-03 | Settings upsert called from ProfileSettingsView saves correctly | integration (manual) | manual — UI interaction | manual |
| A-01 | Onboarding step appears between schermopname and klaar | manual | `xcodebuild build CODE_SIGNING_ALLOWED=NO` + visual inspection | manual |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme TranscriptStudioTests -only-testing:TranscriptStudioTests/PersonProfileTests CODE_SIGNING_ALLOWED=NO`
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `TranscriptStudioTests/MigrationTests.swift` — covers A-04 (migration preserves data). Uses in-memory V1 container with pre-seeded TranscriptRecord, then opens with V2 migration plan.
- [ ] `TranscriptStudioTests/PersonProfileTests.swift` — covers A-02 upsert logic (create + update paths, skip = no record).
- [ ] No framework install needed — XCTest already configured.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes (low severity) | All PersonProfile fields are free-text; no injection risk (not sent to backend in Phase 1). Comma-split on aliases/meetingTypes is client-side only. |
| V6 Cryptography | no | — |

**No high-severity security surface in Phase 1.** PersonProfile is stored on-device only and never transmitted (no backend call in this phase). The primary consideration is that storing user's name/role/org in localStorage (Windows) and SwiftData (macOS) is local-only — acceptable per the project's local-first privacy stance.

---

## Sources

### Primary (HIGH confidence)
- `macos/Services/LocalTranscriptStore.swift` — exact existing ModelContainer init, migrateFromDefaultStore pattern, store URL
- `macos/Views/OnboardingView.swift` — exact OnboardingStep enum, advanceStep/goBackStep logic, step layout patterns
- `macos/Models/TranscriptRecord.swift` — [String] array usage confirmation, @Attribute(.unique) pattern
- `macos/Models/Models.swift` lines 219–302 — Profile struct (collision risk confirmed)
- `windows/src/stores/settingsStore.ts` — zustand persist pattern
- `windows/src/components/onboarding/OnboardingWizard.tsx` — Step type, STEPS array, handleNext/handleComplete logic
- `windows/src/stores/profilesStore.ts` — confirms profilesStore is notule-Profile only (not reusable)
- `windows/src/components/layout/Sidebar.tsx` — routing and nav structure for settings placement

### Secondary (MEDIUM confidence)
- [Donny Wals — A Deep Dive into SwiftData Migrations](https://www.donnywals.com/a-deep-dive-into-swiftdata-migrations/) — ModelContainer(migrationPlan:) syntax, VersionedSchema code pattern
- [Atomic Robot — An Unauthorized Guide to SwiftData Migrations](https://atomicrobot.com/blog/an-unauthorized-guide-to-swiftdata-migrations/) — additive new @Model is lightweight-safe claim, VersionedSchema.models must include all types

### Tertiary (LOW confidence — see Assumptions Log)
- [byby.dev — SwiftData migrations](https://byby.dev/swiftdata-migrations) — ModelContainer(for:migrationPlan:configurations:) overload syntax
- WebSearch summary — lightweight migration covers "adding new models" claim

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in project, no new packages
- Migration pattern: MEDIUM — community-confirmed, Apple docs pages returned 403/404 during research; A1 in assumptions log
- Architecture / onboarding insertion: HIGH — code fully read, insertion points identified precisely
- Windows store pattern: HIGH — direct code read of settingsStore.ts and profilesStore.ts

**Research date:** 2026-06-04
**Valid until:** 2026-07-04 (SwiftData migration API is stable; zustand persist is stable)
