# Project Research Summary

**Project:** ThoughtVault — People & Attribution (v1.1)
**Domain:** Cross-platform meeting-notes app; on-device people-context + action-item attribution
**Researched:** 2026-06-04
**Confidence:** HIGH

## Executive Summary

People & Attribution is a purely additive milestone: no existing flows are replaced, no new infrastructure is introduced. The research confirms that the entire feature set — self-profiling, a local directory, context injection into the notule prompt, and post-generation editable attribution — can be built on the existing SwiftData / Zustand stack with exactly one new npm dependency (`fuse.js`) and zero new Rust crates or SPM packages. The four feature categories (A→B→C→D) form a strict linear dependency chain that must be built in that order; no parallelism is safe because each phase's deliverables are preconditions for the next.

The recommended approach is model-first: define `PersonProfile` as a single `@Model` with an `isSelf` flag (covering both the self-profile singleton and directory entries), set up a versioned `SchemaMigrationPlan` before any model changes land, and establish the `PersonProfile` / `PeopleDirectory` naming discipline as a hard constraint on day one. Context injection follows a proven placeholder-substitution pattern already in `LLMService.buildNotuleUserContent`, extended with a `{{PEOPLE_CONTEXT}}` branch on both the local LLM path and the cloud n8n webhook payload. Attribution mapping runs client-side after generation — keeping all personal directory data on-device — and feeds a shared `AttributionEditorView` component that both notule viewers (`NotuleResultView` and `TranscriptDetailView`) embed identically.

The top risks are: (1) silent SwiftData data loss if schema migration is skipped or under-tested — prevention is the only recovery; (2) n8n payload contract breakage because `people_context` must land in four separate backend locations simultaneously, including the separate regenerate path which is easy to forget; (3) prompt injection through user-controlled directory fields — sanitisation is mandatory before Phase C ships on the cloud path; (4) the two-viewer divergence (FND-008) causing attribution edits made in `NotuleResultView` to be invisible in `TranscriptDetailView` — requires a single `TranscriptRecord`-backed source of truth from the start of Phase D.

---

## Key Findings

### Recommended Stack

The existing stack handles everything. macOS uses SwiftData — extend `LocalTranscriptStore`'s `ModelContainer` to include `PersonProfile.self`. The unified `PersonProfile @Model` carries an `isSelf: Bool` flag so a single model type covers both the self-profile singleton and all directory entries; this avoids a redundant `SelfProfile`/`DirectoryPerson` split. Windows uses Zustand with a custom `tauri-plugin-store`-backed `StateStorage` adapter (pattern verified via Context7); `personProfileStore.ts` and `peopleDirectoryStore.ts` follow the same structure as the existing `settingsStore.ts`. Attribution overrides live on `TranscriptRecord` as `attributionsData: Data?` (macOS) and as `Transcript.attributions?` in `transcriptsStore.ts` (Windows).

**Core technologies:**
- `SwiftData @Model` (macOS): unified `PersonProfile` model + additive `TranscriptRecord` extension — already in the project, auto-migrates additive-only changes
- `Zustand persist` + `tauri-plugin-store` (Windows): custom `StateStorage` adapter to named JSON files — already installed, consistent with `settingsStore.ts` pattern
- `NLTagger` / `.personalName` (macOS): OS-built-in name extraction from notule HTML — zero new dependency
- `fuse.js ^7.4.0` (Windows): fuzzy name matching over `PersonDirectoryEntry[]` in-memory — only new npm dependency
- `SchemaMigrationPlan` (macOS): versioned schema wrapping `TranscriptRecord` before any field is added — mandatory pre-work, Phase A

**Do not add:** SQLite/rusqlite, CloudKit, a second `ModelContainer`, `@Relationship` between `TranscriptRecord` and `PersonProfile`, `NSLinguisticTagger` (deprecated), any external Swift fuzzy-match SPM package, `ObservableObject`/Combine.

### Expected Features

**Must have (table stakes — all four categories):**
- A: `PersonProfile` model (macOS SwiftData + Windows Zustand store), skippable onboarding step, Settings edit screen
- B: Directory CRUD UI (add/edit/delete), aliases per entry, intern/extern flag with `unknown` as a valid third state
- C: `{{PEOPLE_CONTEXT}}` injected into both local `LLMService` path and cloud n8n webhook payload; self-profile + meeting attendees only (not full directory) per prompt
- D: Action-item owner chip (tappable), people-picker backed by directory, attribution persisted to `TranscriptRecord`, consistent UI in both notule viewers

**Should have (high-value differentiators in v1.1):**
- B: Calendar attendee seed — calendar data is already fetched but discarded; surface a "voeg deelnemers toe?" prompt after notule generation
- B: Organisation-based intern/extern inference — if attendee org matches `PersonProfile.organisation`, pre-fill as internal (pending user confirmation)
- C: Prompt alias serialisation — "Jan Bakker, ook bekend als: Jan, JB" dramatically improves LLM name resolution
- D: Intern/extern indicator on owner chip — low-cost, high-context addition

**Defer to v1.x (after validation):**
- Fuzzy duplicate detection in directory (merge prompt)
- Visual confidence indicator on auto-assigned owners (requires structured LLM output to be stable first)
- Bulk "accept all attributions" confirm action

**Defer to v2+:**
- Meeting-history association in directory ("appeared in N meetings")
- Attribution learning loop (remember owner patterns across meetings)
- External task system sync (Jira/Asana)
- Org-wide profile sync

**Hard anti-features (never in this milestone):**
- Photo/avatar upload — no product value for attribution
- Mandatory self-profile before first use — blocks power users
- Auto-create person from every transcript mention — generates noise
- Directory cloud sync — breaks local-first; requires privacy review

### Architecture Approach

Everything is additive. Three new subsystems (`PersonProfile` store, `PeopleDirectory` service, `AttributionMapper`) attach to four modified integration points (`LLMService.buildNotuleUserContent`, `RecordingViewModel` local + regenerate paths, `TranscribeTextRequest` backend model, and the n8n workflow). The `PeopleContextBuilder` is a pure function (or simple struct) that formats the `{{PEOPLE_CONTEXT}}` block from directory state — no actor, no async, no network. `AttributionMapper` runs post-generation on the completed notule HTML, always client-side, producing `[AttributionEntry]` persisted to `TranscriptRecord.attributionsData`. The backend never returns structured attribution data; this keeps personal directory data local.

**Major components:**
1. `PersonProfile @Model` + `PersonDirectoryService actor` (macOS) / `personProfileStore` + `peopleDirectoryStore` (Windows) — on-device storage, no network methods
2. `PeopleContextBuilder` (both platforms) — formats `{{PEOPLE_CONTEXT}}` plain-text block; bounded to ~30–50 entries (meeting attendees first, then fallback to full directory)
3. `AttributionMapper actor` (macOS) / equivalent TypeScript service (Windows) — post-generation HTML scan; strict-then-permissive matching (alias exact > name exact > Jaro-Winkler ≥ 0.85, min 4-char names only)
4. `AttributionEditorView` (SwiftUI) / `AttributionEditor.tsx` (Windows) — shared component injected identically into both notule viewers; reads/writes `TranscriptRecord.attributionsData` as single source of truth
5. `SelfProfileOnboardingStep` + `PeopleDirectoryView` — new UI surfaces (skippable onboarding, Settings CRUD)

**Key patterns:**
- Additive placeholder substitution: `{{PEOPLE_CONTEXT}}` follows existing `{{TRANSCRIPTION}}` / `{{OUTPUT_TEMPLATE}}` convention; always route through `buildNotuleUserContent`, never concatenate at call sites
- Client-side post-processing: `AttributionMapper` runs once after the full HTML is returned, never inside a streaming callback
- Denormalized display name in `AttributionEntry`: stores both `personId` and `personDisplayName` so old transcripts remain readable if the directory entry is deleted

### Critical Pitfalls

1. **SwiftData schema migration crash wiping user data** — Before adding any field to `TranscriptRecord`, define `VersionedSchema` V1/V2 + `SchemaMigrationPlan` with `.lightweight` migration + pass `migrationPlan:` to `ModelContainer`. Must be done in Phase A, before any model change ships. Test on a real device with existing data — the simulator never hits this.

2. **n8n payload contract breakage on cloud path** — `people_context` must land in four backend locations simultaneously (`transcription_service.py`, `transcription.py` ×2, `transcripts.py`) plus the separate `regenerateNotule` endpoint (`APIService.swift:656`). Do a spike at the start of Phase C: enumerate all four locations, change them in a single commit, test the webhook end-to-end. The regenerate path is the easiest to forget and has the highest probability of being missed.

3. **Prompt injection via user-controlled directory fields** — `PersonProfile.name`, `role`, and `aliases` are user-editable and calendar-seeded. Sanitise (strip newlines + `{{...}}` sequences) before substitution in Phase C. Wrap the block in `<people_context>...</people_context>` XML delimiters and add an explicit system-prompt guard. Mandatory before the cloud path goes live.

4. **`Profile` / `PersonProfile` naming collision corrupting notule-template routing** — `Profile` is a live type in `Models.swift:219-302`; it is notule style, not a person. New type is always `PersonProfile`; directory is always `PeopleDirectory`. Add a collision-warning comment to `Models.swift` in Phase A, never name any new variable/UserDefaults key with the word "profile" outside the existing type, and grep for violations before any Phase A PR merges.

5. **Two-viewer attribution divergence (FND-008)** — `NotuleResultView` wraps `TranscriptTask` (session-scoped); `TranscriptDetailView` wraps `TranscriptRecord` (persisted). Attribution must be written to `TranscriptRecord` immediately on first assignment — not stored in `TranscriptTask`. Phase D must use a shared `AttributionEditorView` component injected identically into both viewers. Verification: assign an owner in `NotuleResultView`, dismiss the session, reopen from history — the assignment must be present in `TranscriptDetailView`.

---

## Implications for Roadmap

The build order is fixed by hard dependencies. A→B→C→D is not a preference; it is a constraint. `PersonProfile` is the foundation that B, C, and D all require. Directory population makes C useful and D accurate. Context injection produces the LLM output that D's `AttributionMapper` needs to work with realistic data. Phase D has the highest uncertainty and the most integration surface; it belongs last.

### Phase 1: Self-Profile Foundation (Feature Category A)

**Rationale:** `PersonProfile @Model` is the shared data primitive for every subsequent phase. Building it first, with the correct `isSelf` unified design and the versioned `SchemaMigrationPlan` already in place, avoids rework in Phases 2–4. The naming discipline (no `Profile` collision) must be established here before any other code refers to the new concept.

**Delivers:** `PersonProfile @Model` + `PersonDirectoryService`, versioned `SchemaMigrationPlan`, skippable onboarding step `SelfProfileOnboardingStep`, Settings > "Mijn profiel" edit screen; Windows `personProfileStore.ts` + equivalent UI; stable UUID strategy for cross-platform person IDs.

**Addresses:** A-01, A-02, A-03

**Avoids:** SwiftData migration crash (Pitfall 1 — migration plan in place before any field lands), Profile/PersonProfile naming collision (Pitfall 3), cross-platform attribution inconsistency on person IDs (Pitfall 9)

**Gate:** Self-profile saved on-device, readable, editable, survives restart on both platforms. `ModelContainer` includes `PersonProfile.self`. Must verify on device with existing `TranscriptRecord` data, not just a clean simulator.

### Phase 2: People Directory (Feature Category B)

**Rationale:** Directory CRUD + calendar attendee seed populate the data source that Phase 3 injects and Phase 4 matches against. Intern/extern flag needs the `unknown` third state from day one — retrofitting later is a data migration. The `PersonProfile` model is reused directly for directory entries (`isSelf == false`), so Phase 1 is the only model dependency.

**Delivers:** `PeopleDirectoryView` (CRUD on both platforms), directory entries with `isSelf == false`, intern/extern/unknown tri-state flag, calendar attendee seed prompt (reads existing `CalendarEvent` data — no new Graph API scope), org-matching intern/extern inference (suggestion, pending user confirmation).

**Addresses:** B-01, B-02, B-03

**Avoids:** Internal/external misclassification (Pitfall 6 — `unknown` is first-class, never auto-committed), local-only scope creep (Pitfall 10 — `PersonDirectoryService` has no `URLSession` references), calendar attendee seed must use only data already in `CalendarEvent` struct.

**Gate:** Add/edit/delete a person entry; seed from a calendar event; `unknown` classification is the default for seeded entries; survives restart. Grep confirms `PersonDirectoryService` has no network methods.

### Phase 3: Context Injection (Feature Category C) — SPIKE REQUIRED

**Rationale:** Injecting `{{PEOPLE_CONTEXT}}` into both LLM paths converts the directory from a UI-only feature into functional improvement in notule quality. This phase has the widest integration surface (local Swift + FastAPI backend + n8n workflow + Windows API client) and must be preceded by a spike to enumerate all four backend payload locations and inspect the n8n workflow node structure before touching either.

**Delivers:** `PeopleContextBuilder` (pure function, both platforms), `buildNotuleUserContent` extended with `peopleContext: String?`, `TranscribeTextRequest` extended with `people_context: Optional[str] = None`, n8n workflow `Iq3AAf8Vk8eQ9dcZ` updated with a Set/Code node that splices people-context into the prompt, Windows `api.ts` updated, `regenerateNotule` path updated. All changes backward-compatible (optional fields / no-op when absent).

**Addresses:** C-01, C-02

**Avoids:** Prompt injection (Pitfall 4 — sanitisation + `<people_context>` XML delimiter wrapper mandatory before cloud path ships), n8n payload breakage (Pitfall 8 — spike enumerates all four backend locations; regenerate path explicitly included), LLM hallucination (Pitfall 2 — bounded context: meeting attendees + self-profile only, not full directory; prompt instructs LLM to use exact names from the list)

**Gate:** Notule generated locally shows people-context influence; cloud notule receives `people_context` in n8n execution; old profiles without the `{{PEOPLE_CONTEXT}}` placeholder still work (fallback prepend). `regenerateNotule` endpoint verified to include `people_context`.

**Spike tasks before planning:**
- Inspect n8n workflow `Iq3AAf8Vk8eQ9dcZ` in the n8n UI to map node positions before writing code
- Enumerate all four backend locations that build the webhook payload dict
- Confirm whether the `handleiding` Claude-proxy path (DEC-057) routes through the same or a divergent payload-building code path

### Phase 4: Attribution Mapping + Editable Owner UI (Feature Category D) — SPIKE REQUIRED

**Rationale:** This phase has the highest uncertainty because `AttributionMapper`'s correctness depends on the actual HTML structure of real notule outputs, which varies per Profile template. The FND-008 two-viewer divergence must be resolved here with a shared component and `TranscriptRecord` as the single source of truth, established architecturally before any UI is built.

**Delivers:** `AttributionMapper actor` (post-generation HTML scan), `AttributionEntry Codable` struct, `TranscriptRecord.attributionsData: Data?` (additive optional — lightweight migration covered by Phase 1's plan), `AttributionEditorView` (SwiftUI, injected into both `NotuleResultView` and `TranscriptDetailView`), Windows `AttributionEditor.tsx`, cross-platform attribution JSON schema documented in `.planning/` before Windows implementation starts.

**Addresses:** D-01, D-02, D-03

**Avoids:** Two-viewer divergence (Pitfall 7 — shared `AttributionEditorView` + `TranscriptRecord` as sole source; `TranscriptTask` never used for attribution storage), alias fuzzy-match false positives (Pitfall 5 — strict-then-permissive: alias exact > name exact > Jaro-Winkler ≥ 0.85, min 4-char names, emit "unresolved" below threshold), cross-platform attribution inconsistency (Pitfall 9 — shared JSON schema defined before Windows starts)

**Gate:** Owner shown per action point in both viewers; editable; persisted; survives app restart; assigning owner in `NotuleResultView` and reopening from history in `TranscriptDetailView` shows the same owner. Windows parity confirmed.

**Spike tasks before planning:**
- Inspect 3–5 real notule HTML outputs to confirm action-point tag/class structure before writing `AttributionMapper`
- Verify FND-008 current state: is the two-viewer divergence partially or fully open after Parity & Polish Phase 1?

### Phase Ordering Rationale

- Phase 1 first: `PersonProfile @Model` and `SchemaMigrationPlan` are foundational prerequisites. Doing this last requires painful rework.
- Phase 2 before Phase 3: testing context injection with a nearly empty people block gives a false quality signal. Directory population makes Phase 3 meaningful.
- Phase 3 before Phase 4: `AttributionMapper` needs realistic LLM output generated with people-context. Testing it on context-free prompts produces misleading accuracy signals.
- Phase 4 last: highest unknowns (HTML structure, two-viewer integration, Windows parity). Partial deferral is safe — Phase C already improves notule quality independently.

### Research Flags

Phases requiring a spike during planning:
- **Phase 3:** Inspect n8n workflow `Iq3AAf8Vk8eQ9dcZ` node structure + enumerate all four backend payload locations. Without this the developer will miss at least one payload site and the `regenerateNotule` path.
- **Phase 4:** Inspect real notule HTML outputs (3–5 samples) to confirm action-point tag/class patterns before writing `AttributionMapper`. Without this the matcher will be written against an assumed structure.

Phases with well-documented patterns (skip research-phase):
- **Phase 1:** SwiftData additive model + versioned migration is a standard pattern, fully verified. Implementation steps are specified in STACK.md and PITFALLS.md.
- **Phase 2:** Directory CRUD + Zustand store patterns are standard. Calendar attendee seed is a minor extension of an already-understood code path.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All choices verified via Context7 + official Apple docs + npm. Zero new infrastructure needed. SwiftData migration behaviour confirmed. |
| Features | MEDIUM-HIGH | Real-tool observations of comparable tools (Fireflies, Fellow, Otter, Notion). Single-user-per-install model has no exact comparator; some decisions are reasoned. |
| Architecture | HIGH | Based on direct code inspection of all integration points. All injection points, model locations, and call sites confirmed. |
| Pitfalls | HIGH | Derived from direct codebase analysis. SwiftData migration risk, four-location backend payload, and FND-008 are confirmed in existing code. |

**Overall confidence:** HIGH

### Gaps to Address

- **n8n workflow internal structure:** Workflow `Iq3AAf8Vk8eQ9dcZ` was not directly inspected. Phase 3 spike is mandatory before any n8n changes.
- **Real notule HTML action-point structure:** CSS classes and tag structure for action-point lists not confirmed across all Profile templates. Phase 4 spike is mandatory.
- **`handleiding` Claude-proxy path (DEC-057):** Whether this path builds the webhook payload via the same or a divergent code path is unconfirmed. Include in Phase 3 spike.
- **`attributionsData` vs `attributionJson` field naming:** ARCHITECTURE.md uses `attributionsData: Data?`; STACK.md uses `attributionJson: String?`. Settle before Phase 4. Recommendation: `attributionsData: Data?` with a computed `attributions: [AttributionEntry]` property.
- **FND-008 current state:** Confirm whether the two-viewer divergence was partially addressed in Parity & Polish Phase 1 before Phase 4 planning begins.

---

## Sources

### Primary (HIGH confidence)
- Apple SwiftData documentation (via Context7) — `@Model`, `ModelContainer`, automatic migration, `VersionedSchema`, `SchemaMigrationPlan`
- `NLTagger` / `.nameType` / `.personalName` Apple docs — name extraction, macOS 10.14+
- `tauri-plugin-store` v2 JavaScript API (Context7 `/tauri-apps/plugins-workspace`) — named JSON file persistence
- Zustand `persist` + custom `StateStorage` (Context7 `/pmndrs/zustand`) — Tauri-compatible storage adapter pattern
- Direct codebase inspection: `LLMService.swift:53-76`, `RecordingViewModel.swift:646-753`, `TranscriptRecord.swift`, `LocalTranscriptStore.swift`, `MicrosoftGraphService.swift:260-324`, `CalendarService.swift`, `transcription.py:450-468`, `APIService.swift:655-663`, `windows/src/stores/`, `windows/src/types.ts`
- `.planning/codebase/CONCERNS.md`, `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md` (2026-06-03)
- `docs/DECISIONS.md` DEC-057 (n8n Claude proxy), DEC-050 (Windows Credential Manager), DEC-042 (Swift concurrency patterns)

### Secondary (MEDIUM confidence)
- Gladia: "From transcript to actionable notes: Building effective LLM pipelines" — participant-list injection pattern
- Jiminny, Otter.ai, Fireflies.ai — internal/external domain detection, action-item owner correction UX
- Fellow.ai, AFFiNE — assignee picker UX patterns for meeting action items
- Eleken: User onboarding best practices — skippable gates, progressive profiling

### Tertiary (informational)
- Fuse.js v7.4.0 (npm, June 2026) — fuzzy search, threshold configuration

---
*Research completed: 2026-06-04*
*Ready for roadmap: yes*
