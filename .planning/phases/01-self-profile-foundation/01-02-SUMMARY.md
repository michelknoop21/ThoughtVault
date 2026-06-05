---
phase: 01-self-profile-foundation
plan: "02"
subsystem: ui
tags: [swiftui, onboarding, settings, personprofile, localizable]
dependency_graph:
  requires:
    - macos/Models/PersonProfile.swift (Plan 01)
    - macos/Services/LocalTranscriptStore.swift (upsertSelfProfile + fetchSelfProfile, Plan 01)
  provides:
    - macos/Views/OnboardingView.swift (OnboardingStep.profiel + profielStep)
    - macos/Views/ProfileSettingsView.swift (Settings Profiel editor)
    - macos/Views/SettingsView.swift (ProfileSettingsView wired in)
    - macos/Resources/nl.lproj/Localizable.strings (onboarding + settings profiel keys)
    - macos/Resources/en.lproj/Localizable.strings (EN equivalents)
  affects:
    - Plan 01-03 (Windows — parallel, no macOS impact)
    - Phase 2+ (self-profile now editable via Settings for later use in context-injection)
tech_stack:
  added: []
  patterns:
    - ScrollView wrapping profielStep to allow field visibility with 6 text inputs
    - LabeledContent for form fields in Settings (matches SettingsView pattern)
    - Task.sleep(for: .seconds(2)) for auto-dismiss "Opgeslagen" confirmation
    - PrimaryButtonStyle on "Profiel opslaan" CTA (focal anchor per UI-SPEC)
key_files:
  created:
    - macos/Views/ProfileSettingsView.swift
  modified:
    - macos/Views/OnboardingView.swift
    - macos/Views/SettingsView.swift
    - macos/Resources/nl.lproj/Localizable.strings
    - macos/Resources/en.lproj/Localizable.strings
    - TranscriptStudio.xcodeproj/project.pbxproj
decisions:
  - "profielStep wrapped in ScrollView: 6 TextFields exceed onboarding window height; ScrollView prevents clipping while preserving VStack structure"
  - "simultaneousGesture(DragGesture) on profielStep ScrollView: prevents TabView from consuming scroll gestures on macOS"
  - "ProfileSettingsView placed above profielenSection (notule-profiles) in SettingsView to match D-08 separation requirement"
  - "LabeledContent for Settings fields: matches existing SettingsView TextField pattern (verbindingSection lines 108-118)"
  - "Empty state renders form fields inline (not behind a separate CTA): allows immediate editing without an extra tap"
metrics:
  duration: "18m"
  completed_date: "2026-06-05"
  tasks_completed: 2
  tasks_total: 3
  files_created: 1
  files_modified: 5
---

# Phase 01 Plan 02: macOS UI — Onboarding Self-Profile Step + Settings Profiel Editor

**One-liner:** Skippable `OnboardingStep.profiel` (6 fields, upserts PersonProfile when non-empty) between schermopname and klaar, plus `ProfileSettingsView` (load/edit/save singleton, empty-state, saved-confirmation, error-state) wired into SettingsView — all NL strings in Localizable.strings, TS.Spacing/Font/Radius tokens throughout.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Insert skippable self-profile onboarding step | fb4e494 | macos/Views/OnboardingView.swift, nl.lproj/Localizable.strings, en.lproj/Localizable.strings |
| 2 | ProfileSettingsView + wire into SettingsView | 90b4df7 | macos/Views/ProfileSettingsView.swift (new), macos/Views/SettingsView.swift, project.pbxproj |

## What Was Built

**OnboardingView.swift** — `OnboardingStep.profiel = 5` inserted between `schermopname` (4) and `klaar` (now 6). Full per-case properties: title "Vertel iets over jezelf", icon "person.crop.circle", gradientColors `[gradientPurple, brandPrimary.opacity(0.4)]`, `isAvailableOnCurrentPlatform = true`. `profielStep` view: ScrollView wrapper (6 fields fitting within window), hero 120×120pt circle, title/description, 6 `TextField` rows (naam/rol/organisatie/aliassen/meetingTypes/expertise), "Overslaan" plain button. "Volgende" action in navigationFooter: checks anyFilled → `upsertSelfProfile(...)` with comma-split + trim on multi-value fields; skip → `advanceStep()` only (D-07 compliant). `@State` fields: `profielNaam`, `profielRol`, `profielOrganisatie`, `profielAliassen`, `profielMeetingTypes`, `profielExpertise`.

**ProfileSettingsView.swift** — `struct ProfileSettingsView: View` returns a `Section` (embedded in SettingsView's Form). `onAppear` loads via `fetchSelfProfile()` → fields. Empty state (all blank): "Geen profiel ingevuld" heading + body + inline form. Populated state: same fields editable. 6 `LabeledContent` rows with `.plain` TextFields. "Profiel opslaan" `PrimaryButtonStyle` button: `isSaving` disables it, on success sets `showSaved = true` → `Task.sleep(2s)` → dismiss; on failure shows "Kon profiel niet opslaan. Probeer het opnieuw." in `Color.statusError`. No hardcoded hex values; all tokens.

**SettingsView.swift** — `ProfileSettingsView()` inserted above `profielenSection` inside `Form { }`. Distinct from notule-Profielen (D-08).

**Localizable.strings (NL + EN)** — 22 new keys covering onboarding step (title, description, skip, 6 field labels + 3 placeholders) and Settings section (header, subtitle, save CTA, saved, empty heading/body, error).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] ScrollView wrapper for profielStep**
- **Found during:** Task 1 — analysis of 6 fields in a step with fixed window height
- **Issue:** 6 TextFields + hero + title/description would overflow OnboardingView without scrolling; this blocks usability
- **Fix:** Wrapped `profielStep` content in `ScrollView` with `simultaneousGesture(DragGesture())` to coexist with TabView swipe gesture
- **Files modified:** macos/Views/OnboardingView.swift
- **Commit:** fb4e494

## Known Stubs

None. All form fields are wired to `upsertSelfProfile`/`fetchSelfProfile`. No placeholder data, TODOs, or unfilled fields.

## Threat Flags

No new network endpoints, auth paths, or external data paths introduced. ProfileSettingsView reads/writes exclusively via `LocalTranscriptStore` (on-device SwiftData). Trust boundaries are consistent with plan threat model (T-01-02-01: skip path verified — "Overslaan" calls `advanceStep()` only, no upsert; T-01-02-02: local-only, no transmission).

## Self-Check: PASSED

- [x] macos/Views/ProfileSettingsView.swift exists (163 lines)
- [x] `struct ProfileSettingsView` present (1 occurrence)
- [x] `fetchSelfProfile` present (1 occurrence in ProfileSettingsView)
- [x] `upsertSelfProfile` present (1 occurrence in ProfileSettingsView + 1 in OnboardingView)
- [x] `isSaving` state present in ProfileSettingsView
- [x] "Geen profiel ingevuld" present in ProfileSettingsView
- [x] `ProfileSettingsView` wired in SettingsView (1 occurrence)
- [x] No hardcoded hex colors in ProfileSettingsView (0 `#` matches)
- [x] `case profiel = 5` in OnboardingStep enum
- [x] `case klaar = 6` in OnboardingStep enum
- [x] `profielStep` present 2+ times in OnboardingView (switch case + var)
- [x] "Overslaan" button in profielStep calls advanceStep() without upsert
- [x] NL Localizable.strings contains onboarding + settings profiel keys
- [x] Commit fb4e494 exists (Task 1)
- [x] Commit 90b4df7 exists (Task 2)
- [x] BUILD SUCCEEDED (both tasks)

## Pending

Task 3 (checkpoint:human-verify) — awaiting visual verification of onboarding flow and Settings persistence across restart.
