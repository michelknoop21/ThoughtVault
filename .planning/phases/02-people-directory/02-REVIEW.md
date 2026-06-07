---
phase: 02-people-directory
reviewed: 2026-06-07T15:56:00Z
depth: standard
files_reviewed: 18
files_reviewed_list:
  - macos/Models/PersonProfile.swift
  - macos/Models/AppMigrationPlan.swift
  - macos/Services/CalendarService.swift
  - macos/Services/MicrosoftGraphService.swift
  - macos/Services/PersonDirectoryService.swift
  - macos/ViewModels/RecordingViewModel.swift
  - macos/App/ContentView.swift
  - macos/Views/PeopleDirectoryView.swift
  - macos/Views/PersonEditView.swift
  - macos/Views/SeedReviewSheet.swift
  - windows/src/types.ts
  - windows/src/stores/peopleDirectoryStore.ts
  - windows/src/stores/recordingStore.ts
  - windows/src/services/microsoftGraph.ts
  - windows/src/pages/PeoplePage.tsx
  - windows/src/pages/PersonEditModal.tsx
  - windows/src/pages/SeedReviewSheet.tsx
  - windows/src/App.tsx
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: issues_found
---

# Phase 02: People Directory — Code Review Report

**Reviewed:** 2026-06-07T15:56:00Z
**Depth:** standard
**Files Reviewed:** 18
**Status:** issues_found

## Summary

Phase 2 is a well-structured additive build on Phase 1 primitives. The SwiftData
migration plan is correctly assembled, the Graph `emailAddress.address` fix is
correctly applied on both platforms, the `isSelf == false` invariant is enforced
in the directory store, and the no-network constraint in `PersonDirectoryService`
holds (grep-gated). The two Critical findings are: a silent data-loss path in
`PersonDirectoryService.add()` / `update()` (swallowed `try?` that discards
SwiftData save errors), and a dedup gap on the Windows side where self-profile
emails are never added to the known-email set — allowing the user's own email to
appear in the seed sheet when the `selfEmail` parameter is absent. Warnings
cover a new `PersonDirectoryService` instance being created per-save in both
macOS view files (bypassing the shared container's change tracking), a duplicate
email admission risk in the macOS dedup due to no per-candidate lowercasing
before insertion, and two cross-platform parity gaps in name derivation.

---

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: SwiftData save errors silently discarded — no feedback on write failure

**File:** `macos/Services/PersonDirectoryService.swift:52,59,79`
**Issue:** `add()` and `update()` both use `try? context.save()`, discarding
errors silently. If SwiftData fails to persist (e.g. migration-related constraint
violation, disk full, store unavailable), the app returns normally and the view
shows "Opgeslagen" while the data was never written. The user has no indication
their entry was lost.

The `deletePerson(id:)` and `updatePerson(id:name:)` methods do propagate errors
via `throws`, but the `add` / `update` surface — which the UI uses — does not.

**Fix:**
```swift
// Change add() and update() to throw, or at minimum log + surface the error:
func add(_ person: PersonProfile) throws {
    context.insert(person)
    try context.save()
}

func update(_ person: PersonProfile) throws {
    person.updatedAt = Date()
    try context.save()
}
```
Callers in `PersonEditView.savePerson()` and `SeedReviewSheet.saveSelected()` should
catch and surface the error to the user instead of silently succeeding.

---

### CR-02: Windows dedup misses self-profile emails — user's own email can appear in seed sheet

**File:** `windows/src/stores/peopleDirectoryStore.ts:60-78`
**Issue:** `newSeedCandidates()` only adds `selfEmail` (the parameter passed by
the caller) to `knownEmails`. It never reads the self-profile from
`personProfileStore` (where `isSelf === true` is stored with its own `emails`
array). On the macOS side, `PersonDirectoryService.newSeedCandidates()` explicitly
fetches `LocalTranscriptStore.shared.fetchSelfProfile()?.emails` and unions them
in. The Windows store does not do this.

Consequence: if the user's own email is stored in the self-profile `emails` field
but is not passed as the `selfEmail` argument (which happens when the Graph account
email is different from the self-profile email, or when the user set their email in
the profile but not in Graph), their own address will appear as a seed candidate.
This violates D-10.

**Fix:**
```typescript
// In newSeedCandidates, also read from personProfileStore:
import { usePersonProfileStore } from "./personProfileStore";

newSeedCandidates: (attendeeEmails, selfEmail) => {
  const { people } = get();
  const selfProfile = usePersonProfileStore.getState().profile;

  const knownEmails = new Set<string>();
  for (const person of people) {
    for (const email of person.emails) {
      knownEmails.add(email.toLowerCase());
    }
  }
  // Add self-profile emails (D-10 parity with macOS)
  for (const email of selfProfile?.emails ?? []) {
    knownEmails.add(email.toLowerCase());
  }
  if (selfEmail) {
    knownEmails.add(selfEmail.toLowerCase());
  }
  return attendeeEmails.filter((email) => !knownEmails.has(email.toLowerCase()));
},
```

---

## Warnings

### WR-01: PersonEditView and SeedReviewSheet each construct a new PersonDirectoryService() at save time — bypasses shared context

**File:** `macos/Views/PersonEditView.swift:201`, `macos/Views/SeedReviewSheet.swift:141`
**Issue:** Both view files call `let service = PersonDirectoryService()` inside
their save handler. `PersonDirectoryService.init()` calls
`LocalTranscriptStore.shared.container`, which returns the same `ModelContainer`,
so persistence will work. However, each new `PersonDirectoryService` instance
creates its own implicit `ModelContext` reference (`_container.mainContext`).
Simultaneously, `PeopleDirectoryView` holds its own `@State private var service =
PersonDirectoryService()`. These are all separate instances deriving from the same
`mainContext` — which in SwiftData is a singleton per container — so they do not
actually hold independent contexts. But the pattern is fragile: if
`PersonDirectoryService` were ever refactored to hold its own `ModelContext`
(`ModelContext(container)` instead of `container.mainContext`), the current code
would silently diverge. More concretely: `PeopleDirectoryView.loadPeople()` reads
from its `service` instance after `PersonEditView.savePerson()` writes via a
different transient instance. Since both arrive at `mainContext` this works today,
but it is not obvious and is unnecessary.

**Fix:** Pass the shared `PersonDirectoryService` instance down from the parent
view (dependency injection via the environment), or declare it as
`@Environment(PersonDirectoryService.self)` — consistent with how `RecordingViewModel`
and `CalendarService` are used in `ContentView`. Alternatively, make
`PersonDirectoryService` a singleton (`static let shared`), matching the
`LocalTranscriptStore.shared` pattern.

---

### WR-02: macOS dedup does not deduplicate when the same attendee email appears twice in the input list

**File:** `macos/Services/PersonDirectoryService.swift:115-134`
**Issue:** `newSeedCandidates(from:selfEmail:)` filters against `knownEmails` but
does not deduplicate the `attendeeEmails` input itself. If Graph returns the same
email address twice in a meeting (e.g. one as a required attendee and once as an
optional), both copies pass the filter and the seed sheet shows the same person
twice, leading to two `PersonProfile` inserts with the same email.

```swift
return attendeeEmails
    .map { $0.lowercased() }
    .filter { !knownEmails.contains($0) && !selfSet.contains($0) }
// Missing: dedup the result itself
```

**Fix:**
```swift
var seen = Set<String>()
return attendeeEmails
    .map { $0.lowercased() }
    .filter { !knownEmails.contains($0) && !selfSet.contains($0) }
    .filter { seen.insert($0).inserted }
```

---

### WR-03: Windows SeedReviewSheet name derivation is inconsistent with macOS — single-word capitalization vs. split-on-separators

**File:** `windows/src/pages/SeedReviewSheet.tsx:34-36`
**Issue:** Windows derives a display name as:
```ts
const displayName = emailPrefix.charAt(0).toUpperCase() + emailPrefix.slice(1);
// "jsmith" → "Jsmith"
```
macOS derives it as:
```swift
prefix
    .components(separatedBy: CharacterSet(charactersIn: "._-"))
    .map { $0.capitalized }
    .joined(separator: " ")
// "j.smith" → "J Smith"
```
For emails like `j.smith@company.com`, macOS produces "J Smith", Windows produces
"J.smith". For `john_doe@company.com` macOS produces "John Doe", Windows produces
"John_doe". The Windows rendering is clearly degraded and inconsistent with macOS.

**Fix:** Apply the same split-on-separators logic in Windows:
```ts
const displayName = emailPrefix
  .split(/[._-]/)
  .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
  .join(" ");
```

---

### WR-04: AppTab keyboard shortcut ordering is non-sequential — "5" skipped, "6"=admin, "7"=people

**File:** `macos/App/ContentView.swift:55-65`
**Issue:** The keyboard shortcut mapping is:
```
home=1, record=2, tasks=3, transcripts=4, people=7, settings=5, admin=6
```
People is bound to "7" with "6" skipped for admin (only visible to admin users),
meaning a regular user (no admin tab) sees shortcuts 1-5 and 7, with no "6". The
gap creates a confusing UX where pressing ⌘6 either does nothing (non-admin) or
opens Admin (admin). While this was an intentional decision documented in plan
02-04 (admin took "6" before people was specced), the result for the common case
(non-admin users) is a permanent ⌘6 dead key.

**Fix:** Consider rebinding people to "6" and admin to "8" (or omitting admin's
shortcut entirely since it is rarely used). The shortcut gap only affects macOS
sidebar navigation, not functionality.

---

### WR-05: MicrosoftGraphService.getUpcomingEvents() uses `/me/calendar/calendarView` (Windows) vs `/me/calendarView` (macOS)

**File:** `windows/src/services/microsoftGraph.ts:159`
**Issue:** Windows requests:
```
/me/calendar/calendarView
```
macOS requests:
```
/me/calendarView
```
Both are valid Graph v1.0 endpoints, but `/me/calendarView` aggregates all
calendars (including shared calendars in Exchange), while `/me/calendar/calendarView`
queries only the default calendar. For users with meetings in non-default calendars
(e.g. a shared team calendar), the Windows app will silently miss those events and
produce fewer seed candidates than macOS. This is a functional parity gap that
directly impacts D-07/D-08/D-10 correctness.

**Fix:**
```ts
// Change Windows to use the same endpoint as macOS:
url: `${GRAPH_BASE}/me/calendarView?${params}`,
```

---

## Info

### IN-01: PersonProfile.isInternal SwiftData migration note missing from AppMigrationPlan comment

**File:** `macos/Models/AppMigrationPlan.swift:6`
**Issue:** The file comment says "V2→V3 adds emails: [String] (additive) and
relaxes isInternal: Bool → Bool?". This is technically accurate but does not
mention the edge case flagged in the research (Assumption A1): the `emails: [String]`
field is added to an already-persisted model row (the self profile). This is a
different scenario from V1→V2 (where `PersonProfile` itself was new). A future
maintainer adding another collection field may not know to run the migration test.
The Pitfall 1 warning in RESEARCH.md exists but is not echoed in the source.

**Fix:** Add an inline comment on the `v2ToV3` stage:
```swift
// Note: emails is added to an *already-persisted* PersonProfile row (the self-profile).
// SwiftData materializes [] for existing rows — confirmed by MigrationTests.testPersonProfileSurvivesV2ToV3Migration.
// Any future [String] addition to an existing model must be similarly tested.
static let v2ToV3 = MigrationStage.lightweight(...)
```

---

### IN-02: PeopleDirectoryView loads people synchronously on appear — no async guard for large directories

**File:** `macos/Views/PeopleDirectoryView.swift:262-266`
**Issue:** `loadPeople()` calls `service.directoryPeople()` — a synchronous
SwiftData fetch on the main context — and sets `isLoading = false` before the
fetch. Since this is a Phase 2 feature with small expected dataset sizes, there
is no practical issue today. However, the `isLoading` flag is set to `false`
before calling `directoryPeople()`, which means the loading skeleton is never
actually displayed (it shows for zero frames). If the method is made async in the
future, the current structure would be incorrect.

**Fix:** Set `isLoading = false` after the fetch:
```swift
private func loadPeople() {
    people = service.directoryPeople()
    isLoading = false
    loadError = nil
}
```

---

### IN-03: Windows PersonEditModal does not preserve existing emails when editing

**File:** `windows/src/pages/PersonEditModal.tsx:76`
**Issue:** In edit mode, `handleSave()` passes `emails: person.emails` — meaning
whatever email array was on the person object at modal open time is preserved
unchanged. This is correct behaviour. However, the modal has no UI to view or
edit emails (e-mails arrive from Graph seed, not from manual entry). If a user
manually edits a seeded person and saves, their email is preserved. If they edit
a person created via the manual "Persoon toevoegen" path, `emails: []` is preserved.
This matches macOS (`PersonEditView` also has no emails text field). Consistent
but worth noting: there is currently no way for a user to manually add an email
address to a person, meaning dedup will never match a manually-added person by
email unless they were originally seeded. Post-Phase-3/4, when email-based
attribution matters, this will become a blocker.

**Fix (deferred):** No action needed in Phase 2 — within scope. Flag for Phase 3
when `{{PEOPLE_CONTEXT}}` injection begins: add an emails field to both edit forms.

---

### IN-04: SeedReviewSheet (macOS) header uses candidates.count, not checkedCount — misleading after unchecking

**File:** `macos/Views/SeedReviewSheet.swift:63`
**Issue:** The subtitle reads:
```swift
Text("\(candidates.count) deelnemers uit je agenda staan nog niet in je directory.")
```
This count is fixed at the initial candidate list size. If the user unchecks some
rows and then reads the text, the header still says e.g. "3 deelnemers" even
though only 1 is selected. The primary button correctly reflects the checked count.
The Windows implementation has the same pattern (`candidates.length`). This is a
minor UX inconsistency, not a correctness issue.

**Fix:** Not required for correctness. If desired: keep the static header (it
describes what was found) and rely on the button label for the current selection
count — which is already done correctly.

---

_Reviewed: 2026-06-07T15:56:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
