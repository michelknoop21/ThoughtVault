---
phase: 02-people-directory
fixed_at: 2026-06-07T16:06:30Z
review_path: .planning/phases/02-people-directory/02-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-06-07T16:06:30Z
**Source review:** `.planning/phases/02-people-directory/02-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (2 Critical, 5 Warning)
- Fixed: 7
- Skipped: 0

## Fixed Issues

### CR-01: SwiftData save errors silently discarded

**Files modified:** `macos/Services/PersonDirectoryService.swift`, `macos/Views/PersonEditView.swift`, `macos/Views/SeedReviewSheet.swift`
**Commit:** `5e1dab8`
**Applied fix:** Changed `add()` and `update()` signatures from non-throwing to `throws`, replacing `try? context.save()` with `try context.save()`. Updated `PersonEditView.savePerson()` to wrap both paths in a `do/catch` that sets `saveError` (already wired to the UI). Added `@State private var saveError: String? = nil` and error display UI to `SeedReviewSheet`, then wrapped `saveSelected()` loop in `do/catch` that surfaces the error and keeps the sheet open for retry.

---

### CR-02: Windows dedup misses self-profile emails

**Files modified:** `windows/src/stores/peopleDirectoryStore.ts`
**Commit:** `b0d824a`
**Applied fix:** Added `import { usePersonProfileStore } from "./personProfileStore"` and reads `usePersonProfileStore.getState().profile` inside `newSeedCandidates()`. Iterates `selfProfile?.emails ?? []` and adds each (lowercased) to `knownEmails` before the attendee filter, matching the macOS `fetchSelfProfile()?.emails` path (D-10 parity).

---

### WR-01: Transient PersonDirectoryService instances in views

**Files modified:** `macos/Services/PersonDirectoryService.swift`, `macos/Views/PeopleDirectoryView.swift`, `macos/Views/PersonEditView.swift`, `macos/Views/SeedReviewSheet.swift`, `macos/App/ContentView.swift`
**Commit:** `9197d58`
**Applied fix:** Added `static let shared = PersonDirectoryService()` to `PersonDirectoryService`, matching the `LocalTranscriptStore.shared` pattern. Changed `PeopleDirectoryView` from `@State private var service = PersonDirectoryService()` to `private let service = PersonDirectoryService.shared`. Updated `PersonEditView.savePerson()`, `SeedReviewSheet.saveSelected()`, and `ContentView`'s `onChange` seed handler to use `.shared` instead of constructing transient instances.

Note: `@Observable` environment injection was considered but not used — `PersonDirectoryService` is `@MainActor` only (not `@Observable`), making `static let shared` the simpler and consistent choice.

---

### WR-02: macOS dedup allows duplicate attendees from one meeting

**Files modified:** `macos/Services/PersonDirectoryService.swift`
**Commit:** `56fccd8`
**Applied fix:** Added `var seen = Set<String>()` before the return chain in `newSeedCandidates(from:selfEmail:)` and appended `.filter { seen.insert($0).inserted }` after the existing filter, ensuring each email appears at most once in the result.

---

### WR-03: Windows seed name derivation degraded vs macOS

**Files modified:** `windows/src/pages/SeedReviewSheet.tsx`
**Commit:** `973a858`
**Applied fix:** Replaced single-word capitalize (`charAt(0).toUpperCase() + slice(1)`) with `.split(/[._-]/).map((s) => s.charAt(0).toUpperCase() + s.slice(1)).join(" ")`, matching the macOS `components(separatedBy: CharacterSet(charactersIn: "._-")).map { $0.capitalized }.joined(separator: " ")` logic. `j.smith@co.com` now produces "J Smith" on both platforms.

---

### WR-04: AppTab keyboard shortcut ordering non-sequential

**Files modified:** `macos/App/ContentView.swift`
**Commit:** `eaf1085`
**Applied fix:** Reordered shortcuts: `settings="5"`, `people="6"`, `admin="8"`. Regular users (no admin tab) now see a contiguous 1–6 sequence. Admin moves to "8" (rarely used; "7" is an intentional gap ahead of admin).

---

### WR-05: Windows Graph endpoint queries only default calendar

**Files modified:** `windows/src/services/microsoftGraph.ts`
**Commit:** `c72282a`
**Applied fix:** Changed URL from `${GRAPH_BASE}/me/calendar/calendarView?${params}` to `${GRAPH_BASE}/me/calendarView?${params}`, matching the macOS endpoint. `/me/calendarView` aggregates all calendars including shared Exchange calendars; `/me/calendar/calendarView` was restricted to the default calendar only.

---

## Build & Test Results

**macOS build:** `** BUILD SUCCEEDED **` (CODE_SIGNING_ALLOWED=NO, xcodebuild Debug)

**Windows tests:** `2 Test Files | 4 passed` — `src/stores/__tests__/peopleDirectoryStore.test.ts` all green. Tests run against main repo (node_modules not in worktree); CR-02 change is additive to `newSeedCandidates` and doesn't affect existing test assertions (test 4 seeds no self-profile, so `selfProfile?.emails ?? []` evaluates to `[]`).

---

_Fixed: 2026-06-07T16:06:30Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
