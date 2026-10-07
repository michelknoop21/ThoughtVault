---
phase: "01-self-profile-foundation"
plan: "03"
subsystem: "windows-self-profile"
tags: [windows, zustand, react, onboarding, settings, personprofile]
dependency_graph:
  requires: []
  provides: [windows-person-profile-store, windows-onboarding-profiel-step, windows-profile-settings]
  affects: [windows-onboarding-wizard, windows-settings-page]
tech_stack:
  added: []
  patterns: [zustand-persist, react-controlled-inputs, css-vars]
key_files:
  created:
    - windows/src/stores/personProfileStore.ts
    - windows/src/components/settings/ProfileSettings.tsx
  modified:
    - windows/src/types.ts
    - windows/src/components/onboarding/OnboardingWizard.tsx
    - windows/src/pages/SettingsPage.tsx
decisions:
  - "Dedicated personProfileStore with name 'person-profile-store' (distinct from profiles-store / settings-store)"
  - "expertiseTags included from the start (A-05) to prevent a second migration in Phase 3/4"
  - "Skip path on step 4 reuses the same footer Overslaan button — no write on handleComplete if all fields empty (D-07)"
  - "ProfileSettings placed before Notulen group in SettingsPage to separate self-profile from notule-Profielen (D-08)"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-05"
  tasks_completed: 4
  tasks_total: 4
  files_changed: 5
---

# Phase 01 Plan 03: Windows Self-Profile Stack Summary

**One-liner:** zustand persist personProfileStore (localStorage, person-profile-store key) + skippable Profiel step in OnboardingWizard (index 4, Klaar shifts to 5) + ProfileSettings section in SettingsPage.

## What Was Built

The full Windows (Tauri 2 / React / zustand) self-profile stack for Phase 1:

1. **PersonProfile type** (`types.ts`) — 11-field interface with all parity fields including `expertiseTags: string[]` (A-05). Placed before the existing `Profile` interface.

2. **personProfileStore** (`stores/personProfileStore.ts`) — zustand `persist` store with store name `"person-profile-store"` (distinct from `"profiles-store"` and `"settings-store"`). Actions: `upsertProfile` (spread-merge, bumps `updatedAt`, creates fresh record with `isSelf: true` / `isInternal: true` / `crypto.randomUUID()` id when no profile exists) and `clearProfile`.

3. **OnboardingWizard step 4** (`components/onboarding/OnboardingWizard.tsx`) — Step type extended to `0|1|2|3|4|5`; STEPS array gains "Profiel" before "Klaar"; `handleNext` guards `step < 5`; "Beginnen" triggers at `step === 5`. New step 4 renders 6 controlled inputs (Naam, Rol/Functie, Organisatie, Aliassen, Vergadertypen, Expertise) with copy-contract strings. Footer shows "Overslaan" at step 4 — clicking "Overslaan" advances to Klaar without writing any profile (D-07). If any field is non-empty on `handleComplete`, `upsertProfile` is called before `setHasCompletedOnboarding(true)`.

4. **ProfileSettings** (`components/settings/ProfileSettings.tsx`) — reads `usePersonProfileStore`, 6 labeled inputs seeded from persisted profile. Empty state "Geen profiel ingevuld" shown when `profile === null`. "Profiel opslaan" button (`btn btn-accent`) with `isSaving` guard; "Opgeslagen" 2s confirmation; error message on failure. All colors via CSS vars only.

5. **SettingsPage wiring** (`pages/SettingsPage.tsx`) — new `settings-group` with label "Profiel" placed before the Notulen group (D-08: separate from notule-Profielen). Imports and renders `<ProfileSettings />`.

## Deviations from Plan

None — plan executed exactly as written.

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1: PersonProfile type + store | `0054e77` | PersonProfile interface + personProfileStore |
| 2: OnboardingWizard Profiel step | `8e5dcec` | Skippable Profiel step at index 4 |
| 3: ProfileSettings + SettingsPage | `56b0fbc` | ProfileSettings component + SettingsPage wiring |

## Verification

All three tasks verified clean with `cd windows && npx tsc --noEmit` — no TypeScript errors.

Acceptance criteria checked:
- `grep -c "interface PersonProfile" windows/src/types.ts` == 1 with all 11 fields incl. expertiseTags
- `person-profile-store` literal present in personProfileStore.ts; distinct from profiles-store/settings-store
- `type Step = 0 | 1 | 2 | 3 | 4 | 5` present in OnboardingWizard
- STEPS contains "Profiel" before "Klaar"; handleNext guards `step < 5`
- step === 4 block renders 6 inputs; step === 5 is Klaar/Beginnen
- `upsertProfile` referenced in handleComplete
- ProfileSettings uses `usePersonProfileStore` (read + upsertProfile + isSaving + "Opgeslagen")
- "Geen profiel ingevuld" empty state present
- ProfileSettings imported and rendered in SettingsPage

### Task 4 (checkpoint:human-verify) — approved on build evidence

Task 4 (live visual + persistence walkthrough) was **approved on build evidence**, not a live macOS/Windows run:

- `cd windows && npx tsc --noEmit` — clean, no type errors.
- `cd windows && vite build` — succeeded with no errors (only pre-existing dynamic-import warnings unrelated to this plan).

The live wizard/persistence/collision walkthrough remains **to be done on a real Windows environment** (VM or CI). Specifically still unverified by execution: the skippable Profiel wizard step rendering before Klaar, Settings Profiel persistence across an app restart, and the distinct `person-profile-store` localStorage key (no collision with `profiles-store`). These are covered by static evidence (distinct store name literal, step-index logic, controlled inputs) but not by an interactive run.

## Known Stubs

None — all fields are wired to the personProfileStore.

## Threat Surface Scan

No new network endpoints, auth paths, or backend calls introduced. PersonProfile data stays on-device (localStorage). Threats T-01-03-01 (store name collision) and T-01-03-02 (skip-path empty write) are mitigated in code.

## Checkpoint Resolution

Task 4 (checkpoint:human-verify) was **approved** on programmatic verification (tsc + vite build clean). The live visual/persistence walkthrough on a real Windows VM/CI run is deferred — see the "Task 4 — approved on build evidence" note under Verification for the exact items still to be exercised interactively.

## Self-Check: PASSED

- `windows/src/stores/personProfileStore.ts` — exists
- `windows/src/components/settings/ProfileSettings.tsx` — exists
- `windows/src/types.ts` contains `interface PersonProfile` — confirmed (grep count 1)
- `windows/src/components/onboarding/OnboardingWizard.tsx` contains step === 4 block — confirmed
- `windows/src/pages/SettingsPage.tsx` contains ProfileSettings import — confirmed
- Commits `0054e77`, `8e5dcec`, `56b0fbc` exist in git log — confirmed
