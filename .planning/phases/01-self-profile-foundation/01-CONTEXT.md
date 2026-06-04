# Phase 1: Self-Profile Foundation - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 levert het fundament voor persoonscontext: de installerende gebruiker stelt
zichzelf voor via een korte, overslaanbare onboarding-stap; het zelf-profiel wordt
on-device opgeslagen in een nieuw, gedeeld `PersonProfile`-datamodel (macOS SwiftData +
Windows zustand-persist), bewerkbaar via een Settings-sectie op beide platforms; en een
app-upgrade die het datamodel introduceert behoudt bestaande transcript-historie via een
versioned migratie.

**In scope (A-01 t/m A-04):**
- Overslaanbare self-profile onboarding-stap (naam, rol, organisatie, aliassen, meeting-types)
- `PersonProfile`-model on-device, werkt in local-mode zonder account — macOS + Windows
- Settings-sectie om het profiel later te bekijken/bewerken — beide platforms
- Versioned SwiftData-migratie zodat bestaande transcripts intact blijven

**Niet in scope (latere fasen):**
- Mensen-directory (collega's/externen) — Phase 2
- Context-injectie in notule-generatie — Phase 3
- Mapping + bewerkbare eigenaar-toewijzing — Phase 4

</domain>

<decisions>
## Implementation Decisions

### SwiftData migratie (A-04)
- **D-01:** Introduceer een **expliciete `VersionedSchema`** in `LocalTranscriptStore`.
  `SchemaV1` = huidige store (alleen `TranscriptRecord`), `SchemaV2` = `TranscriptRecord`
  + `PersonProfile`. Gebruik een **`MigrationStage.lightweight(fromVersion: SchemaV1, toVersion: SchemaV2)`**
  via een `SchemaMigrationPlan`, doorgegeven aan `ModelContainer(for:migrationPlan:configurations:)`.
- **Rationale:** Sluit aan op A-04's expliciete "versioned migratie"-eis, geeft een
  testbaar upgrade-pad en een schone basis voor de schema-groei in Phase 2-4 (directory,
  attributie-velden op `TranscriptRecord`). Context7/SwiftData bevestigt dat het toevoegen
  van een nieuw `@Model` puur additief is en binnen lightweight migratie valt — geen custom
  stage of data-wipe nodig.
- **D-02:** De bestaande one-time kopie uit de oude default-store (`migrateFromDefaultStore`)
  blijft ongewijzigd functioneren; de versioned schema mag dit pad niet breken.

### PersonProfile datamodel
- **D-03:** `PersonProfile` is een **volwaardig gedeeld `@Model`** dat de Phase 2 directory
  hergebruikt — niet een minimaal self-only model. Voorkomt een tweede migratie volgende fase.
- **D-04:** Velden: `id` (UUID-string, `@Attribute(.unique)`), `name`, `role`, `organization`,
  `aliases: [String]`, `meetingTypes: [String]`, `isSelf: Bool`, `isInternal: Bool` (default `true`),
  `createdAt`, `updatedAt`. Phase 1 schrijft uitsluitend het `isSelf == true`-record;
  directory-entries (`isSelf == false`) komen in Phase 2.
- **D-05:** Naam-collisie met het bestaande `Profile` (notule-stíjl, `Models.swift:221`) wordt
  voorkomen door het nieuwe type consequent `PersonProfile` te noemen + een collision-warning
  comment in `Models.swift` (success criterion 5). `Profile` wordt nooit hergebruikt.

### Onboarding-stap & skip-UX
- **D-06:** De self-profile-stap komt **vóór de afsluitende 'klaar'-stap**, ná de
  permissie-stappen. macOS: nieuwe `OnboardingStep`-case tussen `schermopname` en `klaar`.
  Windows: nieuwe stap vóór de laatste in `OnboardingWizard.tsx`.
- **D-07:** Volledig **overslaanbaar** via een expliciete "Overslaan"-knop; alle velden zijn
  optioneel. Overslaan = geen `PersonProfile`-record aangemaakt; functionaliteit blijft intact.

### Settings-editor & self-singleton
- **D-08:** Nieuwe **dedicated Settings-sectie** ("Profiel" / "Over jou") op beide platforms,
  los van de bestaande notule-Profile-instellingen.
- **D-09:** Exact **één** `isSelf == true`-`PersonProfile` (singleton), via upsert: fetch
  `isSelf == true`, maak aan als afwezig, anders bewerk in-place. Afwezig/leeg profiel is
  toegestaan (bv. na overgeslagen onboarding).

### Claude's Discretion
- Exacte SwiftUI-layout van de onboarding-stap en de Settings-editor (binnen bestaande
  `TS.Spacing/Font/Radius` + `Color.brand*` tokens; Windows binnen Tailwind + Fluent).
- Windows-opslagmechanisme voor `PersonProfile`: zustand `persist` store (localStorage,
  schemaloos JSON — geen migratie-risico zoals SwiftData) of een dedicated store; planner kiest.
- NL `Localizable.strings` / Windows i18n keys en exacte copy.
- Of `meetingTypes`/`aliases` in de onboarding als comma-separated input of chips worden ingevoerd.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project & requirements
- `.planning/PROJECT.md` — milestone-scope "People & Attribution", key decisions (PersonProfile-naamgeving, local-first)
- `.planning/REQUIREMENTS.md` §A — requirements A-01 t/m A-04 (locked)
- `.planning/ROADMAP.md` — Phase 1 goal + success criteria

### macOS (Swift / SwiftData)
- `macos/Services/LocalTranscriptStore.swift` — bezit de `ModelContainer`; hier komt de VersionedSchema + migration plan
- `macos/Models/TranscriptRecord.swift` — bestaand `@Model`, wordt `SchemaV1`-lid
- `macos/Models/Models.swift` §221 — bestaand `Profile` (notule-stíjl); collision-warning hier
- `macos/App/TranscriptStudioApp.swift` — `.modelContainer(...)` injectie + `@AppStorage("hasCompletedOnboarding")` gate
- `macos/Views/OnboardingView.swift` — `OnboardingStep`-enum; nieuwe self-profile case invoegen

### Windows (Tauri 2 / React / Zustand)
- `windows/src/stores/settingsStore.ts` — zustand `persist`-patroon (localStorage), `has_completed_onboarding`
- `windows/src/components/onboarding/OnboardingWizard.tsx` — 5-staps wizard (0-4); nieuwe stap invoegen
- `windows/src/stores/profilesStore.ts` — bestaande notule-Profile store (NIET hergebruiken voor PersonProfile)
- `windows/src/types.ts` — type-definities

### Codebase maps
- `.planning/codebase/ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md` — patronen & conventies

### Framework docs
- SwiftData `ModelContainer(for:migrationPlan:configurations:)`, `VersionedSchema`, `SchemaMigrationPlan`,
  `MigrationStage.lightweight` — Context7 `/websites/developer_apple_swiftdata`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LocalTranscriptStore.shared.container`: bestaande MainActor SwiftData-store met CRUD; breid uit met `PersonProfile` + versioned schema.
- `OnboardingView.OnboardingStep` (macOS) & `OnboardingWizard` step-state (Windows): bestaande multi-step patronen om de self-profile-stap in te haken.
- zustand `persist`-middleware (`settingsStore.ts`): patroon voor on-device Windows-opslag van `PersonProfile`.
- Design tokens: `TS.Spacing/Font/Radius`, `Color.brand*` (macOS); Tailwind + Fluent (Windows).

### Established Patterns
- macOS: `@Observable` ViewModels (geen ObservableObject/Combine), `actor`/`@MainActor` services, `async/await`.
- SwiftData: app-specifieke store-URL (`Application Support/TranscriptStudio/Local.store`), in-memory fallback bij faalde store.
- Onboarding gated via `@AppStorage("hasCompletedOnboarding")` (macOS) / `has_completed_onboarding` in settingsStore (Windows).
- UI-strings NL via `Localizable.strings` / Windows i18n; code/comments EN.

### Integration Points
- `ModelContainer`-init in `LocalTranscriptStore` (versioned schema + migration plan).
- Onboarding-flow (nieuwe stap) op beide platforms.
- Settings-UI (nieuwe sectie) op beide platforms.
- Bestaande `migrateFromDefaultStore`-pad mag niet breken.

</code_context>

<specifics>
## Specific Ideas

- Self-profile velden volgen exact de roadmap: naam, rol/functie, organisatie, aanspreekvormen/aliassen, typische meeting-types.
- `isSelf`-vlag is de leidende discriminator (uit REQUIREMENTS A-02), forward-compatible met de Phase 2 directory.

</specifics>

<deferred>
## Deferred Ideas

- Mensen-directory met collega's/externen, agenda-seed (Microsoft Graph attendees) — **Phase 2** (B-01..B-03).
- `{{PEOPLE_CONTEXT}}`-injectie in lokale + cloud notule-generatie — **Phase 3** (C-01..C-04).
- Naam→persoon-mapping + bewerkbare eigenaar-toewijzing, `TranscriptRecord`-attributievelden — **Phase 4** (D-01..D-04).

None overige — discussie bleef binnen de Phase 1-scope.

</deferred>

---

*Phase: 01-self-profile-foundation*
*Context gathered: 2026-06-04*
