# Lerende context: woordenlijst, personen en taakverdeling

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ThoughtVault leert van elk gesprek: één woordenlijst (term, foute varianten, toelichting) en een mensenlijst met functie en taken gaan als context mee naar de notule-AI, en na elke notule stelt de AI nieuwe termen en personen voor, met versiebeheer en herstel.

**Architecture:** Alles draait in de app, geen backend. Bronnen: `personal-corrections.json` (woordenlijst, versie 2) en SwiftData `PersonProfile` met nieuw veld `responsibilities`. Eén functie bouwt daar een contextblok van voor de notuleprompt. Na het opslaan van een notule doet een tweede, korte AI-aanroep (`LLMService.complete`) een JSON-voorstel voor termen en personen, dat in een balk boven de notule verschijnt. Wijzigingsgeschiedenis staat in een apart, alleen groeiend `context-history.json`, zodat het SwiftData-schema alleen een additief V4 krijgt.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData (gedeelde macOS- en iOS-code), Tauri 2 + React/TS (Windows), XCTest, vitest.

**Spec:** de beslissingen hieronder, vastgesteld met Michel op 9 nov 2026. Er is geen apart spec-document.

## Uitgangspunt en preflight

- Basis is `origin/main` (bij het schrijven `6d03290`). De lokale checkout `fix/functional-audit-core` loopt achter: daar ontbreekt bijvoorbeeld `macos/Services/PersonalCorrections.swift`. Alle regelnummers in dit plan zijn gecontroleerd tegen `origin/main`.
- Maak een nieuwe worktree `feat/lerende-context` vanaf `origin/main` en kopieer dit plan naar `docs/superpowers/plans/` in die worktree.
- Bij het schrijven raakt geen bestaande worktree of remote branch dit onderwerp (`git worktree list`: pilot, windows-audit290, cloudstt, macos-parity, notulekwaliteit). Controleer dit opnieuw vóór Taak 1, en zeker `feat/notulekwaliteit` op wijzigingen in de notuleprompt van `RecordingViewModel.swift`.

## Beslissingen

1. De schakelaar "Transcriptie op apparaat" staat alleen bij Cloud. Bij Lokaal is er nooit live tekst.
2. "Eigen termen" gaat op in de Woordenlijst. Een regel bestaat uit: juiste term, optioneel varianten, optioneel toelichting (max. 200 tekens) en een profielbereik.
3. De Woordenlijst krijgt een eigen instellingenpagina met een doorzoekbare tabel: Term · Herkend als · Toelichting · Profiel · Aan, gesorteerd A-Z, met een teller.
4. Na de notule volgt een aparte AI-stap die termen en personen voorstelt in een balk boven de notule, met Toevoegen en Negeren. Genegeerde voorstellen komen niet terug.
5. Nieuwe personen komen alleen via een voorstel in de lijst. Bestaande personen worden automatisch aangevuld met gesprekslink, soort meeting, onderwerpen en taken. Een afwijkende functie of organisatie en een nieuwe alias gaan via een voorstel.
6. Elke persoon krijgt het veld "Taken en verantwoordelijkheden": zelf in te vullen en door de AI aan te vullen met wat in een gesprek expliciet gezegd is. Het gaat mee als context zodat acties bij de juiste persoon landen.
7. Versiebeheer voor elke wijziging aan een persoon of woordenlijstregel: momentopname vóór de wijziging, met bron en herstel, maximaal 50 versies per item.
8. Geen door de AI geschreven samenvatting per persoon.
9. Windows krijgt hetzelfde (woordenlijst v2, taken, contextblok, voorstellen, geschiedenis). De schakelaar bestaat op Windows niet.

## Global Constraints

- UI-teksten Nederlands en zonder em-dash; code en comments Engels. `@Observable`, `async/await`, `TS.*`-tokens, `Color.brand*`.
- Het woordenlijstbestand blijft één JSON-formaat voor macOS en Windows. Versie 2 leest versie 1 zonder verlies.
- SwiftData krijgt alleen `AppSchemaV4` met `PersonProfile.responsibilities: [String] = []`, lightweight zoals V2 naar V3. Geen nieuwe `@Model`.
- `TranscriptsView.swift` (2484 regels) en `RecordingViewModel.swift` (1844): nieuwe code in eigen bestanden, in deze twee bestanden alleen aanroepregels.
- Whisper-prompt: maximaal 30 termen (224-token-budget). Contextblok voor de notule-AI: 6.000 tekens voor gehoste providers en lokale Ollama/LM Studio, 1.200 voor Apple Intelligence.
- De AI-stap draait alleen voor notules die in de app gemaakt zijn (verwerking Lokaal), niet bij Apple Intelligence en niet bij transcripties boven 64.000 tekens. Faalt de stap, dan alleen een logregel, niets zichtbaars.
- Zware builds via `heavy run --label <naam> --`. Testen met scheme `ThoughtVault`, destination `platform=macOS`.
- Gedeelde testopdracht, hierna `$XT`: `heavy run --label lerende-context -- xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS'`

## Review Focus

1. **Bestaande `personal-corrections.json` versie 1 met regels.** Na de update werken alle regels, toelichting leeg. Test: Taak 2 `testLoadsVersion1DocumentWithoutNotes`.
2. **Voornaamvoorstel bij twee bekende personen** ("Jan" naast "Jan de Vries" en "Jan Smit"). Geen automatische koppeling, alleen een keuzevoorstel. Test: Taak 6 `testAmbiguousFirstNameIsNotAutoLinked`.
3. **Kapotte of halve JSON uit de AI** (code fences, tekst ervoor). Geen crash, nul voorstellen. Test: Taak 5 `testParseStripsFencesAndLeadingText`, `testParseInvalidJSONReturnsEmpty`.
4. **Herstel van een oude versie terwijl er een nieuwere is.** Herstel maakt een nieuwe versie, er gaat niets verloren. Test: Taak 3 `testRestoreCreatesNewVersionAndKeepsNewer`.
5. **Het store-vangnet `moveStoreAside` (`LocalTranscriptStore.swift`) mag bij V4 niet afgaan.** Een V3-store met personen opent met alle data. Test: Taak 3 `testV3StoreWithPeopleOpensUnderV4`.

---

## Fase A: schakelaar en woordenlijst (los te leveren)

### Taak 1: Schakelaar alleen bij Cloud, geen live tekst bij Lokaal

**Files:**
- Modify: `macos/Services/OnDeviceTranscriber.swift:394` (`LiveTranscriptionPolicy`)
- Modify: `macos/ViewModels/RecordingViewModel.swift:1347` (`startLiveTranscriptionIfEnabled`) en `:1393` (`statusText`-aanroep)
- Modify: `macos/Views/SettingsView+Verwerking.swift:234`, de iOS-sectie in `macos/Views/SettingsView.swift`, `macos/Views/RecordingView+iOS.swift:331-345`, `macos/Views/RecordingView+Studio.swift:565`
- Create: `ThoughtVaultTests/LiveTranscriptionPolicyTests.swift`

**Interfaces:**
- Produces: `LiveTranscriptionPolicy.isEnabled(preferred: Bool, available: Bool, localMode: Bool) -> Bool`

- [ ] **Step 1: Failing test** `testLiveTranscriptionDisabledInLocalMode`:
  ```swift
  XCTAssertFalse(LiveTranscriptionPolicy.isEnabled(preferred: true, available: true, localMode: true))
  XCTAssertTrue(LiveTranscriptionPolicy.isEnabled(preferred: true, available: true, localMode: false))
  XCTAssertFalse(LiveTranscriptionPolicy.isEnabled(preferred: false, available: true, localMode: false))
  ```
- [ ] **Step 2:** `$XT -only-testing:ThoughtVaultTests/LiveTranscriptionPolicyTests`. Verwacht: build-fout, `isEnabled` bestaat niet.
- [ ] **Step 3:** Implementeer `isEnabled` en gebruik het in `startLiveTranscriptionIfEnabled` en bij de `statusText`-aanroep (bij Lokaal geen status "live tekst staat uit", want er is geen schakelaar meer).
- [ ] **Step 4:** Verberg de schakelaar bij Lokaal: voorwaarde `&& !isLocalProcessing` op macOS (`SettingsView+Verwerking.swift:234`) en iOS (`SettingsView.swift`), en de live-tekstweergave in `RecordingView+iOS.swift:331-345` en `RecordingView+Studio.swift:565` alleen tonen als `isEnabled` waar is.
- [ ] **Step 5:** Test opnieuw: PASS. Schermafbeeldingen van Instellingen > Verwerking bij Lokaal en bij Cloud.
- [ ] **Step 6:** Commit `fix(instellingen): schakelaar transcriptie op apparaat alleen bij Cloud`.

### Taak 2: Woordenlijst v2 en contextblok (macOS)

**Files:**
- Modify: `macos/Services/PersonalCorrections.swift` (`PersonalCorrection` r.3, `CorrectionDocument` r.17)
- Modify: `macos/Services/LocalTranscriber.swift:22` (`PersonalVocabulary`)
- Modify: `macos/ViewModels/RecordingViewModel.swift:927-928` en `:1056-1057` (twee aanroepen worden één)
- Modify: `ThoughtVaultApp` init-task (eenmalig `migrateLegacyTerms()`)
- Create: `ThoughtVaultTests/PersonalCorrectionsTests.swift`

**Interfaces:**
- Produces:
  - `PersonalCorrection.note: String?` (max. 200 tekens, geen `\r`, `\n`, `<`, `>`). `variants` mag leeg zijn.
  - `CorrectionDocument { version: Int = 2; entries: [PersonalCorrection]; dismissed: [String] = [] }`. `load` accepteert versie 1 en 2; `save` schrijft versie 2.
  - `struct PersonContext: Sendable { name: String; role: String; organization: String; responsibilities: [String]; aliases: [String] }`
  - `PersonalCorrections.contextBlock(entries: [PersonalCorrection], people: [PersonContext], transcript: String, profileId: String?, maxCharacters: Int) -> String`
  - `PersonalCorrections.contextBudget(for provider: NotulenProvider) -> Int` (6000, of 1200 voor Apple Intelligence; `NotulenProvider` uit `macos/Models/Models.swift:173`)
  - `PersonalVocabulary.migrateLegacyTerms()`

- [ ] **Step 1: Failing tests** in `PersonalCorrectionsTests`:
  - `testLoadsVersion1DocumentWithoutNotes`: fixture `{"version":1,"entries":[{...canonical "Yinga", variants ["Jengo"]...}]}` laadt met één regel, `note == nil`, `dismissed == []`; na `save` staat `"version":2` in het bestand.
  - `testEntryWithoutVariantsIsValid`: regel met `variants: []` is geldig en overleeft save/load.
  - `testNoteLongerThan200IsRejected`: 201 tekens geeft een validatiefout, 200 niet.
  - `testContextBlockPrioritisesTermsFoundInTranscript`: twee regels, transcriptie bevat alleen "Jengo", `maxCharacters: 120`; resultaat bevat "Yinga", niet de andere term.
  - `testContextBlockListsPeopleWithResponsibilities`: resultaat bevat letterlijk `Jan de Vries (schade-expert, Achmea), taken: rapport opstellen`.
  - `testMigrateLegacyTermsCreatesEntriesOnce`: `UserDefaults`-sleutel `personalVocabulary` = `"Yinga, Prezent"`; twee keer migreren geeft precies twee regels zonder varianten en de sleutel is weg.
- [ ] **Step 2:** `$XT -only-testing:ThoughtVaultTests/PersonalCorrectionsTests`: FAIL.
- [ ] **Step 3:** Implementeer. Blokformaat (vaste kop, exact deze tekst):
  ```
  Woordenboek en personen (juiste spelling en betekenis; corrigeer verkeerd herkende varianten stil, voeg geen feiten toe; koppel acties aan de persoon wiens taak het is):
  - Yinga (ook gehoord als: Jengo): bedrijf van Michel, AI-advies
  - Jan de Vries (schade-expert, Achmea), taken: rapport opstellen
  ```
  Volgorde van regels: eerst wat in de transcriptie voorkomt (term, variant of alias, hoofdletterongevoelig), dan regels voor `profileId`, dan de nieuwste. Hele regels afkappen op `maxCharacters`, nooit halverwege. `contextBlock` vervangt `PersonalVocabulary.promptInstruction()` en `PersonalCorrections.prompt(_:profileId:)` op beide plekken in `RecordingViewModel`; personen komen uit `PersonDirectoryService.directoryPeople()`. De Whisper-prompt houdt de grens van 30 termen. Verwijder de vervangen functies als ze geen aanroepers meer hebben.
- [ ] **Step 4:** Tests: PASS. Daarna de volledige suite `$XT`. Het bekende falen van `testAllFourHostedProvidersAreOffered` apart benoemen.
- [ ] **Step 5:** Commit `feat(woordenlijst): toelichting, lege varianten en contextblok voor de notule-AI`.

### Taak 3: Geschiedenis (woordenlijst en personen) en schema V4

**Files:**
- Create: `macos/Services/ContextHistory.swift`
- Modify: `macos/Models/PersonProfile.swift` (`var responsibilities: [String] = []`)
- Modify: `macos/Models/AppMigrationPlan.swift` (`AppSchemaV4`, stage `v3ToV4` lightweight)
- Modify: `macos/Services/PersonDirectoryService.swift` (nieuwe `update(_:source:mutate:)`), `macos/Services/PersonalCorrections.swift`
- Modify: schrijfplekken in `macos/Views/PersonEditView.swift` en `PeopleDirectoryView`
- Create: `ThoughtVaultTests/ContextHistoryTests.swift`
- Modify: `ThoughtVaultTests/MigrationTests.swift` (bestaand)

**Interfaces:**
- Produces:
  - `enum HistoryKind: String, Codable { case person, term }`
  - `struct HistoryEntry: Codable, Identifiable { let id: UUID; let kind: HistoryKind; let itemId: String; let date: Date; let source: String; let snapshotJSON: String }`. `source` is `"handmatig"`, `"gesprek:<taskId>"`, `"voorstel:<taskId>"` of `"herstel"`.
  - `enum ContextHistory { static let maxPerItem = 50; static func record<T: Encodable>(kind: HistoryKind, itemId: String, source: String, snapshot: T) throws; static func versions(kind: HistoryKind, itemId: String) -> [HistoryEntry] }` (nieuwste eerst). Bestand: `ApplicationSupport/ThoughtVault/context-history.json`, atomisch geschreven. Bestandslocatie injecteerbaar voor tests.
  - `struct PersonSnapshot: Codable` met alle bewerkbare velden van `PersonProfile`, `init(_ person: PersonProfile)` en `apply(to: PersonProfile)`.
  - `PersonDirectoryService.update(_ person: PersonProfile, source: String, mutate: (PersonProfile) -> Void) throws`: snapshot vastleggen, muteren, opslaan.
  - `PersonDirectoryService.restore(_ entry: HistoryEntry, to person: PersonProfile) throws`: via `update(source: "herstel")`.
  - `PersonalCorrections.saveRecording(_ entry: PersonalCorrection, source: String) throws` en `restore(_ entry: HistoryEntry) throws`.

- [ ] **Step 1: Failing tests:**
  - `testRecordKeepsAtMost50PerItem`: 55 keer `record` voor één item geeft 50 versies; een tweede item blijft onaangetast.
  - `testRestoreCreatesNewVersionAndKeepsNewer`: drie wijzigingen, herstel van de oudste, dan vier versies; `versions(...).first?.source == "herstel"` en de vorige nieuwste staat er nog.
  - `testV3StoreWithPeopleOpensUnderV4` (in `MigrationTests`): maak een store met `AppSchemaV3` en twee personen, sluit, open met het huidige migratieplan; twee personen met `responsibilities == []` en het store-bestand staat nog op dezelfde plek (geen `moveStoreAside`).
- [ ] **Step 2:** `$XT -only-testing:ThoughtVaultTests/ContextHistoryTests -only-testing:ThoughtVaultTests/MigrationTests`: FAIL.
- [ ] **Step 3:** Implementeer. Elke schrijfactie op een persoon loopt via `PersonDirectoryService.update(_:source:mutate:)` met `source: "handmatig"` vanuit de UI; elke woordenlijstwijziging via `saveRecording`. Geen losse `record`-aanroepen in views.
- [ ] **Step 4:** Tests: PASS, daarna `$XT`.
- [ ] **Step 5:** Commit `feat(context): versiebeheer voor personen en woordenlijst, PersonProfile.responsibilities`.

### Taak 4: Woordenlijstpagina, takenveld en geschiedenis-UI (macOS/iOS)

**Files:**
- Modify: `macos/Views/SettingsView+Studio.swift` (`SettingsTab.woordenlijst`, titel "Woordenlijst", icoon `character.book.closed`)
- Rewrite: `macos/Views/PersonalCorrectionsView.swift` (tabel)
- Modify: `macos/Views/SettingsView+Verwerking.swift`: verwijder de woordenlijstregel bij r.24 en de "Eigen termen"-rijen r.291-300
- Modify: `macos/Views/SettingsView.swift:634-645` (iOS "Eigen termen" en footertekst weg)
- Modify: `macos/Views/PersonEditView.swift` (secties "Taken en verantwoordelijkheden" en "Geschiedenis")
- Create: `macos/Views/HistoryListView.swift`
- Modify: `CorrectionFields` (gebruikt door de woordcorrectiesheet bij `TranscriptsView.swift:1118`): toelichtingsveld

**Interfaces:**
- Consumes: Taak 2 `PersonalCorrection.note`; Taak 3 `ContextHistory.versions`, `PersonDirectoryService.restore`, `PersonalCorrections.restore`.
- Produces: `HistoryListView(kind: HistoryKind, itemId: String, onRestore: (HistoryEntry) -> Void)`

- [ ] **Step 1:** macOS: `Table` met kolommen Term · Herkend als · Toelichting · Profiel · Aan, A-Z, `.searchable` en teller "N termen". Rij aanklikken opent een bewerkpaneel met `CorrectionFields`, toelichting en `HistoryListView`. iOS: `List` met dezelfde gegevens per rij.
- [ ] **Step 2:** Persoon: takenlijst met toevoegen en verwijderen; Geschiedenis met per versie datum, bron en de knop Herstel.
- [ ] **Step 3:** Bouw (`heavy run --label lerende-context -- xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug -allowProvisioningUpdates build`): BUILD SUCCEEDED. Schermafbeeldingen van de Woordenlijst met 0 en met 40 regels en van een persoon met taken en geschiedenis.
- [ ] **Step 4:** Commit `feat(woordenlijst): eigen pagina met doorzoekbare tabel, taken en geschiedenis per persoon`.

## Fase B: AI-voorstellen na de notule

### Taak 5: `LLMService.complete` en de contextstap

**Files:**
- Modify: `macos/Services/LLMService.swift` (protocol r.30; `OpenAICompatibleLLMService` via `streamChatCompletion` r.384; stubs gooien `LLMError.providerUnavailable`)
- Modify: `macos/Services/AnthropicLLMService.swift`, `macos/Services/AppleFoundationModelService.swift`
- Create: `macos/Services/ContextSuggestions.swift`
- Modify: `RecordingViewModel.swift`: na de notule-opslag bij ~939 en ~1063 één aanroepregel
- Create: `ThoughtVaultTests/ContextSuggestionsTests.swift`

**Interfaces:**
- Consumes: Taak 2 `contextBlock`, `CorrectionDocument.dismissed`.
- Produces:
  - `func complete(systemPrompt: String, userMessage: String) async throws -> String` op `LLMService`
  - `struct TermSuggestion: Codable, Hashable { heard: String; canonical: String; note: String }`
  - `struct PersonSuggestion: Codable, Hashable { name: String; role: String; organization: String; responsibilities: [String]; topics: [String]; heardAs: [String]; matchedPersonId: String? }`
  - `struct ContextSuggestionSet: Codable { terms: [TermSuggestion]; people: [PersonSuggestion] }`
  - `ContextSuggestions.parse(_ raw: String, transcript: String, entries: [PersonalCorrection], dismissed: [String]) -> ContextSuggestionSet`
  - `ContextSuggestions.runInBackground(taskId: String, transcript: String, participants: [Participant], provider: NotulenProvider)`
  - Opslag `ApplicationSupport/ThoughtVault/context-suggestions.json` (`[taskId: ContextSuggestionSet]`) met `load(taskId:)`, `remove(taskId:item:)` en `dismiss(key:)`; de sleutel gaat naar `CorrectionDocument.dismissed`.
  - `Notification.Name.contextSuggestionsUpdated` met `taskId` in `userInfo`.

- [ ] **Step 1: Failing tests:**
  - `testParseStripsFencesAndLeadingText`: `"Hier is het:\n```json\n{...één term...}\n```"` geeft één term.
  - `testParseInvalidJSONReturnsEmpty`: `"{\"terms\": [ {"` geeft een lege set, geen throw.
  - `testParseDropsTermWhoseHeardTextIsNotInTranscript`
  - `testParseDropsAlreadyKnownAndDismissed`: term met bestaande canonical, en term waarvan de sleutel in `dismissed` staat, vallen allebei weg.
  - `testParseCapsAtEightTermsAndEightPeople`: 12 en 12 in, 8 en 8 uit.
- [ ] **Step 2:** `$XT -only-testing:ThoughtVaultTests/ContextSuggestionsTests`: FAIL.
- [ ] **Step 3:** Implementeer. De prompt vraagt alleen JSON in de vorm van `ContextSuggestionSet` en krijgt het contextblok, de deelnemers en de transcriptie mee. Regels in de prompt: alleen personen die in het gesprek een rol spelen; functie en taken alleen als ze expliciet genoemd worden; `heard` letterlijk zoals in de transcriptie. Volgorde: notule opslaan, dan `Task.detached(priority: .utility)`, daarna de notificatie. Skip-regels uit Global Constraints in `runInBackground` zelf. Dismiss-sleutel: `term:<heard>→<canonical>` of `person:<name>`, kleine letters.
- [ ] **Step 4:** Tests: PASS, daarna `$XT`.
- [ ] **Step 5:** Eén echte aanroep op de schadebezoek-transcriptie met `mistral-large-4` (scratch-script, niet in de repo). Verwacht: minstens "SRC/RSC" als term of een persoon met de rol schade-expert. Toon de ruwe uitvoer.
- [ ] **Step 6:** Commit `feat(context): AI-stap stelt na de notule termen en personen voor`.

### Taak 6: Personen koppelen en automatisch aanvullen

**Files:**
- Create: `macos/Services/PersonMatcher.swift`
- Modify: `macos/Models/Participant.swift` (`var personId: String? = nil`, decodeert oude JSON zonder het veld)
- Modify: `macos/Services/ContextSuggestions.swift` (`runInBackground` roept matcher aan)
- Modify: `macos/Views/PersonEditView.swift` (sectie "Gesprekken")
- Create: `ThoughtVaultTests/PersonMatcherTests.swift`

**Interfaces:**
- Consumes: Taak 3 `PersonSnapshot`, `PersonDirectoryService.update(_:source:mutate:)`; Taak 5 `PersonSuggestion`.
- Produces:
  - `enum MatchResult: Equatable { case existing(id: String), ambiguous([String]), new }`
  - `PersonMatcher.match(_ s: PersonSuggestion, in people: [PersonSnapshot]) -> MatchResult`: exacte naam of alias (hoofdletterongevoelig) geeft `existing`; alleen een voornaam telt als die uniek is, anders `ambiguous`.
  - `PersonMatcher.autoApply(_ s: PersonSuggestion, to id: String, profileName: String, taskId: String) throws -> PersonSuggestion?`: voegt `profileName` toe aan `meetingTypes`, `topics` aan `expertiseTags` en `responsibilities` aan `responsibilities`, zonder dubbelen (hoofdletterongevoelig), via `update(source: "gesprek:<taskId>")`. Geeft een restvoorstel terug bij afwijkende functie of organisatie of een nieuwe alias, anders `nil`.

- [ ] **Step 1: Failing tests:** `testExactNameMatches`, `testAliasMatches`, `testAmbiguousFirstNameIsNotAutoLinked` ("Jan" met "Jan de Vries" en "Jan Smit" geeft `.ambiguous` met beide ids), `testAutoApplyAddsResponsibilitiesWithoutDuplicates` ("Rapport opstellen" naast bestaand "rapport opstellen" blijft één), `testAutoApplyNeverOverwritesRoleButReturnsProposal` (rol blijft, restvoorstel heeft de nieuwe rol), `testAutoApplyRecordsHistoryEntry` (één versie met `source == "gesprek:T1"`).
- [ ] **Step 2:** `$XT -only-testing:ThoughtVaultTests/PersonMatcherTests`: FAIL.
- [ ] **Step 3:** Implementeer. `runInBackground` roept `autoApply` aan voor elke `existing`, zet `personId` op de deelnemers van de transcriptie, en bewaart alleen restvoorstellen, `ambiguous` en `new` in de voorstellenopslag.
- [ ] **Step 4:** Persoonsdetail, sectie "Gesprekken": datum en titel van transcripties met een deelnemer waarvan `personId == person.id`.
- [ ] **Step 5:** Tests: PASS, daarna `$XT`.
- [ ] **Step 6:** Commit `feat(personen): personen uit gesprekken koppelen en profielen automatisch aanvullen`.

### Taak 7: Voorstellenbalk boven de notule

**Files:**
- Create: `macos/Views/ContextSuggestionBar.swift`
- Modify: `macos/Views/TranscriptsView.swift`: één regel boven de notule-weergave plus `.onReceive` op `contextSuggestionsUpdated`

**Interfaces:**
- Consumes: Taak 5 opslag en `dismiss(key:)`; Taak 6 `MatchResult`; bestaande `applyWordCorrection(remember: true)` en `PersonEditView`.
- Produces: `ContextSuggestionBar(taskId: String)`

- [ ] **Step 1:** Ingeklapt: teller ("2 termen, 1 persoon"). Uitgeklapt per term: `heard → canonical`, toelichting, Toevoegen en Negeren. Toevoegen opent de bestaande woordcorrectiesheet met `variants: [heard]` en `note`; Opslaan corrigeert via `applyWordCorrection(remember: true)` direct deze notule.
- [ ] **Step 2:** Per persoon: naam, functie, organisatie, taken. Nieuw: Toevoegen opent `PersonEditView` vooraf ingevuld (opslaan met `source: "voorstel:<taskId>"`). Restvoorstel: Bijwerken. `ambiguous`: keuze "Is dit Jan de Vries of Jan Smit?". Altijd Negeren. Na elke actie verdwijnt het item; genegeerde items komen niet terug.
- [ ] **Step 3:** Bouw: BUILD SUCCEEDED. Schermafbeeldingen van de balk ingeklapt en uitgeklapt op 1280 en 1920 breed.
- [ ] **Step 4:** Commit `feat(notule): balk met term- en persoonsvoorstellen`.

## Fase C: Windows-pariteit

### Taak 8: Windows woordenlijst v2, taken, context, voorstellen en geschiedenis

**Files:**
- Modify: `windows/src/services/personalCorrections.ts`, `windows/src/stores/personalCorrectionsStore.ts`, `windows/src/components/settings/PersonalCorrections.tsx` (tabel), `windows/src/stores/personProfileStore.ts`, `windows/src/stores/peopleDirectoryStore.ts` (`responsibilities`), `windows/src/pages/PersonEditModal.tsx`, `windows/src/services/llm.ts` (`correctionPrompt` wordt `contextBlock`, plus `complete`), `windows/src/services/localPipeline.ts`
- Create: `windows/src/services/contextHistory.ts`, `windows/src/services/contextSuggestions.ts`, `windows/src/components/transcripts/ContextSuggestionBar.tsx`, en de bijbehorende `*.test.ts`

**Interfaces:**
- Consumes: hetzelfde JSON-formaat, dezelfde kopregel van het contextblok, dezelfde prompttekst en dezelfde dismiss-sleutels als macOS (Taak 2, 3, 5, 6).

- [ ] **Step 1:** Port de tests uit Taak 2, 3, 5 en 6 naar vitest, met dezelfde namen in camelCase en dezelfde fixtures, waaronder de v1-JSON. De SwiftData-migratietest heeft geen Windows-tegenhanger.
- [ ] **Step 2:** `cd windows && npx vitest run`: FAIL.
- [ ] **Step 3:** Implementeer. Geen live-tekstschakelaar toevoegen.
- [ ] **Step 4:** `npx vitest run` en `npx tsc --noEmit`: PASS.
- [ ] **Step 5:** Commit `feat(windows): woordenlijst v2, taken, contextvoorstellen en geschiedenis`.

### Taak 9: Docs

- [ ] **Step 1:** Volgende vrije DEC-nummer op de remote bepalen (`git fetch && git show origin/main:docs/DECISIONS.md | grep -o 'DEC-0[0-9]*' | sort -u | tail -1`; bij het schrijven DEC-059, dus vermoedelijk DEC-060). Leg vast: woordenlijst v2, contextblok met budget, AI-stap, regels voor personen, geschiedenis in JSON in plaats van een `@Model`, schema V4.
- [ ] **Step 2:** `docs/ARCHITECTURE.md`, sectie "Notulegeneratie (lokaal)": contextblok en contextstap. Eén regel in `docs/CHANGELOG.md`. Anti-slop-hook moet schoon zijn.
- [ ] **Step 3:** Commit `docs: lerende context (DEC-0xx)`.

## Verificatie (end-to-end)

1. `$XT`: alle nieuwe tests groen; het bekende falen van `testAllFourHostedProvidersAreOffered` apart benoemd.
2. `cd windows && npx vitest run`: groen.
3. Handmatig in een geïnstalleerde build. Eerst een backup van `/Applications/ThoughtVault.app` en een seintje aan Michel voor de app afgesloten wordt.
   - (a) Oude "Eigen termen" staan in de Woordenlijst.
   - (b) Het schadebezoek opnieuw notuleren met `mistral-large-4`: de balk toont voorstellen, Toevoegen corrigeert de notule direct.
   - (c) Persoon met taak "rapport opstellen" toevoegen, opnieuw notuleren: de actie over het rapport staat op die persoon.
   - (d) Na een automatische aanvulling de vorige versie herstellen via Geschiedenis.
4. Schermafbeeldingen van Instellingen > Woordenlijst, het persoonsdetail en de balk op 1920, 1440, 1280, 390 (iOS) en 320.
5. Opruimen: eigen buildmappen, scratch-scripts en screenshots buiten `docs/` weg; simulators afgesloten (`xcrun simctl list devices booted`).
