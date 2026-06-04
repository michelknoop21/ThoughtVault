# Phase 1: Self-Profile Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 01-self-profile-foundation
**Areas discussed:** SwiftData migration strategy, PersonProfile model shape & forward-compat, Onboarding step placement & skip UX, Settings editor + self-singleton

---

## SwiftData migration strategy (A-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit VersionedSchema v1→v2 | SchemaV1 (TranscriptRecord only) → SchemaV2 (+PersonProfile), lightweight MigrationStage, version anchor + testable upgrade path | ✓ |
| Automatic migration, no plan | Add PersonProfile.self to container; SwiftData auto-migrates additively. Less code, no version anchor | |

**User's choice:** Explicit VersionedSchema v1→v2
**Notes:** Context7/SwiftData confirms adding a new @Model is purely additive and within lightweight migration capability. Explicit versioning matches A-04 wording and sets a clean base for Phase 2-4 schema growth.

---

## PersonProfile model shape & forward-compat

| Option | Description | Selected |
|--------|-------------|----------|
| Full shared @Model now, isSelf flag | Model Phase 2 directory reuses; full field set; Phase 1 writes only isSelf=true record | ✓ |
| Minimal self-only model now | Smaller now, generalize in Phase 2 — forces a second migration | |

**User's choice:** Full shared @Model now, isSelf flag
**Notes:** Avoids a second schema migration in Phase 2; matches REQUIREMENTS A-02 ("PersonProfile, isSelf-vlag").

---

## Onboarding step placement & skip UX

| Option | Description | Selected |
|--------|-------------|----------|
| Before final 'klaar' step, explicit Overslaan | After permission steps; macOS between schermopname & klaar, Windows before final; all fields optional + skip button | ✓ |
| Right after welcome | Before permissions — strong intro but interrupts permission momentum | |
| Separate first-run sheet after onboarding | Decoupled, but adds a second first-run surface | |

**User's choice:** Before final 'klaar' step, explicit Overslaan
**Notes:** User is already committed by then; doesn't break the permission flow.

---

## Settings editor + self-singleton

| Option | Description | Selected |
|--------|-------------|----------|
| New dedicated section + enforced singleton | New 'Profiel'/'Over jou' section both platforms; one isSelf=true profile upserted; empty/absent allowed | ✓ |
| Fold into existing profiles settings area | Reuse notule-Profile surface — high collision/confusion risk | |

**User's choice:** New dedicated section + enforced singleton
**Notes:** Kept separate from the notule-style Profile type to avoid the naming collision.

---

## Claude's Discretion

- Exact SwiftUI/Tailwind layout of the onboarding step and Settings editor (within existing design tokens).
- Windows storage mechanism for PersonProfile (zustand persist / localStorage vs dedicated store).
- NL Localizable.strings / Windows i18n keys and exact copy.
- aliases/meetingTypes input style (comma-separated vs chips).

## Deferred Ideas

- People directory (colleagues/externals, Microsoft Graph attendee seed) — Phase 2 (B-01..B-03).
- {{PEOPLE_CONTEXT}} injection in local + cloud notule generation — Phase 3 (C-01..C-04).
- Name→person mapping + editable owner assignment, TranscriptRecord attribution fields — Phase 4 (D-01..D-04).
