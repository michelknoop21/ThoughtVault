# Phase 2: People Directory - Research

**Researched:** 2026-06-05
**Domain:** SwiftData versioned migration · Microsoft Graph attendee decode · cross-platform local-first CRUD (macOS Swift 6 / Windows Tauri 2 + Zustand)
**Confidence:** HIGH (datamodel + Graph + patterns verified against codebase; migration rules verified against authoritative SwiftData sources)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** `PersonProfile.isInternal: Bool` → **`isInternal: Bool?`** (`nil` = onbekend, `true` = intern, `false` = extern). Agenda-geseede personen krijgen `nil`. Non-optional → optional = relaxing wijziging, lightweight-migratie.
- **D-02:** Voeg **`emails: [String]`** toe aan `PersonProfile` (precedent: `aliases`/`meetingTypes`/`expertiseTags` zijn al `[String]`). Calendar-attendees ZIJN e-mailadressen → dedup eerst op e-mail, dan op genormaliseerde naam. Puur additief.
- **D-03:** Eén gecombineerde **`SchemaV3`** lightweight-stage met `MigrationStage.lightweight(fromVersion: AppSchemaV2, toVersion: AppSchemaV3)` in `AppMigrationPlan`. Geen custom stage, geen data-wipe. Bestaand `isSelf == true`-record + alle `TranscriptRecord`s blijven intact.
- **Windows-equivalent:** `isInternal` nullable (`boolean | null`) + `emails: string[]` in PersonProfile-type + zustand-store. Schemaloze JSON (localStorage) → geen migratie.
- **D-04:** Top-level navigatie **"Mensen"** (first-class, niet in Settings). macOS: nieuwe `AppTab` in custom collapsible sidebar (DEC-029). Windows: nieuwe route in react-router.
- **D-05:** Gedeeld `PersonProfile`-model; directory-entries = `isSelf == false`. Zelf-profiel verschijnt NIET als bewerkbare directory-entry (verborgen of read-only bovenaan — planner's discretie).
- **D-06:** `expertiseTags` bewerkbaar per persoon — zelfde invoer-UX als zelf-profiel (chips-vs-comma moet gelijk zijn aan onboarding).
- **D-07:** Review-sheet ná opname-stop, per-persoon bevestigen "Voeg deelnemers toe aan directory?" (geen auto-commit). Niet-bevestigde deelnemers worden niet bewaard.
- **D-08:** macOS attendee-plumbing toevoegen: `attendees: [String]` (+ evt. `organizer: String?`) aan macOS `CalendarEvent`-struct, map in decode-stap. Windows heeft dit al.
- **D-09:** Geseede personen → `isInternal = nil`, `isSelf = false`. Naam uit e-mail/Graph-displayname; e-mail in `emails`; rol/organisatie/expertiseTags leeg.
- **D-10:** Dedup bij seed vóór de review-sheet: filter attendees die al in directory zitten (match op `emails`, dan genormaliseerde naam). Eigen gebruiker (zelf-profiel-/account-e-mail) uit seed-lijst filteren.
- **D-11:** `PersonDirectoryService` (macOS) doet CRUD via `LocalTranscriptStore`'s `ModelContainer`, bevat **geen** `URLSession`-referenties (grep-verifieerbaar). Seed-data komt via bestaande `MicrosoftGraphService`.

### Claude's Discretion
- Exacte SwiftUI-/React-layout van directory-lijst, bewerk-formulier en review-sheet (binnen `TS.Spacing/Font/Radius` + `Color.brand*` op macOS; Tailwind/Fluent op Windows).
- Lijst-vs-grid weergave, zoek/filter binnen de directory (binnen "beheer"-scope).
- NL `Localizable.strings` / Windows inline-NL copy + exacte tekst.
- `chips` vs comma-separated voor `aliases`/`expertiseTags` — moet wél consistent zijn met Phase 1 onboarding-keuze (zie research: Phase 1 koos **comma-separated**, niet chips).
- Of zelf-profiel read-only bovenaan verschijnt of volledig verborgen blijft.
- Exacte naamafleiding uit attendee-e-mail wanneer geen Graph-displayname beschikbaar.

### Deferred Ideas (OUT OF SCOPE)
- Seed vanuit eerder verwerkte transcripts (B-03 "en/of") — agenda-seed is de geleverde bron in Phase 2.
- `{{PEOPLE_CONTEXT}}`-injectie in notule-generatie — **Phase 3** (C-01..C-05).
- Post-generatie persoons-detectie + bewerkbare eigenaar-toewijzing — **Phase 4** (D-01..D-06).
- Leerlus die `expertiseTags` verrijkt — **Phase 4** (D-06).
- Confidence-/herkomst-indicatoren in UI — **Phase 4** / later (D-05).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| B-01 | Personen lokaal vastleggen met naam, aliassen, rol, intern/extern-status, organisatie | Gedeeld `PersonProfile` @Model (macOS) / interface (Windows) — alleen velden uitbreiden (D-01/D-02). CRUD via `LocalTranscriptStore.container` (geen nieuw type, geen URLSession). |
| B-02 | Toevoegen/bewerken/verwijderen via directory-beheer-UI (beide platforms) | macOS: nieuwe `AppTab.people` in custom sidebar (`ContentView.swift:8` enum) + `PersonDirectoryService` CRUD. Windows: nieuwe react-router route `/people` + uitgebreide zustand store. Bewerk-formulier-precedent: `ProfileSettingsView.swift` / `SettingsPage.tsx` Profiel-editor. |
| B-03 | (Semi-)automatische aanvulling uit agenda-deelnemers, gebruiker in controle | macOS attendee-gap dichten (D-08): `$select` haalt `attendees`/`organizer` al op (`MicrosoftGraphService.swift:273`) maar decode dropt ze (`GraphEvent` struct mist velden, regel 439). Review-sheet ná opname-stop (D-07), per-persoon confirm, dedup vooraf (D-10). |
| B-04 | `expertiseTags` per directory-persoon bewerkbaar (gedeeld model) | Veld bestaat al sinds Phase 1 (`PersonProfile.expertiseTags: [String]`). Hergebruik comma-separated invoer-UX uit `ProfileSettingsView.swift:116` + `splitAndTrim`. |
</phase_requirements>

## Summary

Phase 2 is een **additieve uitbreiding** op het Phase 1-fundament, geen nieuwe architectuur. Het deelt het bestaande `PersonProfile` @Model en `LocalTranscriptStore.container`; de enige datamodel-wijzigingen (`isInternal: Bool → Bool?` en nieuw `emails: [String]`) vallen beide binnen SwiftData lightweight-migratie en gaan samen in één nieuwe `SchemaV3`-stage die het V1→V2-patroon één-op-één spiegelt. Cross-platform blijft het werk symmetrisch: macOS krijgt een echte SwiftData-migratie, Windows krijgt een schemaloze JSON-velduitbreiding zonder migratierisico.

De grootste reële complexiteit zit níet in het datamodel maar in twee plumbing-gaps: (1) de macOS Graph-decode gooit attendees weg terwijl de Windows-zijde ze al correct mapt — Windows is de referentie-shape (`emailAddress.email` / `emailAddress.name`); en (2) **`RecordingViewModel` houdt op dit moment geen verwijzing naar het CalendarEvent vast waar de opname bij hoort** — de `CallAlertView` geeft het `meeting`-object door maar `startRecording()` bewaart alleen `selectedMode`, niet het event. De seed-trigger (D-07) vereist dus een nieuwe linkage tussen "actieve opname" en "het CalendarEvent met deelnemers".

**Primary recommendation:** Behandel dit als vier dunne lagen — (1) macOS datamodel + SchemaV3-migratie + RED-migratietest, (2) macOS Graph attendee-plumbing + `PersonDirectoryService` (geen URLSession) + dedup, (3) seed-trigger (event→opname linkage) + review-sheet UI + macOS "Mensen"-tab, (4) Windows full-stack parity (type + store + `/people` route + seed). Hergebruik de Phase 1 comma-separated `splitAndTrim` invoer-UX (NIET chips) voor consistentie (D-06).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Directory CRUD (macOS) | Database/Storage (`PersonDirectoryService` op `ModelContainer`) | UI (SwiftUI Mensen-tab) | Persoonsdata blijft on-device; service praat niet met netwerk (D-11) |
| Directory CRUD (Windows) | Client/Storage (zustand `persist` → localStorage JSON) | UI (React `/people` page) | Schemaloos, geen migratie; spiegelt macOS-CRUD |
| Datamodel-evolutie (macOS) | Database/Storage (`SchemaV3` + `AppMigrationPlan`) | — | Lightweight-migratie behoudt bestaande records |
| Agenda-attendee ophalen | API/Backend (Microsoft Graph via bestaande `MicrosoftGraphService`) | — | Netwerk-IO blijft in Graph-service, niet in directory-service |
| Attendee-decode → CalendarEvent | Client (decode-stap in Graph-service) | — | macOS-gap dichten; Windows is referentie |
| Seed-trigger (event→opname→review) | UI/ViewModel (`RecordingViewModel` event-linkage + review-sheet) | Storage (confirmed personen → service) | Gebruiker in controle, per-persoon confirm, geen auto-commit |
| Dedup | Client (in-memory, in directory-service) | — | Match op `emails` dan genormaliseerde naam, vóór review-sheet |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | iOS 17+/macOS 14+ (platform SDK) | `@Model PersonProfile`, `VersionedSchema`, `MigrationStage.lightweight` | Reeds in gebruik (Phase 1 `AppMigrationPlan`); geen alternatief nodig |
| EventKit / Microsoft Graph REST | platform SDK / Graph v1.0 | Agenda-events + attendees | `$select` haalt attendees al op (`MicrosoftGraphService.swift:273`) |
| Zustand + `persist` middleware | already installed (Windows) | Directory-collectie state → localStorage | Phase 1-precedent (`personProfileStore.ts`); schemaloos |
| react-router-dom | already installed (Windows) | Nieuwe `/people` route | App.tsx gebruikt `<Routes>`/`<Route>` (regel 339-347), NIET een page-store |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| XCTest + SwiftData in-memory `ModelContainer` | platform SDK | Migratie + CRUD + dedup tests (macOS) | Precedent: `MigrationTests.swift`, `PersonProfileTests.swift` |
| vitest | ^4.1.0 (already installed) | Windows store/dedup unit tests | Precedent: `windows/src/services/__tests__/*.test.ts` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `isInternal: Bool?` (tri-state via optional) | Aparte `enum InternalStatus` | Enum = nieuw type + custom migratie + nieuwe Windows-serialisatie. Optional Bool is relaxing/lightweight (D-01). |
| Comma-separated `TextField` (Phase 1-stijl) | Chips/token-field | D-06 vereist consistentie met onboarding; Phase 1 koos comma-separated (`ProfileSettingsView.swift:100,116`). Chips zou inconsistent zijn. |

**Installation:** Geen nieuwe packages. Phase 2 gebruikt uitsluitend bestaande platform-SDK's en reeds-geïnstalleerde dependencies.

**Version verification:** N/A — geen externe package-installatie in deze fase.

## Package Legitimacy Audit

Niet van toepassing: Phase 2 installeert **geen** externe packages op macOS (platform SDK only) noch op Windows (alle benodigde libs — zustand, react-router-dom, vitest — zijn al aanwezig sinds Phase 1). Geen registry-verificatie of slopcheck nodig.

## Architecture Patterns

### System Architecture Diagram

```
                         ┌─────────────────────────────────────────────┐
                         │            DIRECTORY MANAGEMENT (B-01,B-02)   │
  User edits ──────────► │  Mensen-tab/page  ──►  PersonDirectoryService │
                         │  (SwiftUI / React)     (CRUD, NO URLSession)  │
                         │                              │                │
                         └──────────────────────────────┼────────────────┘
                                                         ▼
                                          ┌──────────────────────────────┐
                                          │  LocalTranscriptStore.container│  (macOS)
                                          │  PersonProfile @Model          │
                                          │  isSelf==false = directory     │
                                          │  ──────────────────────────────│
                                          │  zustand persist (Windows)     │
                                          │  localStorage JSON             │
                                          └──────────────────────────────┘
                                                         ▲
                         SEED PIPELINE (B-03)            │ confirmed people only
                         ┌───────────────────────────────┼────────────────┐
  Recording stops ─────► │ RecordingVM knows active event │                │
  (event had attendees)  │      │                         │                │
                         │      ▼                          │                │
                         │ MicrosoftGraphService           │                │
                         │   getUpcomingEvents()           │                │
                         │   $select=...,attendees,organizer                │
                         │   decode → CalendarEvent.attendees: [String]     │
                         │      │  (macOS: NEW plumbing D-08)               │
                         │      ▼                          │                │
                         │  DEDUP (D-10): match emails, then norm-name      │
                         │  filter out self/account email  │                │
                         │      │                          │                │
                         │      ▼                          │                │
                         │  Review-sheet "Voeg toe?"  ──per-person confirm──┘
                         │  (NO auto-commit, D-07)                          │
                         └─────────────────────────────────────────────────┘
```

Trace primary use case (seed): opname met agenda-event stopt → RecordingVM kent het event → Graph-attendees (al gedecodeerd) → dedup tegen bestaande directory + self → review-sheet toont alleen écht nieuwe personen → gebruiker bevestigt per persoon → bevestigden → `PersonDirectoryService` insert (`isInternal=nil`, `isSelf=false`).

### Recommended Project Structure
```
macos/
├── Models/
│   ├── PersonProfile.swift           # + isInternal: Bool?  + emails: [String]
│   └── AppMigrationPlan.swift         # + AppSchemaV3 + v2ToV3 lightweight stage
├── Services/
│   ├── LocalTranscriptStore.swift     # container nu met SchemaV3; directory CRUD helpers OR
│   ├── PersonDirectoryService.swift   # NEW @MainActor service, CRUD + dedup, NO URLSession
│   └── CalendarService.swift          # CalendarEvent + attendees:[String], organizer:String?
│       MicrosoftGraphService.swift    # GraphEvent decode: + attendees/organizer mapping
├── Views/
│   ├── PeopleDirectoryView.swift      # NEW list (Mensen-tab)
│   ├── PersonEditView.swift           # NEW edit form (mirrors ProfileSettingsView UX)
│   └── SeedReviewSheet.swift          # NEW per-person confirm sheet
├── ViewModels/
│   ├── PeopleDirectoryViewModel.swift # NEW @Observable @MainActor
│   └── RecordingViewModel.swift       # + activeMeeting linkage for seed trigger
└── App/ContentView.swift              # + AppTab.people in sidebar enum

windows/src/
├── types.ts                          # PersonProfile: isInternal: boolean|null; + emails: string[]
├── stores/peopleDirectoryStore.ts     # NEW zustand persist (collection)
├── services/microsoftGraph.ts         # already maps attendees/organizer (no change)
├── pages/PeoplePage.tsx               # NEW route /people
└── App.tsx                           # + <Route path="/people"> + sidebar nav item + Ctrl+key
```

### Pattern 1: SchemaV3 lightweight stage (mirror V1→V2 exactly)
**What:** Add `AppSchemaV3` listing both models, append `v2ToV3` lightweight stage.
**When to use:** Both schema changes (D-01 relaxing Bool→Bool?, D-02 additive `emails`) are lightweight-eligible — one combined stage.
**Example:**
```swift
// Source: codebase AppMigrationPlan.swift V1→V2 precedent + [CITED: donnywals.com/a-deep-dive-into-swiftdata-migrations]
enum AppSchemaV3: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(3, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self, PersonProfile.self]
}

enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated(unsafe) static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self]
    nonisolated(unsafe) static var stages: [MigrationStage] = [v1ToV2, v2ToV3]

    static let v1ToV2 = MigrationStage.lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self)
    static let v2ToV3 = MigrationStage.lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self)
}
```
Also update `LocalTranscriptStore.swift:37-41` and `:47` `ModelContainer(for:)` — the schema is inferred from the model types, but the migration plan must include V3. The `for:` model list stays `TranscriptRecord.self, PersonProfile.self` (the current `PersonProfile` definition now carries the V3 fields).

### Pattern 2: macOS Graph attendee decode (Windows = reference shape)
**What:** Add `attendees`/`organizer` to `GraphEvent` decode + `CalendarEvent`, mapping `emailAddress.email`.
**When to use:** D-08 plumbing gap. Windows already does this (`microsoftGraph.ts:183-186`).
**Example:**
```swift
// Source: codebase MicrosoftGraphService.swift:439 (GraphEvent) + Windows reference microsoftGraph.ts:183-186
private struct GraphEvent: Decodable {
    let id: String
    let subject: String?
    let start: GraphDateTime?
    let end: GraphDateTime?
    let onlineMeeting: GraphOnlineMeeting?
    let organizer: GraphRecipient?          // NEW
    let attendees: [GraphAttendee]?         // NEW
}
private struct GraphRecipient: Decodable { let emailAddress: GraphEmailAddress? }
private struct GraphAttendee: Decodable { let emailAddress: GraphEmailAddress? }
private struct GraphEmailAddress: Decodable { let name: String?; let address: String? }
// NOTE: Graph REST field is `emailAddress.address` (NOT `.email`).
// The Windows TS code reads `a.emailAddress?.email` — but the real Graph JSON key is
// `address`. Verify this against a live response; if Windows currently maps `.email`
// it may be silently producing undefined. Cross-check before copying blindly.
```
Then in the `compactMap` decode (`:310`):
```swift
let attendeeEmails = (event.attendees ?? []).compactMap { $0.emailAddress?.address }
let organizerEmail = event.organizer?.emailAddress?.address
return CalendarEvent(..., attendees: attendeeEmails, organizer: organizerEmail)
```

### Pattern 3: PersonDirectoryService — CRUD without URLSession (D-11)
**What:** `@MainActor` service over `LocalTranscriptStore.shared.container`, directory fetch/insert/update/delete + dedup. Contains zero `URLSession` references (grep-verifiable, success criterion 4).
**When to use:** All directory persistence. Seed data arrives as plain `[String]` emails from the already-networked `MicrosoftGraphService` — the directory service never touches the network.
**Example:**
```swift
// Source: codebase LocalTranscriptStore.swift fetch/upsert pattern (FetchDescriptor + #Predicate)
@MainActor
final class PersonDirectoryService {
    private var context: ModelContext { LocalTranscriptStore.shared.container.mainContext }

    func directoryPeople() -> [PersonProfile] {
        let d = FetchDescriptor<PersonProfile>(predicate: #Predicate { $0.isSelf == false },
                                               sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(d)) ?? []
    }
    // insert / update / delete + dedup (see Pattern 4)
}
```

### Pattern 4: Dedup at seed time (D-10)
**What:** Before showing the review-sheet, drop attendees already known (email match, then normalized-name fallback) and drop the self/account email.
**Example:**
```swift
// email match is primary (natural key from Graph); name is fallback only
func newSeedCandidates(from attendeeEmails: [String], selfEmail: String?) -> [String] {
    let existing = directoryPeople()
    let knownEmails = Set(existing.flatMap { $0.emails }.map { $0.lowercased() }
                          + (LocalTranscriptStore.shared.fetchSelfProfile()?.emails ?? []).map { $0.lowercased() })
    let selfSet = Set([selfEmail].compactMap { $0?.lowercased() })
    return attendeeEmails
        .map { $0.lowercased() }
        .filter { !knownEmails.contains($0) && !selfSet.contains($0) }
        // name-normalized fallback applied when a candidate has no email but a displayname
}
```
Name normalization (fallback): lowercase + trim + collapse whitespace; compare against `name` and `aliases`.

### Anti-Patterns to Avoid
- **Custom migration stage for V2→V3:** Both changes are lightweight-eligible; a custom stage adds risk to existing `isSelf`/`TranscriptRecord` data for zero benefit.
- **URLSession in PersonDirectoryService:** Breaks success criterion 4 (grep-verifiable). Network IO stays in `MicrosoftGraphService`.
- **Chips/token-field for tags:** Inconsistent with Phase 1 comma-separated onboarding (D-06). Reuse `splitAndTrim`.
- **Auto-committing seeded attendees:** Violates D-07 + success criterion 2. Every person needs explicit per-person confirm.
- **Treating self-profile as an editable directory row:** Breaks the Phase 1 singleton invariant (D-05/D-09). Filter `isSelf == true` out of the directory list.
- **Showing already-known attendees in the review-sheet:** Dedup MUST run before the sheet (D-10), not after.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Schema versioning | Manual store-version flag + ad-hoc field copy | `VersionedSchema` + `MigrationStage.lightweight` | Phase 1 precedent; SwiftData handles it |
| Directory persistence (macOS) | New CoreData/JSON store | Existing `LocalTranscriptStore.container` | Single source of truth; shared with TranscriptRecord |
| Directory persistence (Windows) | Custom file IO via Tauri fs | zustand `persist` (localStorage) | Phase 1 `personProfileStore` precedent; schemaless |
| Attendee fetch | New Graph request | Existing `getUpcomingEvents()` — `$select` already includes `attendees,organizer` | Data is already fetched and discarded on macOS |
| Tag input UX | New chips component | Phase 1 comma-separated `TextField` + `splitAndTrim` | D-06 consistency requirement |
| Routing (Windows) | Page-id store | Existing react-router `<Route>` | App.tsx already uses BrowserRouter |

**Key insight:** Phase 2 adds almost no new infrastructure. The only genuinely new code is the **seed pipeline glue** (event→recording linkage + dedup + review-sheet) and the directory UI shells. Everything persistence-related extends Phase 1 primitives.

## Runtime State Inventory

> This phase adds fields to an already-persisted SwiftData model (`PersonProfile`) and changes a localStorage JSON shape. Inventory below.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | macOS: existing `isSelf==true` `PersonProfile` record(s) persisted under `Application Support/TranscriptStudio/Local.store` (SchemaV2). SchemaV3 migration must preserve it. `TranscriptRecord`s persisted in same store. Windows: `person-profile-store` key in localStorage (single self profile). | Code edit (migration) — lightweight V2→V3 preserves all rows; no data migration of values needed. New `emails` defaults to `[]`, `isInternal` stays its current value (existing self record had `true`). |
| Live service config | None — Microsoft Graph attendee data is fetched live per `getUpcomingEvents()`; nothing stored server-side that references directory. | None — verified: directory is fully local (D-11). |
| OS-registered state | None — no Task Scheduler/launchd/pm2 entries reference person data. | None — verified by grep (no scheduled-task references to people). |
| Secrets/env vars | None — directory introduces no new secrets; Graph tokens unchanged (managed by existing `MicrosoftGraphService` / backend token store). | None. |
| Build artifacts | None new — pure source changes; no egg-info/compiled-package rename. macOS rebuild + Windows `npm` build pick up changes normally. | None. |

**Migration safety note (D-03):** The existing self-profile record was written under SchemaV2 where `isInternal` is non-optional `Bool`. After V2→V3 (`Bool → Bool?`), that stored value is preserved as the wrapped non-nil value (the relaxing change keeps existing data). New `emails: [String]` materializes as empty `[]` for the existing record. No value-derivation needed → lightweight is correct.

## Common Pitfalls

### Pitfall 1: Additive collection property on an already-persisted model
**What goes wrong:** Phase 1's V1→V2 added `aliases`/`meetingTypes`/`expertiseTags` as `[String]` **simultaneously with introducing the whole `PersonProfile` model** (no rows existed yet). V2→V3 adds `emails: [String]` to a model that **already has a persisted row** (the self profile). That's a new scenario for this codebase.
**Why it happens:** Lightweight migration must supply a default for the existing row. SwiftData materializes a new collection property as empty for existing rows.
**How to avoid:** Keep it lightweight but **prove it** with the RED migration test (seed a V2-style `PersonProfile` + `TranscriptRecord`, run through `AppMigrationPlan`, assert both survive and `emails == []`, `isInternal` preserved). Do not assume — the existing `MigrationTests.swift` only covers V1→V2 TranscriptRecord survival; add a PersonProfile-survival case.
**Warning signs:** "store not reachable" / schema-mismatch crash on launch with an existing store; missing self profile after upgrade.

### Pitfall 2: Graph attendee JSON key — `address` vs `email`
**What goes wrong:** The Windows TS reads `a.emailAddress?.email`, but the Microsoft Graph v1.0 `emailAddress` object uses the key **`address`** (and `name`). If `.email` is wrong, Windows attendees may already be silently `undefined`.
**Why it happens:** Field-name drift between assumed shape and real Graph schema.
**How to avoid:** Verify against one live `calendarView` response before copying. Decode macOS with `address` (the documented Graph key). Flag the Windows `.email` read for verification/fix during parity work.
**Warning signs:** Empty `attendees` array on macOS despite a meeting with participants; seed always shows zero candidates.

### Pitfall 3: Recording has no link to its CalendarEvent
**What goes wrong:** `RecordingViewModel` does not retain the `CalendarEvent` that triggered the recording. `ContentView.swift:131-138` passes `meeting` to `CallAlertView` and then calls `startRecording()` setting only `selectedMode` — the event is dropped. So at stop-time there's nothing to read attendees from.
**Why it happens:** Phase 1/earlier had no need for the event past the start moment.
**How to avoid:** Add an `activeMeeting: CalendarEvent?` (or just `activeAttendees: [String]`) to `RecordingViewModel`, set it where recording is started from a calendar event (CallAlert `onStartRecording`, `.meetingRecordRequested`, `.videoCallDetected`), clear it on stop/cancel. The seed-trigger in `stopAndUpload()` reads it. Manually-started recordings (no event) simply have `nil` → no seed prompt.
**Warning signs:** Review-sheet never appears even after a meeting with attendees; or appears with stale attendees from a previous meeting (forgot to clear).

### Pitfall 4: Windows store name collision
**What goes wrong:** A new zustand `persist` store with a name colliding with `person-profile-store`, `profiles-store`, or `settings-store` corrupts state.
**Why it happens:** localStorage keys are global.
**How to avoid:** Use a distinct key, e.g. `name: "people-directory-store"`. (Phase 1 explicitly flagged this — see comment `personProfileStore.ts:43`.)
**Warning signs:** Self profile disappears or directory overwrites profile data after reload.

### Pitfall 5: Self profile leaking into the directory list
**What goes wrong:** Directory fetch returns the `isSelf==true` record as an editable row, letting the user delete/duplicate it and breaking the singleton.
**How to avoid:** Always filter `isSelf == false` in directory queries (macOS `#Predicate`, Windows `.filter`). If showing self read-only at top (D-05 discretion), render it from a separate code path.

## Code Examples

### Update PersonProfile @Model (macOS, D-01 + D-02)
```swift
// Source: codebase PersonProfile.swift (extend in place)
@Model final class PersonProfile {
    @Attribute(.unique) var id: String
    var name: String
    var role: String
    var organization: String
    var aliases: [String]
    var meetingTypes: [String]
    var expertiseTags: [String]
    var emails: [String]          // NEW (D-02) — dedup key from Graph attendees
    var isSelf: Bool
    var isInternal: Bool?         // CHANGED Bool -> Bool? (D-01): nil=onbekend
    var createdAt: Date
    var updatedAt: Date

    init(/* ... */ emails: [String] = [], isInternal: Bool? = nil /* ... */) { /* ... */ }
}
```
Note: change the `init` default for `isInternal` from `true` to `nil` for seeded entries; the self-profile upsert in `LocalTranscriptStore.swift:129` currently passes `isInternal: true` explicitly — keep that explicit `true` for self.

### Comma-separated tag input (reuse Phase 1 UX, D-06)
```swift
// Source: codebase ProfileSettingsView.swift:100,116,167-169 + splitAndTrim
TextField("grafisch ontwerp, marketing, IT (kommagescheiden)", text: $expertise)
// load:  expertise = person.expertiseTags.joined(separator: ", ")
// save:  expertiseTags: splitAndTrim(expertise)
```

### Windows PersonProfile + collection store
```typescript
// Source: codebase types.ts:78 + personProfileStore.ts pattern
export interface PersonProfile {
  // ...existing...
  emails: string[];              // NEW
  isInternal: boolean | null;    // CHANGED from boolean (null = onbekend)
}

// peopleDirectoryStore.ts — NEW
export const usePeopleDirectoryStore = create<PeopleDirectoryState>()(
  persist((set, get) => ({
    people: [],                  // PersonProfile[] with isSelf=false
    addPerson: (p) => set((s) => ({ people: [...s.people, p] })),
    updatePerson: (id, u) => set((s) => ({ people: s.people.map(x => x.id===id ? {...x,...u,updatedAt:new Date().toISOString()} : x) })),
    removePerson: (id) => set((s) => ({ people: s.people.filter(x => x.id!==id) })),
  }), { name: "people-directory-store" })  // distinct key (Pitfall 4)
);
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `isInternal: Bool` (binary, default true) | `isInternal: Bool?` tri-state | Phase 2 | Seeded people = `nil` (onbekend); relaxing/lightweight |
| macOS drops Graph attendees | macOS decodes `attendees`/`organizer` | Phase 2 (D-08) | Enables seed; Windows already did this |
| No people directory | Directory of `isSelf==false` profiles | Phase 2 | Reuses Phase 1 model, no new type |

**Deprecated/outdated:** None. Phase 2 extends current Phase 1 code; no replacements.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Adding a new `[String]` property to an *already-persisted* model is lightweight-eligible (SwiftData materializes `[]`). | Pitfall 1 / D-02 | If wrong → launch crash on upgrade with existing self profile. **Mitigation: RED migration test proves it before shipping.** Verified lightweight for optional/defaulted props via [CITED: donnywals.com]; the persisted-row collection case is the residual assumption. |
| A2 | Microsoft Graph `emailAddress` object key is `address` (not `email`); Windows TS `.email` may be incorrect. | Pitfall 2 / Pattern 2 | If `.address` is wrong, macOS attendees decode empty. Verify against a live Graph response. |
| A3 | `isInternal: Bool → Bool?` preserves the existing self record's `true` value under lightweight migration. | Runtime State Inventory | If wrong, self-profile internal status resets. Covered by migration test assertion. |
| A4 | No new external packages required on either platform. | Standard Stack | Low — verified zustand/react-router/vitest present; macOS is platform-SDK only. |

## Open Questions (RESOLVED)

1. **Self/account email source for dedup-filter (D-10)**
   - What we know: `MicrosoftGraphService` exposes `accountEmail`; `CalendarService.microsoftAccountEmail`; self profile will have `emails` (possibly empty until user fills it).
   - What's unclear: If the user never enters their own email into the self profile, only the Graph `accountEmail` filters them out. For Apple-only calendar users there may be no account email.
   - Recommendation: Filter on (self-profile emails ∪ Graph account email). Document that Apple-calendar-only users may need to enter their own email once. Planner: small decision, not a blocker.
   - **RESOLVED:** selfEmail = `accountEmail ∪ microsoftAccountEmail ∪ self-profile emails`. Locked in 02-03 T2 (macOS) and 02-04 T3 / 02-05 T3 (seed self-filter). Apple-calendar-only users with no self-email/account-email are mitigated by per-person confirm.

2. **Where exactly to fire the seed trigger in `stopAndUpload()`**
   - What we know: `stopAndUpload()` branches into local/onDevice/cloud/offline paths and returns early in each.
   - What's unclear: The cleanest single place to invoke the review-sheet after a successful stop regardless of processing path.
   - Recommendation: Capture `activeMeeting` at stop-start, present the review-sheet from the ViewModel/View layer after `recordingState` settles (not inside each upload branch). Decouples seed from processing path.
   - **RESOLVED:** Capture `activeMeeting` at stop; present the seed sheet from the view layer after `recordingState` settles via `pendingSeedAttendees` (not inside any upload branch). Locked in 02-04 T1 (macOS) / 02-05 T3 (Windows mirror).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / Swift 6 toolchain | macOS build + migration test | ✓ | project-configured | — |
| Microsoft 365 account w/ calendar+attendees | Live seed end-to-end test | ✗ (cannot verify in this session) | — | Unit-test dedup + decode with fixture JSON; manual live test on dev machine |
| Node + vitest | Windows store/dedup tests | ✓ | vitest ^4.1.0 | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** Live Graph attendee response — use a captured/fixture JSON for the decode + dedup unit tests; defer the true end-to-end seed to manual verification on a machine with a connected M365 account.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | macOS: XCTest (`TranscriptStudioTests`); Windows: vitest ^4.1.0 |
| Config file | macOS: scheme `TranscriptStudioTests`; Windows: `vite.config.*` (no separate vitest config) |
| Quick run command | `xcodebuild test -project TranscriptStudio.xcodeproj -scheme TranscriptStudioTests` · Windows: `cd windows && npx vitest run` |
| Full suite command | same as above (both platforms) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| B-01/A-04 | SchemaV3 migration preserves existing self `PersonProfile` + `TranscriptRecord`; `emails==[]`, `isInternal` preserved | unit (in-memory ModelContainer) | `xcodebuild test ... -only-testing:TranscriptStudioTests/MigrationTests` | ⚠️ extend `MigrationTests.swift` (currently only V1→V2 TranscriptRecord) — ❌ Wave 0 |
| B-01/B-02 | Directory CRUD round-trip (insert→fetch→update→delete) only returns `isSelf==false` | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/PersonDirectoryServiceTests` | ❌ Wave 0 |
| B-03 | Graph attendee decode maps `emailAddress.address` into `CalendarEvent.attendees` from fixture JSON | unit | `xcodebuild test ... -only-testing:TranscriptStudioTests/GraphAttendeeDecodeTests` | ❌ Wave 0 |
| B-03/D-10 | Dedup filters known emails + self/account email; name-fallback | unit | macOS + `npx vitest run` (Windows dedup) | ❌ Wave 0 |
| D-11 | `PersonDirectoryService` contains no `URLSession` | static grep gate | `! grep -q "URLSession" macos/Services/PersonDirectoryService.swift` | ❌ Wave 0 (add as plan verification step) |
| B-01/B-04 | Windows store round-trip + tag edit; distinct localStorage key | unit | `npx vitest run` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** relevant `-only-testing:` subset (macOS) / `npx vitest run <file>` (Windows)
- **Per wave merge:** full `xcodebuild test` + full `npx vitest run`
- **Phase gate:** both suites green + `grep` URLSession gate passes + manual seed smoke on a live M365 machine before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] Extend `TranscriptStudioTests/MigrationTests.swift` — add PersonProfile-survival V2→V3 case (covers B-01/A-04)
- [ ] `TranscriptStudioTests/PersonDirectoryServiceTests.swift` — CRUD + dedup (B-01/B-02/D-10)
- [ ] `TranscriptStudioTests/GraphAttendeeDecodeTests.swift` + fixture JSON (B-03)
- [ ] `windows/src/stores/__tests__/peopleDirectoryStore.test.ts` — round-trip + dedup (B-01/B-04/D-10)
- [ ] URLSession grep gate as an explicit plan verification step (D-11)

## Security Domain

> `security_enforcement` not present in config → treated as enabled. Phase is local-first; limited surface.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No new auth; directory is local. Graph token flow unchanged (existing service). |
| V3 Session Management | no | — |
| V4 Access Control | no | Single-user on-device data; no multi-tenant boundary. |
| V5 Input Validation | yes | Trim/normalize attendee emails + free-text fields (`name`/`role`/`aliases`) before persist; avoid storing control chars. Reuse `splitAndTrim`. |
| V6 Cryptography | no | No new secrets; person data stored in standard local store (not encrypted-at-rest beyond OS defaults — consistent with existing TranscriptRecord local store). |

### Known Threat Patterns for {SwiftData local store + Graph-sourced strings}
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Untrusted attendee displayname/email persisted then later injected into LLM prompt (Phase 3) | Tampering / Injection | **Out of scope here** but flag for Phase 3: sanitize names/emails before `{{PEOPLE_CONTEXT}}` injection (C-03). Phase 2 should at least normalize/trim so Phase 3 inherits clean data. |
| Self-profile singleton corruption via directory edit | Tampering | Filter `isSelf==true` out of directory CRUD (Pitfall 5) |
| localStorage store-name collision (Windows) | Tampering | Distinct `people-directory-store` key (Pitfall 4) |
| Accidental network exfil of person data | Information Disclosure | `PersonDirectoryService` has no `URLSession` (D-11) + grep gate |

## Sources

### Primary (HIGH confidence)
- Codebase: `PersonProfile.swift`, `AppMigrationPlan.swift`, `LocalTranscriptStore.swift`, `CalendarService.swift`, `MicrosoftGraphService.swift` (:260-454), `ContentView.swift`, `RecordingViewModel.swift` (:369-462), `ProfileSettingsView.swift`, `MigrationTests.swift` — direct reads
- Windows codebase: `types.ts` (:78-90,277-286), `personProfileStore.ts`, `microsoftGraph.ts` (:140-195), `App.tsx` (router) — direct reads
- [CITED: donnywals.com/a-deep-dive-into-swiftdata-migrations] — lightweight eligibility: add-optional ✓, non-optional→optional ✓ (relaxing), custom required for invented/derived non-optional values

### Secondary (MEDIUM confidence)
- [CITED: hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations] — corroborates lightweight rule set (WebSearch summary; page itself 403'd on fetch)
- WebSearch aggregate on SwiftData lightweight migration eligibility

### Tertiary (LOW confidence)
- Microsoft Graph `emailAddress.address` key — inferred from Graph v1.0 conventions + Windows code; flagged A2 for live verification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all existing, verified against codebase
- Architecture: HIGH — extends Phase 1 patterns directly
- Migration (D-01 relaxing): HIGH — verified via Donny Wals + Hacking with Swift
- Migration (D-02 collection on persisted row): MEDIUM — lightweight expected, RED test required (A1)
- Graph decode key: MEDIUM — `address` likely correct, verify live (A2)
- Pitfalls: HIGH — event-linkage gap and store-name collision found directly in code

**Research date:** 2026-06-05
**Valid until:** ~2026-07-05 (stable platform SDKs; codebase-grounded)
