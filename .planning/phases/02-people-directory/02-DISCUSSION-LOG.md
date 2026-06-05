# Phase 2: People Directory - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 2-people-directory
**Areas discussed:** Intern/extern tri-state, Attendee dedup / email field, Directory UI placement, Agenda-seed trigger & flow

---

## Intern/extern tri-state

| Option | Description | Selected |
|--------|-------------|----------|
| isInternal: Bool? (nil=onbekend) | Change Bool → optional Bool. nil = onbekend, true = intern, false = extern. Additive/relaxing within SwiftData schema, minimal Windows change. | ✓ |
| New affiliation: String enum | Add affiliation field ('intern'/'extern'/'onbekend'), deprecate isInternal. More explicit but adds a field + migration of existing self-profile. | |

**User's choice:** isInternal: Bool? (nil=onbekend)
**Notes:** Goes into a combined SchemaV3 lightweight stage together with the emails field (see below).

---

## Attendee dedup / email field

| Option | Description | Selected |
|--------|-------------|----------|
| Add emails: [String], dedup by email → name | New emails array on PersonProfile. Match seeded attendee by email first, fall back to normalized name. Matches Graph data shape. | ✓ |
| Single email: String | One email per person. Simpler but multi-address person can still duplicate. | |
| Name-only dedup, no email field | No schema change; dedup on normalized name. Lightest but fragile. | |

**User's choice:** Add emails: [String], dedup by email → name
**Notes:** Purely additive field (precedent: aliases/meetingTypes/expertiseTags are [String]).

---

## Directory UI placement

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level sidebar item 'Mensen' | macOS sidebar entry + Windows Mensen page. First-class, discoverable. | ✓ |
| Section inside Settings | Under existing Settings/Profiel area. Less prominent. | |

**User's choice:** Top-level sidebar item 'Mensen'

---

## Agenda-seed trigger & flow

| Option | Description | Selected |
|--------|-------------|----------|
| Review sheet after recording stops | Per-person confirm sheet when a recording linked to an event with attendees finishes. Requires adding attendee plumbing to macOS CalendarEvent. | ✓ |
| Batch banner in directory | Stash unseen attendees; show banner in Mensen view for later review. Less interruptive but easier to forget. | |

**User's choice:** Review sheet after recording stops
**Notes:** macOS CalendarEvent currently drops Graph attendees ($select already requests them) — plumbing gap to close. Own user filtered out of seed list; default seeded affiliation = nil (onbekend).

## Claude's Discretion

- Exact list/form/review-sheet layout (within TS.* tokens / Tailwind+Fluent).
- List-vs-grid + search/filter within the directory (within "beheer" scope).
- NL Localizable.strings / Windows i18n keys + copy.
- chips vs comma-separated for aliases/expertiseTags (must match Phase 1 onboarding choice).
- Whether self-profile shows read-only atop the directory or is hidden.
- Name derivation from attendee email when no Graph display name.

## Deferred Ideas

- Seed from previously processed transcripts (B-03 "en/of") — agenda-seed is the delivered source.
- {{PEOPLE_CONTEXT}} injection — Phase 3 (C-01..C-05).
- Post-generation detection + editable owner assignment — Phase 4 (D-01..D-06).
- Learning loop enriching expertiseTags — Phase 4 (D-06).
- Confidence/source UI indicators — Phase 4 / later (D-05).
