# Phase 2: People Directory - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 levert een **lokale mensen-directory**: collega's en bekende externen die de
gebruiker handmatig kan beheren (toevoegen/bewerken/verwijderen) en (semi-)automatisch
kan aanvullen vanuit agenda-deelnemers. De directory hergebruikt het in Phase 1 gebouwde
gedeelde `PersonProfile`-model (`isSelf == false` voor directory-entries) en blijft volledig
on-device. Cross-platform: macOS (Swift 6 / SwiftData) + Windows (Tauri 2 / React / Zustand).

**In scope (B-01 t/m B-04):**
- Directory-CRUD-UI op beide platforms: naam, aliassen, rol, expertiseTags, intern/extern/onbekend, organisatie
- Semi-automatische seed vanuit agenda-deelnemers (Microsoft Graph attendees), gebruiker bevestigt per persoon (geen auto-commit)
- `expertiseTags` per directory-persoon bewerkbaar (gedeeld model met zelf-profiel)
- `PersonDirectoryService` zonder `URLSession` — persoonsdata blijft lokaal (verifieerbaar via grep)

**Niet in scope (latere fasen):**
- `{{PEOPLE_CONTEXT}}`-injectie in notule-generatie — Phase 3 (C-01..C-05)
- Post-generatie persoons-detectie + bewerkbare eigenaar-toewijzing — Phase 4 (D-01..D-06)
- Seed vanuit eerder verwerkte transcripts (B-03 noemt dit optioneel "en/of") — niet primair scope; agenda-seed is de geleverde bron

</domain>

<decisions>
## Implementation Decisions

### Datamodel-uitbreiding (PersonProfile → SchemaV3)
- **D-01: Intern/extern/onbekend als optionele Bool.** Verander `PersonProfile.isInternal: Bool`
  (huidig, default `true`) naar **`isInternal: Bool?`** — `nil = onbekend`, `true = intern`,
  `false = extern`. Agenda-geseede personen krijgen `nil` (onbekend, success criterion 3);
  de gebruiker kan corrigeren. Een non-optional → optional verandering is een **relaxing**
  schema-wijziging en valt binnen SwiftData lightweight migratie.
- **D-02: E-mail-identifier voor dedup.** Voeg **`emails: [String]`** toe aan `PersonProfile`
  (precedent: `aliases`/`meetingTypes`/`expertiseTags` zijn al `[String]`). Calendar-attendees
  ZIJN e-mailadressen → matching/dedup eerst op e-mail, daarna fallback op genormaliseerde naam.
  Puur additief veld.
- **D-03: Eén gecombineerde SchemaV3 lightweight-stage.** D-01 (`Bool → Bool?`) + D-02
  (`emails: [String]` additief) gaan samen in **`SchemaV3`** met
  `MigrationStage.lightweight(fromVersion: SchemaV2, toVersion: SchemaV3)` in `AppMigrationPlan`.
  Phase 1 anticipeerde expliciet schema-groei in Phase 2 — dit is dat moment. Geen custom stage,
  geen data-wipe. Bestaand `isSelf == true`-record en alle `TranscriptRecord`s blijven intact.
- **Windows-equivalent:** `isInternal` wordt nullable (`boolean | undefined`/`null`) + `emails: string[]`
  in het PersonProfile-type + zustand-store. Schemaloze JSON (localStorage) → geen migratie-risico.

### Directory-beheer-UI (B-01, B-02)
- **D-04: Top-level navigatie "Mensen".** De directory is een **first-class navigatie-item**,
  niet verstopt in Settings. macOS: nieuwe entry in de custom collapsible sidebar (52px icon ↔ full;
  DEC-029). Windows: nieuwe "Mensen"-pagina in de bestaande page-router. Een dagelijks-gebruikt
  adresboek hoort vindbaar te zijn.
- **D-05: Gedeeld `PersonProfile`-model.** Directory-entries zijn `PersonProfile` met `isSelf == false`.
  Het zelf-profiel (`isSelf == true`) verschijnt NIET als bewerkbare directory-entry (of read-only
  bovenaan — planner's discretie), zodat de singleton-invariant uit Phase 1 (D-09) intact blijft.
- **D-06: `expertiseTags` bewerkbaar per persoon** (B-04) — zelfde invoer-UX als het zelf-profiel
  (consistent met Phase 1; chips-vs-comma blijft Claude's discretie maar moet gelijk zijn aan onboarding).

### Agenda-seed (B-03)
- **D-07: Review-sheet ná opname-stop, per-persoon bevestigen.** Wanneer een opname die gekoppeld is
  aan een agenda-event mét deelnemers stopt, toont de app een review-sheet "Voeg deelnemers toe aan
  directory?" met per-persoon bevestiging (geen auto-commit, success criterion 2). Niet-bevestigde
  deelnemers worden niet bewaard.
- **D-08: macOS attendee-plumbing toevoegen (gap).** macOS `CalendarEvent` (`CalendarService.swift:28`)
  dropt nu de Graph-attendees terwijl `$select` ze al ophaalt (`MicrosoftGraphService.swift:273`).
  Voeg `attendees: [String]` (e-mails) + evt. `organizer: String?` toe aan de macOS `CalendarEvent`-struct
  en map ze in de decode-stap (`MicrosoftGraphService.swift:310`). Windows heeft `attendees: string[]`
  + `organizer` al (`types.ts:284-285`, `microsoftGraph.ts:183-185`) — geen plumbing nodig daar.
- **D-09: Geseede personen → `isInternal = nil` (onbekend), `isSelf = false`.** Naam afgeleid uit
  e-mail/Graph-displayname; e-mail in `emails`; rol/organisatie/expertiseTags leeg tot de gebruiker invult.
- **D-10: Dedup bij seed.** Vóór de review-sheet: filter attendees die al in de directory zitten
  (match op `emails`, dan genormaliseerde naam) zodat de prompt alleen écht nieuwe personen toont.
  De eigen gebruiker (zelf-profiel-e-mail / account-e-mail) wordt uit de seed-lijst gefilterd.

### PersonDirectoryService
- **D-11: On-device service zonder netwerk.** `PersonDirectoryService` (macOS) doet CRUD via
  `LocalTranscriptStore`'s `ModelContainer` en bevat **geen** `URLSession`-referenties (success
  criterion 4, grep-verifieerbaar). Seed-data komt binnen via de bestaande `MicrosoftGraphService`
  (de directory-service zelf praat niet met het netwerk).

### Claude's Discretion
- Exacte SwiftUI-/React-layout van de directory-lijst, het bewerk-formulier en de review-sheet
  (binnen `TS.Spacing/Font/Radius` + `Color.brand*` op macOS; Tailwind + Fluent op Windows).
- Lijst-vs-grid weergave, zoek/filter binnen de directory (zolang binnen "beheer"-scope, geen nieuwe capability).
- NL `Localizable.strings` / Windows i18n keys + exacte copy.
- `chips` vs comma-separated invoer voor `aliases`/`expertiseTags` — moet wél consistent zijn met de Phase 1 onboarding-keuze.
- Of het zelf-profiel read-only bovenaan de directory verschijnt of volledig verborgen blijft.
- Exacte naamafleiding uit een attendee-e-mail wanneer geen Graph-displayname beschikbaar is.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project & requirements
- `.planning/PROJECT.md` — milestone "People & Attribution", PersonProfile-naamgeving, local-first key decisions
- `.planning/REQUIREMENTS.md` §B — requirements B-01 t/m B-04 (locked)
- `.planning/ROADMAP.md` — Phase 2 goal + 5 success criteria
- `.planning/phases/01-self-profile-foundation/01-CONTEXT.md` — Phase 1 datamodel-/migratie-beslissingen (D-01..D-09) die hier doorwerken

### macOS (Swift / SwiftData)
- `macos/Models/PersonProfile.swift` — gedeeld `@Model`; hier komen `isInternal: Bool?` + `emails: [String]`
- `macos/Models/AppMigrationPlan.swift` — `VersionedSchema`/`SchemaMigrationPlan`; nieuwe `SchemaV3` lightweight-stage
- `macos/Services/LocalTranscriptStore.swift` — bezit de `ModelContainer`; basis voor `PersonDirectoryService` CRUD
- `macos/Services/CalendarService.swift` §28 — `CalendarEvent`-struct; attendee-velden toevoegen (D-08)
- `macos/Services/MicrosoftGraphService.swift` §260-318 — `getUpcomingEvents()`/decode; attendees mappen (`$select` haalt ze al op)
- `macos/Views/ProfileSettingsView.swift` — bestaande zelf-profiel-editor; UX-precedent voor het directory-bewerk-formulier
- `macos/App/ContentView.swift` — sidebar-navigatie; nieuwe "Mensen"-entry inhaken (DEC-029 collapsible sidebar)

### Windows (Tauri 2 / React / Zustand)
- `windows/src/types.ts` §154,277-285 — `PersonProfile`-type (nullable `isInternal` + `emails`), `CalendarEvent` heeft attendees/organizer al
- `windows/src/services/microsoftGraph.ts` §149,183-185 — attendees/organizer al beschikbaar (emails)
- `windows/src/stores/calendarStore.ts` — calendar-account-state; bron voor seed
- `windows/src/pages/SettingsPage.tsx` — bestaande Profiel-editor (UX-precedent); page-router-patroon voor nieuwe "Mensen"-pagina
- bestaande `personProfileStore` (Phase 1, zustand persist) — uitbreiden naar meerdere personen

### Codebase maps
- `.planning/codebase/ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `INTEGRATIONS.md` — patronen, conventies, Microsoft Graph integratie

### Framework docs
- SwiftData `VersionedSchema`, `SchemaMigrationPlan`, `MigrationStage.lightweight` (Bool→Bool? = relaxing, additief veld) — Context7 `/websites/developer_apple_swiftdata`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PersonProfile` `@Model` (Phase 1): hergebruikt voor directory; alleen velden uitbreiden, geen nieuw type.
- `LocalTranscriptStore.shared.container`: bestaande MainActor SwiftData-store + versioned schema; basis voor directory-CRUD.
- `AppMigrationPlan` (SchemaV1→V2): precedent voor de nieuwe SchemaV2→V3 lightweight-stage.
- `ProfileSettingsView.swift` (macOS) / Profiel-editor in `SettingsPage.tsx` (Windows): bewerk-formulier-precedent voor het directory-formulier.
- `MicrosoftGraphService.getUpcomingEvents()`: `$select` haalt `attendees`+`organizer` al op — Windows mapt ze, macOS niet (gap D-08).
- zustand `persist` `personProfileStore` (Phase 1): uitbreiden van singleton naar collectie.

### Established Patterns
- macOS: `@Observable` ViewModels, `actor`/`@MainActor` services, `async/await`. Services zonder Combine/completion handlers.
- SwiftData: app-specifieke store-URL, in-memory fallback; versioned schema + migration plan.
- Custom collapsible sidebar (52px ↔ full), toggle `Shift+Cmd+S`, géén `columnVisibility` (DEC-029).
- UI-strings NL via `Localizable.strings` / Windows i18n; code/comments EN. Design tokens `TS.*` + `Color.brand*`.
- Auth header macOS `X-User-Token`, Windows `Authorization: Bearer`; backend `username` == e-mailadres.

### Integration Points
- `PersonProfile`-schema-uitbreiding + nieuwe `SchemaV3` migratie-stage (macOS).
- Nieuwe `PersonDirectoryService` (macOS) op de bestaande `ModelContainer`; geen `URLSession`.
- macOS `CalendarEvent` attendee-plumbing in `CalendarService` + `MicrosoftGraphService` decode.
- Sidebar-/page-navigatie (nieuwe "Mensen"-route) op beide platforms.
- Seed-trigger gekoppeld aan opname-stop wanneer een event met deelnemers actief was.

</code_context>

<specifics>
## Specific Ideas

- Tri-state intern/extern/onbekend representeert via optionele Bool (`nil` = onbekend) i.p.v. een aparte enum — minimale, relaxing schema-wijziging.
- Dedup primair op e-mail (de natuurlijke sleutel uit Graph-attendees), naam alleen als fallback.
- Eigen gebruiker uit de seed-lijst filteren (zelf-profiel/account-e-mail).
- macOS attendee-gap is een bekende bron-omissie, geen nieuwe capability — `$select` levert de data al.

</specifics>

<deferred>
## Deferred Ideas

- Seed vanuit eerder verwerkte transcripts (B-03 "en/of") — agenda-seed is de geleverde bron in Phase 2; transcript-mining kan later.
- `{{PEOPLE_CONTEXT}}`-injectie in notule-generatie — **Phase 3** (C-01..C-05).
- Post-generatie persoons-detectie + bewerkbare eigenaar-toewijzing — **Phase 4** (D-01..D-06).
- Leerlus die `expertiseTags` verrijkt na bevestigde toewijzing — **Phase 4** (D-06).
- Confidence-/herkomst-indicatoren in de UI — **Phase 4** / later (D-05).

None overige — discussie bleef binnen de Phase 2-scope.

</deferred>

---

*Phase: 02-people-directory*
*Context gathered: 2026-06-05*
