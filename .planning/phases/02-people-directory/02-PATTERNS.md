# Phase 2: People Directory - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 16 (8 macOS, 6 Windows, 2 test)
**Analogs found:** 16 / 16 (all have a Phase 1 precedent — Phase 2 is purely additive)

## File Classification

### macOS (Swift 6 / SwiftData)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `macos/Models/PersonProfile.swift` (modify) | model | CRUD | self (extend in place) | exact |
| `macos/Models/AppMigrationPlan.swift` (modify) | migration | transform | self (V1→V2 stage) | exact |
| `macos/Services/LocalTranscriptStore.swift` (modify) | service/store | CRUD | self (`upsertSelfProfile`/fetch) | exact |
| `macos/Services/PersonDirectoryService.swift` (NEW) | service | CRUD | `LocalTranscriptStore.swift` fetch/upsert | role+flow match |
| `macos/Services/CalendarService.swift` (modify) | model (struct) | transform | self (`CalendarEvent` struct :28) | exact |
| `macos/Services/MicrosoftGraphService.swift` (modify) | service | transform/decode | self (`GraphEvent` decode :439, :298) | exact |
| `macos/App/ContentView.swift` (modify) | route/nav | event-driven | self (`AppTab` enum :8, sidebar :214) | exact |
| `macos/ViewModels/RecordingViewModel.swift` (modify) | viewmodel | event-driven | self (`stopAndUpload` :369) | exact |
| `macos/Views/PeopleDirectoryView.swift` (NEW) | component | CRUD/list | `ProfileSettingsView.swift` | role match |
| `macos/Views/PersonEditView.swift` (NEW) | component | request-response | `ProfileSettingsView.swift` | exact (mirror) |
| `macos/Views/SeedReviewSheet.swift` (NEW) | component | request-response | `ProfileSettingsView.swift` (save UX) | role match |
| `macos/ViewModels/PeopleDirectoryViewModel.swift` (NEW) | viewmodel | CRUD | (no @Observable VM precedent in scope; see No Analog) | partial |

### Windows (Tauri 2 / React / Zustand)

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `windows/src/types.ts` (modify) | model (type) | — | self (`PersonProfile` :78, `CalendarEvent` :277) | exact |
| `windows/src/stores/peopleDirectoryStore.ts` (NEW) | store | CRUD | `personProfileStore.ts` | exact (mirror) |
| `windows/src/services/microsoftGraph.ts` (modify — bug fix only) | service | decode | self (mapping :176-187) | exact |
| `windows/src/pages/PeoplePage.tsx` (NEW) | component/page | CRUD/list | `SettingsPage.tsx` | role match |
| `windows/src/pages/PersonEditModal.tsx` (NEW) | component | request-response | `SettingsPage.tsx` (input rows) | role match |
| `windows/src/pages/SeedReviewSheet.tsx` (NEW) | component | request-response | `SettingsPage.tsx` | partial |
| `windows/src/App.tsx` (modify) | route/nav | event-driven | self (`<Routes>` :338, Ctrl-key :224) | exact |

### Tests

| New/Modified File | Role | Closest Analog | Match Quality |
|-------------------|------|----------------|---------------|
| `ThoughtVaultTests/MigrationTests.swift` (modify) | test | self (`testTranscriptRecordSurvivesV1ToV2Migration`) | exact |
| `ThoughtVaultTests/PersonDirectoryServiceTests.swift` (NEW) | test | `PersonProfileTests.swift` (in-mem container + upsert mirror) | exact (mirror) |
| `ThoughtVaultTests/GraphAttendeeDecodeTests.swift` (NEW) | test | `PersonProfileTests.swift` (XCTest/in-mem pattern) | role match |
| `windows/src/stores/__tests__/peopleDirectoryStore.test.ts` (NEW) | test | `windows/src/services/__tests__/*.test.ts` (vitest) | role match |

---

## Pattern Assignments

### `macos/Models/PersonProfile.swift` (model, CRUD) — MODIFY IN PLACE

**Analog:** self. Current model has non-optional `isInternal: Bool` and no `emails`. Two surgical changes (D-01, D-02).

**Current shape** (lines 17-32) — note `aliases`/`meetingTypes`/`expertiseTags` are already `[String]`, the precedent for `emails`:
```swift
var aliases: [String]
var meetingTypes: [String]
var expertiseTags: [String]
var isSelf: Bool
var isInternal: Bool          // CHANGE → Bool? (D-01)
var createdAt: Date
var updatedAt: Date
```

**Required changes:**
- Add `var emails: [String]` (D-02, mirrors the existing `[String]` props).
- Change `var isInternal: Bool` → `var isInternal: Bool?` (D-01, relaxing = lightweight-eligible).
- In `init` (lines 34-46): add `emails: [String] = []` param + assignment; change `isInternal: Bool = true` → `isInternal: Bool? = nil` (seeded entries default to onbekend).

**Caller impact:** `LocalTranscriptStore.upsertSelfProfile` (line 121-130) explicitly passes `isInternal: true` for the self record — keep that explicit `true` so the self profile stays "intern". Only seeded/new directory entries get `nil`.

---

### `macos/Models/AppMigrationPlan.swift` (migration, transform) — MODIFY

**Analog:** self — the V1→V2 stage is the exact template to copy.

**Current pattern** (lines 26-43):
```swift
enum AppSchemaV2: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(2, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self, PersonProfile.self]
}

enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated(unsafe) static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self, AppSchemaV2.self]
    nonisolated(unsafe) static var stages: [MigrationStage] = [v1ToV2]
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self)
}
```

**Required changes (mirror exactly, D-03):**
- Add `enum AppSchemaV3: VersionedSchema` with `versionIdentifier = Schema.Version(3, 0, 0)` and the same `models` list `[TranscriptRecord.self, PersonProfile.self]`.
- Append `AppSchemaV3.self` to `schemas`.
- Append `v2ToV3` to `stages` and add `static let v2ToV3 = MigrationStage.lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self)`.

**Anti-pattern:** Do NOT use a custom stage — both changes (Bool→Bool?, additive `emails`) are lightweight-eligible.

---

### `macos/Services/LocalTranscriptStore.swift` (service/store, CRUD) — MODIFY (minimal)

**Analog:** self. The container already lists `PersonProfile.self` (lines 37-41, 47) and the migration plan is inferred — **no `for:` change needed** (the V3 fields live on the current `PersonProfile`). The migration plan reference already covers V3 once `AppMigrationPlan` includes the stage.

**Existing fetch/upsert pattern to reuse** (the template for `PersonDirectoryService`):
```swift
// fetch self (lines 91-96)
func fetchSelfProfile() -> PersonProfile? {
    let descriptor = FetchDescriptor<PersonProfile>(predicate: #Predicate { $0.isSelf == true })
    return try? context.fetch(descriptor).first
}
// upsert: fetch-first-then-insert/edit + context.save() (lines 100-134)
// delete: context.delete(record); try context.save() (see line 168-172 delete + persist())
```

**Possible change:** `upsertSelfProfile` (lines 100-134) does not currently take/persist `emails`. If the self profile should hold the user's own email for seed dedup (Open Question 1 / D-10), add an `emails` param here. Planner's call — directory CRUD itself goes in the new `PersonDirectoryService`.

---

### `macos/Services/PersonDirectoryService.swift` (service, CRUD) — NEW

**Analog:** `LocalTranscriptStore.swift` — copy the `@MainActor` + `context` accessor + `FetchDescriptor`/`#Predicate`/`context.save()` patterns. **NO `URLSession`** (D-11, grep-gated).

**Container access pattern** (from `LocalTranscriptStore` lines 14-21):
```swift
@MainActor
final class PersonDirectoryService {
    private var context: ModelContext { LocalTranscriptStore.shared.container.mainContext }
}
```

**Directory fetch — filter `isSelf == false`** (mirror `fetchSelfProfile` predicate, invert the bool; Pitfall 5):
```swift
func directoryPeople() -> [PersonProfile] {
    let d = FetchDescriptor<PersonProfile>(
        predicate: #Predicate { $0.isSelf == false },
        sortBy: [SortDescriptor(\.name)]
    )
    return (try? context.fetch(d)) ?? []
}
```

**Insert/update/delete:** copy `context.insert(...)` + `try context.save()` (LocalTranscriptStore lines 120-133) and `context.delete(record); persist()` (lines 168-172).

**Dedup at seed time (D-10):** in-memory filter against `directoryPeople().flatMap(\.emails)` (lowercased Set), plus self/account email; name-normalized fallback (lowercase + trim + collapse whitespace) against `name`/`aliases`. Self/account email source: `MicrosoftGraphService.shared.accountEmail` (see `disconnect()` line 332 reference) and/or self-profile `emails`.

---

### `macos/Services/CalendarService.swift` (model struct, transform) — MODIFY

**Analog:** self — the `CalendarEvent` struct (lines 28-50). Windows is the reference shape (already has `attendees`/`organizer`).

**Current struct** (lines 28-35):
```swift
struct CalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date
    let meetingURL: URL?
    let platform: MeetingPlatform
    let calendarTitle: String
    // ADD: let attendees: [String]   (D-08)
    // ADD: let organizer: String?    (D-08)
}
```

**Caution:** `CalendarEvent` is also constructed by EventKit paths elsewhere in this file — adding non-defaulted `let`s breaks every initializer call site. Give the new fields defaults (`var attendees: [String] = []`, `var organizer: String? = nil`) OR audit every `CalendarEvent(...)` construction. Grep `CalendarEvent(` before changing.

---

### `macos/Services/MicrosoftGraphService.swift` (service, decode/transform) — MODIFY

**Analog:** self. The `$select` already requests `organizer,attendees` (line 273) but the `GraphEvent` decode struct (lines 439-445) drops them and the `compactMap` (lines 298-319) never maps them. This is the D-08 plumbing gap.

**Current decode struct** (lines 439-445):
```swift
private struct GraphEvent: Decodable {
    let id: String
    let subject: String?
    let start: GraphDateTime?
    let end: GraphDateTime?
    let onlineMeeting: GraphOnlineMeeting?
    // ADD: let organizer: GraphRecipient?
    // ADD: let attendees: [GraphAttendee]?
}
```

**Add nested decode types** (Graph v1.0 key is `address`, NOT `email` — see Shared Pattern "Graph attendee key"):
```swift
private struct GraphRecipient: Decodable { let emailAddress: GraphEmailAddress? }
private struct GraphAttendee: Decodable { let emailAddress: GraphEmailAddress? }
private struct GraphEmailAddress: Decodable { let name: String?; let address: String? }
```

**Map in the `compactMap`** (extend the `CalendarEvent(...)` return at lines 310-318):
```swift
let attendeeEmails = (event.attendees ?? []).compactMap { $0.emailAddress?.address }
let organizerEmail = event.organizer?.emailAddress?.address
return CalendarEvent(
    id: event.id,
    title: event.subject ?? "Vergadering",
    date: startDate, endDate: endDate,
    meetingURL: joinURL, platform: platform,
    calendarTitle: "Microsoft 365",
    attendees: attendeeEmails, organizer: organizerEmail
)
```

---

### `macos/App/ContentView.swift` (route/nav, event-driven) — MODIFY

**Analog:** self. Add a `people` case to the `AppTab` enum and wire it into the sidebar + tab switch.

**Enum to extend** (lines 8-60). Each `switch` (title/icon/selectedIcon/keyboardShortcut) needs a `.people` arm:
```swift
case people   // add to enum (line 8-14)
// title:        "Mensen"
// icon:         "person.2"
// selectedIcon: "person.2.fill"
```

**Keyboard shortcut conflict (IMPORTANT):** `keyboardShortcut` (lines 51-59) already assigns `"6"` to `.admin`. The UI-SPEC requests `6` for People — that collides. Planner must resolve: either give People a free key (e.g. `"7"`) or renumber. Flag for a decision; do not silently double-bind `6`.

**Sidebar + detail switch:** the `macOSView`/`sidebarView` (line 214+) iterates `AppTab.allCases` — adding the enum case auto-adds the sidebar row; the detail `switch selectedTab` must get a `.people:` arm routing to `PeopleDirectoryView()`.

---

### `macos/ViewModels/RecordingViewModel.swift` (viewmodel, event-driven) — MODIFY

**Analog:** self. The seed-trigger linkage gap (research Pitfall 3, memory obs 26369).

**Where recording starts from an event:** `ContentView.swift` `CallAlertView.onStartRecording` (lines 134-138) and `.meetingRecordRequested`/`.videoCallDetected` handlers (lines 164-176) currently set only `recordingVM.selectedMode` and drop the `meeting`. Add an `activeMeeting: CalendarEvent?` (or `activeAttendees: [String]`) property on the VM, set it in those three call sites, clear it on cancel.

**Where to read it:** `stopAndUpload()` (line 369). Capture `activeMeeting` at stop-start; present the review-sheet from the View layer **after** `recordingState` settles — NOT inside each upload branch (the func returns early in local/onDevice/cloud/offline paths, lines 380-428+). Clear `activeMeeting` after.

---

### `macos/Views/PersonEditView.swift` (component, request-response) — NEW

**Analog:** `ProfileSettingsView.swift` — mirror it field-for-field (UI-SPEC says "mirrors ProfileSettingsView exactly").

**State + form-fields pattern** (ProfileSettingsView lines 16-25, 73-123):
```swift
@State private var naam: String = ""
@State private var rol: String = ""
// ... @State private var saveError: String? = nil

LabeledContent("Naam") {
    TextField("Naam", text: $naam)
        .textFieldStyle(.plain).font(TS.Font.body)
        .autocorrectionDisabled().multilineTextAlignment(.trailing)
}
```

**Comma-separated tag input (D-06 — reuse, do NOT use chips)** (lines 115-121, 178-182):
```swift
LabeledContent("Expertise / onderwerpen") {
    TextField("grafisch ontwerp, marketing, IT (kommagescheiden)", text: $expertise)
}
// load:  expertise = person.expertiseTags.joined(separator: ", ")   (line 169)
// save with splitAndTrim (lines 178-182):
let splitAndTrim: (String) -> [String] = { input in
    input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}
```

**Save button + transient "Opgeslagen" + error** (lines 127-205):
```swift
.buttonStyle(PrimaryButtonStyle())   // accent CTA
// isSaving spinner → showSaved checkmark for 2s (Task.sleep(for: .seconds(2))) → reset
// saveError shown in Color.statusError, TS.Font.caption
```

**New vs ProfileSettingsView:** add the tri-state `Picker` for `isInternal` (Intern/Extern/Onbekend; nil = Onbekend default) — UI-SPEC line 153. No precedent for the segmented picker in Phase 1; build per UI-SPEC.

---

### `macos/Views/PeopleDirectoryView.swift` (component, CRUD/list) — NEW

**Analog:** `ProfileSettingsView.swift` for tokens/empty-state copy; no list precedent in scope (see No Analog).

**Reuse:** empty-state pattern (ProfileSettingsView lines 59-69: heading `TS.Font.bodyMedium`, body `TS.Font.footnote`/`labelSecondary`); `Color.brandPrimary` reserved for the "Persoon toevoegen" CTA only (UI-SPEC). Status dot colors per UI-SPEC lines 109-112 (`brandAccent` green / `brandSecondary` blue / `labelTertiary` gray).

**List specifics from UI-SPEC:** `searchable()` filter on name+aliases+email; trailing edit + delete buttons with `.accessibilityLabel`; delete via `confirmationDialog` (not `Alert`).

---

### `macos/Views/SeedReviewSheet.swift` (component, request-response) — NEW

**Analog:** `ProfileSettingsView.swift` save UX (lines 127-205) + UI-SPEC layout (lines 278-291). Per-person checkbox row (default ON), primary "Voeg {n} personen toe" disabled when 0 checked, "Overslaan" secondary. No auto-commit (D-07).

---

### `windows/src/types.ts` (model type) — MODIFY

**Analog:** self. `PersonProfile` at line 78, `CalendarEvent` at line 277 (already has `attendees?`/`organizer?` lines 284-285 — no change there).

**Changes to `PersonProfile`** (line 78-87):
```typescript
isInternal: boolean;   // CHANGE → boolean | null   (null = onbekend)
// ADD: emails: string[];
```

---

### `windows/src/stores/peopleDirectoryStore.ts` (store, CRUD) — NEW

**Analog:** `personProfileStore.ts` — copy the `create<...>()(persist(...))` shape, but a collection instead of a singleton.

**Pattern** (personProfileStore lines 13-47):
```typescript
export const usePeopleDirectoryStore = create<PeopleDirectoryState>()(
  persist((set, get) => ({
    people: [],   // PersonProfile[] with isSelf=false
    addPerson: (p) => set((s) => ({ people: [...s.people, p] })),
    updatePerson: (id, u) => set((s) => ({ people: s.people.map(x =>
      x.id === id ? { ...x, ...u, updatedAt: new Date().toISOString() } : x) })),
    removePerson: (id) => set((s) => ({ people: s.people.filter(x => x.id !== id) })),
  }), { name: "people-directory-store" })   // DISTINCT key — Pitfall 4 (collides with "person-profile-store"/"profiles-store"/"settings-store" if reused)
);
```
New-person factory mirrors personProfileStore lines 25-38 but `isSelf: false`, `isInternal: null`, `emails: []`.

---

### `windows/src/services/microsoftGraph.ts` (service, decode) — MODIFY (bug fix)

**Analog:** self (lines 176-187). **Research A2 / Pitfall 2 confirmed:** the mapping reads `a.emailAddress?.email` (line 185) but the Graph v1.0 key is `address` — attendees are currently silently dropped/undefined. Fix to `address`:
```typescript
attendees: ((e.attendees as Array<Record<string, Record<string, string>>>)?.map(
  (a) => a.emailAddress?.address       // was: .email (wrong key)
).filter(Boolean)),
```
`organizer` reads `.name` (line 183) which is intentional for display — but for dedup the email is `organizer.emailAddress.address`. Confirm what the seed needs before changing organizer.

---

### `windows/src/App.tsx` (route/nav, event-driven) — MODIFY

**Analog:** self. Add a `/people` route and nav item.

**Routes block** (lines 338-348) — add:
```tsx
<Route path="/people" element={<PeoplePage />} />
```
**Ctrl-key shortcuts** (lines 224-228) currently use 1-5 (5 = `/profiles`). Pick a free key for `/people` (e.g. `6`). Sidebar nav item: Fluent `People24Regular`.

---

### `windows/src/pages/PeoplePage.tsx` + `PersonEditModal.tsx` (component) — NEW

**Analog:** `SettingsPage.tsx` — copy the page scaffold (lines 90-102):
```tsx
<div className="page-scroll">
  <div className="page-header"><h1 className="page-title-sm">Mensen</h1>{/* CTA btn-primary */}</div>
  <div className="page-content">
    <div className="page-content-narrow">
      <input className="input" placeholder="Zoeken..." />
      <div className="settings-group">{/* person rows */}</div>
    </div>
  </div>
</div>
```
Text inputs use `className="input"` (SettingsPage lines 120, 228+). Save to `usePeopleDirectoryStore`.

---

### `ThoughtVaultTests/MigrationTests.swift` (test) — MODIFY

**Analog:** self. Existing `testTranscriptRecordSurvivesV1ToV2Migration` (the only case) seeds a `TranscriptRecord` through the real `AppMigrationPlan` in-memory container and asserts survival. **Add a PersonProfile V2→V3 survival case** (research Pitfall 1 / Wave 0): seed an `isSelf==true` PersonProfile + a TranscriptRecord, run through `AppMigrationPlan`, assert both survive, `emails == []`, and `isInternal` preserved (non-nil).

**Container construction to copy** (lines 18-24):
```swift
let config = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
                                   migrationPlan: AppMigrationPlan.self, configurations: config)
```

---

### `ThoughtVaultTests/PersonDirectoryServiceTests.swift` + `GraphAttendeeDecodeTests.swift` (test) — NEW

**Analog:** `PersonProfileTests.swift` — copy `makeInMemoryContainer()` helper (lines 14-22) and the upsert-mirror approach (test operates on an arbitrary `ModelContext`). CRUD round-trip asserting only `isSelf==false` returned (B-02); dedup unit (D-10); decode test feeds fixture Graph JSON through the new `GraphEvent` decode and asserts `attendees` map `emailAddress.address` (B-03, A2).

---

### `windows/src/stores/__tests__/peopleDirectoryStore.test.ts` (test) — NEW

**Analog:** `windows/src/services/__tests__/*.test.ts` (vitest, `npx vitest run`). Round-trip add/update/remove + dedup + distinct localStorage key (B-01/B-04/D-10/Pitfall 4).

---

## Shared Patterns

### Comma-separated tag input (`splitAndTrim`)
**Source:** `macos/Views/ProfileSettingsView.swift` lines 100, 116, 178-182
**Apply to:** `PersonEditView` (macOS) + `PersonEditModal` (Windows) for `aliases` and `expertiseTags`.
**Reason:** D-06 requires consistency with Phase 1 onboarding, which chose comma-separated — NOT chips.
```swift
let splitAndTrim: (String) -> [String] = { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
// load: field = arr.joined(separator: ", ")
```

### SwiftData CRUD over the shared container
**Source:** `macos/Services/LocalTranscriptStore.swift` lines 14-21, 91-96, 120-133, 168-172
**Apply to:** `PersonDirectoryService` (all persistence).
**Reason:** Single source of truth; the directory shares `LocalTranscriptStore.shared.container`. Pattern: `@MainActor` class, `context` computed from `container.mainContext`, `FetchDescriptor` + `#Predicate`, `context.insert/delete`, `try context.save()`. **No `URLSession`** (D-11, grep gate `! grep -q URLSession PersonDirectoryService.swift`).

### Lightweight VersionedSchema migration stage
**Source:** `macos/Models/AppMigrationPlan.swift` lines 26-43
**Apply to:** the new `AppSchemaV3` + `v2ToV3` stage. Mirror exactly; both V3 changes are lightweight-eligible.

### Graph attendee email key = `address` (NOT `email`)
**Source:** Microsoft Graph v1.0 `emailAddress` object — confirmed Windows bug at `microsoftGraph.ts:185` (`.email`).
**Apply to:** macOS `GraphEmailAddress` decode (`let address: String?`) AND the Windows fix.
**Reason:** Research A2 / Pitfall 2 — the wrong key silently produces `undefined`/empty attendees, which makes the seed always show zero candidates.

### PrimaryButtonStyle + transient "Opgeslagen" save feedback
**Source:** `macos/Views/ProfileSettingsView.swift` lines 127-205
**Apply to:** `PersonEditView`, `SeedReviewSheet` save buttons.
**Reason:** `Color.brandPrimary` reserved for primary CTAs only (UI-SPEC); spinner → checkmark "Opgeslagen" for 2s → reset; errors in `Color.statusError`/`TS.Font.caption`.

### zustand `persist` store with distinct localStorage key
**Source:** `windows/src/stores/personProfileStore.ts` lines 13-47
**Apply to:** `peopleDirectoryStore.ts` — key `"people-directory-store"`.
**Reason:** Pitfall 4 — localStorage keys are global; reusing `"person-profile-store"`/`"profiles-store"`/`"settings-store"` corrupts state.

### Self-profile must never appear as an editable directory row
**Source:** `macos/Services/LocalTranscriptStore.swift` line 93 (`#Predicate { $0.isSelf == true }`) — invert it
**Apply to:** macOS `directoryPeople()` (`isSelf == false`) + Windows `.filter(p => !p.isSelf)`.
**Reason:** Pitfall 5 / D-05 — preserves the Phase 1 singleton invariant.

---

## No Analog Found

| File | Role | Data Flow | Reason / Guidance |
|------|------|-----------|-------------------|
| `macos/ViewModels/PeopleDirectoryViewModel.swift` | viewmodel | CRUD | Phase 1 self-profile UX was a stateless `View` (`ProfileSettingsView` uses `@State` + direct store calls), not an `@Observable` VM. If a VM is wanted, follow the project convention (`@MainActor @Observable class`, async/await — CLAUDE.md) and wrap `PersonDirectoryService`. A VM may be optional: the directory list could call the service directly like `ProfileSettingsView` does. Planner decision. |
| `PeopleDirectoryView` / `PeoplePage` list rows | component | CRUD/list | No existing searchable list-of-cards with per-row edit/delete in scope. Use UI-SPEC layout (lines 242-258, 293-308) + RESEARCH.md. macOS `List` + `searchable()` + `confirmationDialog`; Windows `settings-group` rows + hover-reveal delete + inline confirm. |
| `SeedReviewSheet` (both) | component | request-response | No per-person confirm sheet precedent. Build from UI-SPEC (lines 278-291, 157-162) + ProfileSettingsView save UX. |
| tri-state `isInternal` Picker | component | — | No segmented picker precedent in Phase 1. Build per UI-SPEC line 153 (macOS `.segmented` Picker Intern/Extern/Onbekend; Windows radio/select). |

---

## Open Items For Planner (flagged conflicts)

1. **macOS keyboard shortcut collision:** `AppTab.admin` already binds `"6"` (`ContentView.swift:58`). UI-SPEC requests `6` for People. Pick a non-colliding key.
2. **`CalendarEvent` struct init blast radius (macOS):** adding non-defaulted `let attendees`/`organizer` breaks EventKit construction sites. Default them or audit `grep "CalendarEvent("`.
3. **Self/account email source for dedup** (RESEARCH Open Question 1): use `MicrosoftGraphService.shared.accountEmail` ∪ self-profile `emails`; Apple-only-calendar users may need to enter their own email once.
4. **Windows `organizer` mapping** reads `.name` (display), not email — fine for UI, but seed dedup needs `organizer.emailAddress.address`.

## Metadata

**Analog search scope:** `macos/{Models,Services,Views,ViewModels,App}`, `windows/src/{types.ts,stores,services,pages,App.tsx}`, `ThoughtVaultTests/`
**Files scanned (read in full or targeted):** PersonProfile.swift, AppMigrationPlan.swift, LocalTranscriptStore.swift, ProfileSettingsView.swift, CalendarService.swift (:1-60), MicrosoftGraphService.swift (:255-454), ContentView.swift (:1-220), RecordingViewModel.swift (:369-428), MigrationTests.swift, PersonProfileTests.swift (:1-40), personProfileStore.ts, types.ts (grep), microsoftGraph.ts (:170-195 + grep), App.tsx (grep), SettingsPage.tsx (grep)
**Pattern extraction date:** 2026-06-05
