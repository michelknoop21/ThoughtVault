# Foutrapporten en meldingen, fase b (macOS en iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De macOS- en iOS-app schrijven een afgeschermd logbestand, sturen bij een crash of een mislukte opname, transcriptie of notule automatisch een melding naar de relay uit fase a, en laten de gebruiker zelf melden en antwoorden lezen in "Mijn meldingen".

**Architecture:** `AppLog` schrijft via een `AsyncStream` naar een `actor LogFile` in `AppEnvironment.supportDirectory/Logs`, maskeert gevoelige waarden met `LogRedact` en houdt de crashmarkering `session.open` bij. `actor SupportRelay` praat met `https://thoughtvault.yinga.ai/support` via een eigen `URLSession`, met een wachtrij van JSON-bestanden in `Logs/outbox/`. `SupportViewModel` (`@MainActor @Observable`) haakt aan op `RecordingViewModel` via een `onFailure`-closure, zoals de app nu al `updateCheckService.isBusy` koppelt, en voedt de identiteitspoort, het meldformulier, "Mijn meldingen", de Instellingen-sectie en het Help-menu.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, async/await, CryptoKit (SHA-256), OSLog `Logger`, `URLSession` met `URLProtocol`-stub in XCTest.

**Spec:** `docs/plans/2026-11-10-foutrapporten-feedbackhub.md` op branch `docs/plan-foutrapporten-feedbackhub` (lezen met `git show docs/plan-foutrapporten-feedbackhub:docs/plans/2026-11-10-foutrapporten-feedbackhub.md`). Leidend: hoofdstuk 2 (besluiten), 4 (relay-contract), 5 "Fase b" en 8 (risico's). Besluiten liggen vast.

## Global Constraints

- Basis: branch `feat/foutrapporten-macos-ios` vanaf `origin/main` in een eigen worktree (superpowers:using-git-worktrees). Nooit committen op `main`: `.githooks/post-commit` bumpt daar de versie, tagt `v*` en pusht, wat de productiepipeline start. De gedeelde werkmap `/Volumes/SSD/Projects/thoughtvault-native` niet aanraken.
- Regelnummers in dit plan komen uit de spec (1.0.311). Zoek de regel op inhoud als hij verschoven is.
- Swift 6. `@Observable`, nooit `ObservableObject`/`@Published`. async/await, geen Combine, geen completion handlers. ViewModels `@MainActor`, services `actor`.
- UI-tekst Nederlands via `Localizable.strings`: de sleutel is de Nederlandse brontekst (zie kop van `macos/Resources/nl.lproj/Localizable.strings`). Elke nieuwe sleutel in `nl.lproj` en `en.lproj`. Code en comments in het Engels.
- Geen em-dash en geen en-dash als gedachtestreepje in UI-tekst, Localizable.strings, comments of commitberichten. Dubbele punt, komma of punt.
- Ontwerp: `TS.Spacing`, `TS.Font`, `TS.Radius` (`macos/Extensions/Theme.swift`), kleuren `Color.brandPrimary`, `Color.labelPrimary` (`macos/Extensions/Color+Brand.swift`).
- Elk nieuw bronbestand onder `macos/` in beide targets `ThoughtVault` en `ThoughtVault AppStore`: één `PBXFileReference`, een groepsregel, twee `PBXBuildFile`-regels en een regel in de Sources-fase van elk target. Controle per bestand: `grep -c "<Naam>.swift in Sources" ThoughtVault.xcodeproj/project.pbxproj` geeft `4` (zoals `NetworkMonitor.swift`). Nieuwe testbestanden alleen in target `ThoughtVaultTests` (telling `2`).
- Bestanden onder ~400 regels. `RecordingViewModel.swift` (1555 regels) groeit alleen met de haakjes die Task 3 en 5 noemen; logica gaat naar `RecordingViewModel+Support.swift`.
- Testen: eerst `pgrep -f /Applications/ThoughtVault.app`. Geeft dat een PID, dan niet testen en de gebruiker vragen de app te sluiten; nooit zelf stoppen. Testcommando (zoals het projectinstructiebestand op main), altijd via de wachtrij:
  `heavy run --label tv-faseb-test -- xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination "platform=macOS" -derivedDataPath $TMPDIR/tvtest-faseb -only-testing:ThoughtVaultTests/<Klasse>/<test>`
  Volledige suite: hetzelfde zonder `-only-testing`.
- AppStore-controle na elke taak met nieuwe bestanden: `heavy run --label tv-faseb-appstore -- xcodebuild -project ThoughtVault.xcodeproj -scheme "ThoughtVault AppStore" -configuration Release -destination 'generic/platform=macOS' -derivedDataPath $TMPDIR/tvbuild-faseb build CODE_SIGNING_ALLOWED=NO` geeft `BUILD SUCCEEDED`.
- Schermafbeeldingen alleen van een build in eigen container onder bundle-ID `com.buildmind.ThoughtVault.screens`: bouwen met `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS=<eigen bestand met alleen app-sandbox, network.client, user-selected.read-write>`, daarna `PlistBuddy -c "Set :CFBundleIdentifier com.buildmind.ThoughtVault.screens"` en `codesign --force --deep --sign - --entitlements <zelfde bestand>`. Bundle-ID controleren vóór starten. Starten met `open -g` (geen focus, geen toetsen), vastleggen met `-TVDebugSnapshot <naam>` (resultaat in `~/Library/Containers/com.buildmind.ThoughtVault.screens/Data/tmp/`), venstermaat met `-TVDebugWindow 1920x1080`, `1440x900`, `1280x800`. Vensters op PID selecteren. Na afloop de app stoppen en de container `com.buildmind.ThoughtVault.screens` verwijderen.
- iOS-simulator: navigeren alleen via launch-args (`-TVDebugOpen ...`, `-AppleLanguages "(nl)"`), schermafbeelding met `xcrun simctl io <udid> screenshot`. Vóór elke start `xcrun simctl spawn <udid> defaults write com.buildmind.ThoughtVault localStoreOpenInProgress -bool NO`. Breedtes 390 en 320 voor zover een toestel die breedte heeft; ontbreekt een bruikbare runtime of breedte, dat expliciet melden. Na gebruik `xcrun simctl shutdown <udid>`, controle met `xcrun simctl list devices booted`. Nooit `shutdown all`.
- Opruimen na elke taak: eigen `-derivedDataPath`-mappen, screenshots, xcresult-bundels en de `.screens`-container.
- Relay-contract (spec hoofdstuk 4) is de interface met fase a. Basis-URL als één constante `SupportRelay.baseURL = https://thoughtvault.yinga.ai/support`. Headers `X-TV-Installation` en `X-TV-Secret` op alles behalve `POST /installations`. Tests praten nooit met een echte server.
- UserDefaults-sleutels: `supportInstallationId`, `supportName`, `supportEmail`, `supportAutoReport` (standaard `true`). Geheim in de Keychain onder `supportSecret`, niet gesynchroniseerd. Geen van deze in `SettingsSyncService.keys`.
- Commitberichten Engels, gebiedende wijs, stijl `git log origin/main` ("Add ...", "Route ..."). Geen trailers, geen `Co-Authored-By`, geen tool- of modelnamen.

## Review Focus

1. Hub-datums met milliseconden (`2026-08-02T10:00:00.000Z`): de standaard `.iso8601`-strategie van `JSONDecoder` weigert die, waardoor "Mijn meldingen" leeg blijft. Verwacht: tickets en berichten decoderen met en zonder fractie. Test in Task 4: `testDecodesHubDatesWithAndWithoutFraction`.
2. Netjes afsluiten met Cmd-Q mag bij de volgende start geen crashmelding geven. Een async `notifications(named:)`-lus loopt mogelijk niet meer vóór het proces stopt. Verwacht: de markering is weg zodra `willTerminateNotification` is gepost. Test in Task 6: `testTerminationNotificationRemovesMarkerSynchronously`.
3. Een foutzin met bestandsnaam of e-mailadres ("Bestand niet gevonden: Klant.m4a", r.1067 van `RecordingViewModel.swift`) verlaat het apparaat in `shownMessage` en `errorText`, niet alleen in het log. Verwacht: automatische meldingen krijgen dezelfde `LogRedact.scrub` als het log. Test in Task 5: `testAutoReportScrubsShownMessage`.
4. Twee leegmaakmomenten tegelijk (start en netwerk terug): actor-reentrancy over `await` laat beide rondes dezelfde melding versturen. Verwacht: één POST per melding. Test in Task 4: `testConcurrentFlushSendsOnce`.
5. De relay kent de installatie niet meer (database opnieuw opgebouwd, 401): de melding mag niet verloren gaan of eindeloos blijven hangen. Verwacht: opnieuw aanmelden met hetzelfde kenmerk en geheim, bij 409 een nieuw kenmerk, daarna één nieuwe poging. Test in Task 4: `testUnauthorizedReRegistersAndResends`.

---

### Task 1: AppLog, LogRedact, rotatie en crashmarkering

**Files:**
- Create: `macos/Services/AppLog.swift`
- Modify: `ThoughtVault.xcodeproj/project.pbxproj`
- Test: `ThoughtVaultTests/AppLogTests.swift`

**Interfaces:**
- Consumes: `AppEnvironment.supportDirectory` (`macos/App/ThoughtVaultApp.swift` r.12; wijst onder tests naar een tijdelijke map).
- Produces:
  ```swift
  struct AppLog: Sendable {
      init(category: String)
      func debug(_ message: String)    // os Logger only, never the file
      func info(_ message: String)
      func notice(_ message: String)   // same as info
      func warning(_ message: String)
      func error(_ message: String)
      func fault(_ message: String)    // same as error
      static let clickPath: AppLog     // category "Klikpad"
      static var directory: URL        // AppEnvironment.supportDirectory/Logs
      static func flush() async
      static func tail(maxBytes: Int = 1_048_576) async -> String
      static func clickPath(in log: String, limit: Int = 30) -> [String]
      static func beginSession(in directory: URL = AppLog.directory) -> SessionOutcome
      static func resumeSession(in directory: URL = AppLog.directory)
      static func setSessionStage(_ stage: String?, in directory: URL = AppLog.directory)
      static func endSession(in directory: URL = AppLog.directory)
  }
  enum SessionOutcome: Equatable, Sendable { case clean, crashed(stage: String?) }
  actor LogFile {
      static let rotateBytes = 2_621_440
      static let retention: TimeInterval = 7 * 24 * 60 * 60
      init(directory: URL)
      func append(_ line: String)
      func tail(maxBytes: Int) -> String
  }
  enum LogRedact {
      static func mask(_ value: String) -> String
      static func scrub(_ text: String) -> String
  }
  ```
  `beginSession` wijkt af van de `-> Bool` uit de spec: hij levert ook de lopende stap die de spec bij een crash meegeeft.

- [ ] **Step 1: Schrijf de falende tests in `ThoughtVaultTests/AppLogTests.swift`** (XCTest, `@testable import ThoughtVault`, elke test een eigen tijdelijke map voor `LogFile` en sessie)

```swift
func testMaskIsStableShortToken() {
    XCTAssertEqual(LogRedact.mask("Overleg Jansen"), "k-08122f")
    XCTAssertEqual(LogRedact.mask("Overleg Jansen"), LogRedact.mask("Overleg Jansen"))
    XCTAssertEqual(LogRedact.mask("anna@example.com"), "k-f7d54c")
}

func testScrubMasksEmailPathAndMediaFilename() {
    XCTAssertEqual(LogRedact.scrub("Mail anna@example.com, file /Users/anna/Documents/Klant.m4a"),
                   "Mail k-f7d54c, file k-29040c")
    XCTAssertEqual(LogRedact.scrub("Bestand niet gevonden: Klant.m4a"), "Bestand niet gevonden: k-cc794b")
    XCTAssertEqual(LogRedact.scrub("POST https://thoughtvault.yinga.ai/support/reports 201"),
                   "POST https://thoughtvault.yinga.ai/support/reports 201")
}

func testRotatesAtTwoAndAHalfMegabytes() async throws {
    let file = LogFile(directory: dir)
    let line = String(repeating: "x", count: 999) + "\n"
    for _ in 0..<2_700 { await file.append(line) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "thoughtvault.1.log").path))
    XCTAssertLessThanOrEqual(try size(of: "thoughtvault.log"), 2_621_440)
    XCTAssertLessThanOrEqual(try size(of: "thoughtvault.1.log"), 2_621_440)
}

func testRotatedFileOlderThanSevenDaysIsRemovedAtStart() throws {
    try writeRotated(ageDays: 8)
    _ = LogFile(directory: dir)
    XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "thoughtvault.1.log").path))
    try writeRotated(ageDays: 6)
    _ = LogFile(directory: dir)
    XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "thoughtvault.1.log").path))
}

func testTailIsCappedAtOneMegabyteAndStartsAtALine() async {
    let file = LogFile(directory: dir)
    for i in 0..<3_000 { await file.append(String(format: "line-%04d ", i) + String(repeating: "é", count: 495) + "\n") }
    let tail = await file.tail(maxBytes: 1_048_576)
    XCTAssertLessThanOrEqual(tail.utf8.count, 1_048_576)
    XCTAssertTrue(tail.hasPrefix("line-"))
    XCTAssertTrue(tail.hasSuffix(String(repeating: "é", count: 495) + "\n"))
    XCTAssertTrue(tail.contains("line-2999 "))
}

func testSessionMarker() {
    XCTAssertEqual(AppLog.beginSession(in: dir), .clean)
    XCTAssertEqual(AppLog.beginSession(in: dir), .crashed(stage: nil))
    AppLog.setSessionStage("transcriberen", in: dir)
    XCTAssertEqual(AppLog.beginSession(in: dir), .crashed(stage: "transcriberen"))
    AppLog.endSession(in: dir)
    AppLog.setSessionStage("notule", in: dir)   // no marker: must not create one
    XCTAssertEqual(AppLog.beginSession(in: dir), .clean)
}

func testClickPathTakesLastThirtyMessagesCappedAtEightyChars() {
    var log = (0..<40).map { "2026-11-10T09:00:00Z INFO [Klikpad] Tab \($0)" }
    log.insert("2026-11-10T09:00:00Z ERROR [RecordingVM] other", at: 20)
    log.append("2026-11-10T09:00:01Z INFO [Klikpad] " + String(repeating: "a", count: 120))
    let path = AppLog.clickPath(in: log.joined(separator: "\n"))
    XCTAssertEqual(path.count, 30)
    XCTAssertEqual(path.first, "Tab 11")
    XCTAssertEqual(path.last?.count, 80)
}

func testAppLogWritesScrubbedLinesAndSkipsDebug() async {
    let log = AppLog(category: "Test")
    log.debug("debug-only")
    log.error("mislukt voor anna@example.com\nregel twee")
    await AppLog.flush()
    let tail = await AppLog.tail()
    XCTAssertTrue(tail.contains("ERROR [Test] mislukt voor k-f7d54c regel twee"))
    XCTAssertFalse(tail.contains("debug-only"))
    XCTAssertFalse(tail.contains("anna@"))
}
```

- [ ] **Step 2: Draai de tests en zie ze falen**

Run: testcommando uit Global Constraints met `-only-testing:ThoughtVaultTests/AppLogTests`
Expected: compileerfout `cannot find 'LogRedact' in scope`.

- [ ] **Step 3: Implementeer `macos/Services/AppLog.swift`** en registreer het in beide targets

Vastgelegde keuzes:
- `mask`: `"k-" + eerste 6 hex van SHA256(utf8(value))` (CryptoKit, kleine letters).
- `scrub` in deze volgorde, elke treffer vervangen door `mask(treffer)`:
  1. paden: `(?:file://|~|(?<![\w.:/]))/(?:[^\s/"',]+/)+[^\s/"',]*` (URL's met `://` blijven staan)
  2. e-mail: `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}`
  3. mediabestandsnamen: `[^\s/"',:]+\.(?:m4a|wav|caf|mp3|mp4|mov|m4v|aac|aiff)\b` (hoofdletterongevoelig)
- Regelvorm: `"<ISO 8601 UTC> <INFO|WARN|ERROR> [<category>] <scrub(message) met \n en \r vervangen door spatie>\n"`.
- `AppLog` stuurt elke regel naar `Logger(subsystem: "com.buildmind.ThoughtVault", category:)` en (behalve `debug`) naar één statische `AsyncStream`-continuation; één consumer-task schrijft in volgorde naar `LogFile(directory: AppLog.directory)`. `flush()` stuurt een barrière met een `CheckedContinuation` door dezelfde stream en wacht tot die aan de beurt is.
- `LogFile.init` maakt de map aan en verwijdert `thoughtvault.1.log` als de wijzigingsdatum ouder is dan `retention`. `append`: past de regel niet meer onder `rotateBytes`, dan `thoughtvault.log` naar `thoughtvault.1.log` (bestaande `.1` vervangen) en nieuw beginnen. Schrijffouten slikken; loggen mag de app nooit laten falen.
- `tail`: `.1` plus huidig bestand, laatste `maxBytes` bytes, daarna alles tot en met de eerste `\n` weggooien zodat de tekst op een regel begint en geldige UTF-8 is.
- Sessie: bestand `session.open` in `directory`, inhoud is de stap (leeg = geen stap). `beginSession` leest het bestaande bestand (bestaat het: `.crashed(stage: inhoud of nil)`), en schrijft het opnieuw leeg. `resumeSession` schrijft het leeg zonder te lezen. `setSessionStage` schrijft alleen als het bestand bestaat. `endSession` verwijdert het.
- `clickPath(in:)`: regels met `" [Klikpad] "`, tekst na die marker, eerste 80 tekens, de laatste `limit`.

- [ ] **Step 4: Draai de tests en zie ze slagen**

Run: zelfde commando. Expected: `Test Suite 'AppLogTests' passed`, 8 tests.

- [ ] **Step 5: Controleer de targetregistratie**

Run: `grep -c "AppLog.swift in Sources" ThoughtVault.xcodeproj/project.pbxproj; grep -c "AppLogTests.swift in Sources" ThoughtVault.xcodeproj/project.pbxproj`
Expected: `4` en `2`. Daarna de AppStore-build uit Global Constraints: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add macos/Services/AppLog.swift ThoughtVaultTests/AppLogTests.swift ThoughtVault.xcodeproj/project.pbxproj
git commit -m "Add a masked, rotating app log with a crash marker"
```

---

### Task 2: Services naar AppLog, met de gevoelige regels

**Files:**
- Modify (declaratie `Logger(subsystem: "com.buildmind.ThoughtVault", category: X)` wordt `AppLog(category: X)`, variabelenaam blijft): `macos/Services/` Analytics, APIService, AppleFoundationModelService, AudioChunker, AudioRecorder, BiometricService, CalendarService, ContextSuggestions, GoogleAuthService, LiveActivityManager, LLMService, LocalTranscriber, LocalTranscriptStore, MeetingNotificationService, MicrosoftGraphService, NetworkMonitor, ObsidianService, OfflineQueue, OnDeviceTranscriber, PermissionManager, PersonalCorrections, PersonMatcher, VaultFolderStore, VideoCallDetectionService, WhisperModelStore
- Modify: `macos/Services/DebugLogger.swift` (r.58 `osLogger`, r.79 `error(_:category:)`), `macos/Services/CrashReporter.swift` (r.46 `recordError`)
- Test: `ThoughtVaultTests/AppLogTests.swift`

**Interfaces:**
- Consumes: `AppLog(category:)` met `debug/info/notice/warning/error/fault`, `LogRedact.mask(_:)` uit Task 1.
- Produces: niets nieuws; `DebugLogger.shared.error(_:category:)` en `CrashReporter.shared.recordError(_:context:)` landen in het logbestand.

- [ ] **Step 1: Schrijf de falende test**

```swift
func testDebugLoggerErrorLandsInLogFile() async {
    DebugLogger.shared.error("Keychain write failed for key 'x': -25308", category: "Keychain")
    await AppLog.flush()
    let tail = await AppLog.tail()
    XCTAssertTrue(tail.contains("ERROR [Keychain] Keychain write failed for key 'x': -25308"))
}
```

- [ ] **Step 2: Draai hem en zie hem falen**

Run: `-only-testing:ThoughtVaultTests/AppLogTests/testDebugLoggerErrorLandsInLogFile`
Expected: FAIL op `XCTAssertTrue`.

- [ ] **Step 3: Zet de Services om**

- In de 25 bestanden alleen de declaratie vervangen. Interpolaties met `privacy:` worden gewone interpolaties (`ContextSuggestions` r.246, `PersonalCorrections` r.51, `LocalTranscriber` r.68, `PersonMatcher` r.86 en r.103). Formaatargumenten van `OSLogMessage` (`format:`, `align:`) worden `String(format:)`. `import OSLog` weg waar niets anders in het bestand het nog gebruikt.
- `DebugLogger.error(_:category:)` schrijft via `AppLog(category: category).error(message)`; de andere niveaus van `DebugLogger` blijven ongewijzigd. `osLogger` (r.58) wordt een `AppLog`.
- `CrashReporter.recordError` en de berichtvariant (r.53, r.69) schrijven via `AppLog(category: "CrashReporter").error(...)`.
- Gevoelige regels krijgen `LogRedact.mask(...)` om de titel, bestandsnaam, deelnemer, term of het adres: `AudioChunker.swift` r.196, `GoogleAuthService.swift` r.208, `LocalTranscriber.swift` r.68 (woordenlijstterm) en r.194, `MeetingNotificationService.swift` r.103, `MicrosoftGraphService.swift` r.240, `OnDeviceTranscriber.swift` r.129, `VaultFolderStore.swift` r.166.

- [ ] **Step 4: Draai test en controle**

Run: de test uit Step 1, daarna `git grep -n 'Logger(subsystem: "com.buildmind.ThoughtVault"' -- macos/Services`
Expected: PASS; grep geeft geen uitvoer.

- [ ] **Step 5: Commit**

```bash
git add macos/Services ThoughtVaultTests/AppLogTests.swift
git commit -m "Route service logging through the masked app log"
```

---

### Task 3: ViewModels en views naar AppLog, os_log en klikpad

**Files:**
- Modify: `macos/ViewModels/AuthViewModel.swift` (r.8, r.143), `macos/ViewModels/TasksViewModel.swift` (r.10), `macos/Views/TranscriptsView.swift` (r.18)
- Modify: `macos/ViewModels/RecordingViewModel.swift` (r.9 `OSLog` wordt `AppLog(category: "RecordingVM")`; alle `os_log(`-aanroepen; actiemethoden)
- Modify: `macos/App/ContentView.swift` (r.104 `.onChange(of: selectedTab)`), `macos/Views/SettingsView+Studio.swift` (wissel van instellingentabblad)
- Test: `ThoughtVaultTests/AppLogTests.swift`

**Interfaces:**
- Consumes: `AppLog`, `AppLog.clickPath`, `AppLog.clickPath(in:)`, `LogRedact.mask` (Task 1).
- Produces: klikpadregels met vaste tekst: `Tab <rawValue>`, `Instellingen <tab>`, `Opname starten`, `Opname pauzeren`, `Opname hervatten`, `Opname stoppen`, `Opname annuleren`, `Bestand importeren`. Task 8 voegt `Melding maken geopend` en `Mijn meldingen geopend` toe.

- [ ] **Step 1: Schrijf de falende test**

```swift
@MainActor
func testRecordingActionWritesClickPath() async {
    let vm = RecordingViewModel()
    vm.resumeRecording()
    await AppLog.flush()
    XCTAssertEqual(AppLog.clickPath(in: await AppLog.tail()).last, "Opname hervatten")
}
```

- [ ] **Step 2: Draai hem en zie hem falen**

Expected: FAIL, `last` is `nil` of een andere regel.

- [ ] **Step 3: Zet om en voeg het klikpad toe**

- `os_log(fmt, log: log, type: T, args...)` wordt `log.<niveau>("...")` met interpolatie: `.info`/`.default` naar `info`, `.error` naar `error`, `.fault` naar `fault`, `.debug` naar `debug`. Op main staan 31 aanroepen (de spec noemt 39).
- Bestandsnamen en titels in die regels krijgen `LogRedact.mask(...)`: grep in het bestand op `lastPathComponent`, `filename` en `title` binnen logaanroepen (onder meer `reprocessRecording` r.1061).
- `AuthViewModel` r.143: `logger.info("Login succeeded for \(LogRedact.mask(email)).")`.
- Klikpad als eerste regel van `startRecording`, `pauseRecording`, `resumeRecording`, `stopAndUpload`, `cancelRecording` en `importAudioFile`, vóór elke guard; in `ContentView` `.onChange(of: selectedTab)` en bij de tabwissel in `SettingsView+Studio.swift`.

- [ ] **Step 4: Draai test en controles**

Run: de test uit Step 1; `git grep -n 'privacy:' -- macos`; `git grep -n 'os_log(' -- macos/ViewModels/RecordingViewModel.swift`; `git grep -n 'Logger(subsystem: "com.buildmind.ThoughtVault"' -- macos`
Expected: PASS; de drie greps geven geen uitvoer.

- [ ] **Step 5: Commit**

```bash
git add macos/ViewModels macos/Views/TranscriptsView.swift macos/Views/SettingsView+Studio.swift macos/App/ContentView.swift ThoughtVaultTests/AppLogTests.swift
git commit -m "Log view model activity and the click path to the app log"
```

---

### Task 4: SupportRelay met aanmelden, wachtrij en verzenden

**Files:**
- Create: `macos/Services/SupportModels.swift`, `macos/Services/SupportRelay.swift`
- Modify: `ThoughtVault.xcodeproj/project.pbxproj`
- Test: `ThoughtVaultTests/SupportRelayTests.swift` (met een `URLProtocol`-stub in hetzelfde bestand)

**Interfaces:**
- Consumes: `AppLog.directory`, `AppLog.tail(maxBytes:)`, `AppLog(category:)`, `LogRedact.scrub` (Task 1); `KeychainService.save(_:for:)`, `load(for:)`, `delete(for:)` (`macos/Services/KeychainService.swift`; onder tests eigen service-ID).
- Produces (`SupportModels.swift`):
  ```swift
  enum SupportStage: String, Codable, Sendable { case opnemen, transcriberen, notule, crash }
  enum SupportCategory: String, Codable, Sendable, CaseIterable { case bug = "BUG", featureRequest = "FEATURE_REQUEST", question = "QUESTION" }
  struct SupportReport: Codable, Sendable, Equatable {
      var kind: String            // "auto" | "manual"
      var category: SupportCategory
      var stage: String           // SupportStage.rawValue, "" for manual
      var shownMessage: String    // max 5000
      var errorText: String       // max 2000
      var fingerprint: String?    // auto only
      var clickPath: [String]     // max 30 x 80
      var appVersion: String
      var os: String
      var device: String
      var platform: String        // "macOS" | "iOS"
      var occurredAt: Date
      var name: String = ""       // filled at send time
      var email: String = ""      // filled at send time
      var log: String? = nil      // filled at send time, never stored in the outbox
      static func make(kind: String, category: SupportCategory, stage: String, shown: String,
                       error: String, fingerprint: String?, clickPath: [String]) -> SupportReport
  }
  struct ReportResult: Decodable, Sendable, Equatable { let ticketId: String; let ref: String; let repeated: Bool; let count: Int }
  enum SendOutcome: Equatable, Sendable { case sent(ReportResult), queued }
  struct SupportTicket: Decodable, Identifiable, Sendable, Equatable {
      struct LastMessage: Decodable, Sendable, Equatable { let senderRole: String; let createdAt: Date; let excerpt: String }
      let id: String; let ref: String; let status: String; let category: String
      let description: String; let unread: Bool; let createdAt: Date; let updatedAt: Date
      let lastMessage: LastMessage?
  }
  struct SupportMessage: Decodable, Identifiable, Sendable, Equatable { let id: String; let body: String; let senderRole: String; let createdAt: Date }
  enum SupportIdentity {
      static let installationKey = "supportInstallationId", secretKey = "supportSecret"
      static let nameKey = "supportName", emailKey = "supportEmail", autoReportKey = "supportAutoReport"
      static func isValidEmail(_ value: String) -> Bool
      static func isComplete(name: String, email: String) -> Bool
  }
  enum DeviceInfo { static var appVersion: String; static var os: String; static var device: String; static var platform: String }
  enum SupportJSON { static let decoder: JSONDecoder; static let encoder: JSONEncoder }
  ```
- Produces (`SupportRelay.swift`):
  ```swift
  enum SupportRelayError: Error, Equatable { case http(Int) }
  actor SupportRelay {
      static let baseURL = URL(string: "https://thoughtvault.yinga.ai/support")!
      static let shared = SupportRelay()
      init(baseURL: URL = SupportRelay.baseURL,
           session: URLSession = URLSession(configuration: .ephemeral),
           defaults: UserDefaults = .standard,
           keychain: KeychainService = .shared,
           outbox: URL = AppLog.directory.appending(path: "outbox"),
           logTail: @escaping @Sendable (Int) async -> String = { await AppLog.tail(maxBytes: $0) })
      func enqueue(_ report: SupportReport) throws
      func pendingReports() -> [SupportReport]
      func flush() async
      func send(_ report: SupportReport) async -> SendOutcome   // enqueue + flush, .queued if still pending
      func tickets() async throws -> [SupportTicket]                       // GET /tickets, body {"data":[...]}
      func unreadCount() async throws -> Int                               // GET /unread-count, body {"data":{"count":n}}
      func messages(ticketId: String) async throws -> [SupportMessage]     // GET /tickets/{id}/messages, {"data":[...]}
      func sendMessage(ticketId: String, body: String) async throws        // POST /tickets/{id}/messages {"body":...}
  }
  ```
  Antwoordvormen: vastgelegd in het plan van fase a (afwijking punt 2). Lijsten `{"data": [...]}`, ongelezen `{"data": {"count": n}}`.

- [ ] **Step 1: Schrijf de stub en de falende tests**

Stub `SupportStub: URLProtocol`: statische handler `(URLRequest, Data) -> (status: Int, body: Data)` of een `URLError`, optionele vertraging, en een lijst van ontvangen verzoeken achter een `OSAllocatedUnfairLock` (zoals `ThoughtVaultTests/M3GateRecorder.swift`). De body komt binnen als `httpBodyStream`, niet als `httpBody`: uitlezen. Relay per test met `URLSessionConfiguration.ephemeral` en `protocolClasses = [SupportStub.self]`, `UserDefaults(suiteName: "SupportRelayTests-<uuid>")` met `supportName = "Anna"` en `supportEmail = "anna@example.com"`, een eigen tijdelijke outbox, en `KeychainService.shared.delete(for: "supportSecret")` in `tearDown`.

```swift
func testRegistersOnceAndSignsReports() async throws {
    stub.reply(["/support/installations": (201, "{}"), "/support/reports": (201, result1)])
    try await relay.enqueue(.fixture()); await relay.flush()
    try await relay.enqueue(.fixture()); await relay.flush()
    XCTAssertEqual(stub.paths, ["/support/installations", "/support/reports", "/support/reports"])
    let reg = stub.json(0), report = stub.requests[1]
    XCTAssertEqual(report.value(forHTTPHeaderField: "X-TV-Installation"), reg["installationId"] as? String)
    XCTAssertEqual(report.value(forHTTPHeaderField: "X-TV-Secret"), reg["secret"] as? String)
    XCTAssertEqual((reg["installationId"] as? String)?.count, 36)
    XCTAssertEqual((reg["installationId"] as? String), (reg["installationId"] as? String)?.lowercased())
    XCTAssertEqual((reg["secret"] as? String)?.count, 43)   // 32 bytes, base64url, no padding
    XCTAssertNil(defaults.string(forKey: "supportSecret"))
    XCTAssertEqual(KeychainService.shared.load(for: "supportSecret"), reg["secret"] as? String)
    XCTAssertTrue(await relay.pendingReports().isEmpty)
}

func testLogIsReadAtSendTimeAndNeverStored() async throws {
    relay = makeRelay(logTail: { _ in "LOG-AT-SEND" })
    try await relay.enqueue(.fixture())
    XCTAssertFalse(try outboxText().contains("LOG-AT-SEND"))
    await relay.flush()
    XCTAssertEqual(stub.json(1)["log"] as? String, "LOG-AT-SEND")
    XCTAssertEqual(stub.json(1)["name"] as? String, "Anna")
    XCTAssertEqual(stub.json(1)["email"] as? String, "anna@example.com")
}

func testOfflineKeepsReportAndLaterFlushSends() async throws {
    stub.fail(with: URLError(.notConnectedToInternet))
    try await relay.enqueue(.fixture()); await relay.flush()
    XCTAssertEqual(await relay.pendingReports().count, 1)
    stub.reply(["/support/installations": (201, "{}"), "/support/reports": (201, result1)])
    await relay.flush()
    XCTAssertEqual(await relay.pendingReports().count, 0)
}

func testTooManyRequestsKeepsQueueAndStopsRound() async throws {
    stub.reply(["/support/installations": (201, "{}"), "/support/reports": (429, "{}")])
    try await relay.enqueue(.fixture()); try await relay.enqueue(.fixture()); await relay.flush()
    XCTAssertEqual(stub.paths.filter { $0 == "/support/reports" }.count, 1)
    XCTAssertEqual(await relay.pendingReports().count, 2)
}

func testTooLargeRetriesOnceWithSmallLogThenDrops() async throws {
    relay = makeRelay(logTail: { max in String(repeating: "a", count: min(max, 600_000)) })
    stub.reply(["/support/installations": (201, "{}"), "/support/reports": (413, "{}")])
    try await relay.enqueue(.fixture()); await relay.flush()
    let posts = stub.requests.indices.filter { stub.paths[$0] == "/support/reports" }
    XCTAssertEqual(posts.count, 2)
    XCTAssertLessThanOrEqual((stub.json(posts[1])["log"] as? String)?.utf8.count ?? .max, 262_144)
    XCTAssertEqual(await relay.pendingReports().count, 0)
}

func testBadRequestDropsReport() async throws {
    stub.reply(["/support/installations": (201, "{}"), "/support/reports": (400, "{}")])
    try await relay.enqueue(.fixture()); await relay.flush()
    XCTAssertEqual(await relay.pendingReports().count, 0)
}

func testHeldUntilIdentityIsComplete() async throws {
    defaults.removeObject(forKey: "supportEmail")
    try await relay.enqueue(.fixture()); await relay.flush()
    XCTAssertTrue(stub.paths.isEmpty)
    defaults.set("anna@example.com", forKey: "supportEmail")
    stub.reply(["/support/installations": (201, "{}"), "/support/reports": (201, result1)])
    await relay.flush()
    XCTAssertEqual(await relay.pendingReports().count, 0)
}

func testOutboxKeepsNewestFifty() async throws {
    for i in 0..<55 { try await relay.enqueue(.fixture(shown: "fout \(i)")) }
    let pending = await relay.pendingReports()
    XCTAssertEqual(pending.count, 50)
    XCTAssertEqual(pending.last?.shownMessage, "fout 54")
}

// Review Focus 5
func testUnauthorizedReRegistersAndResends() async throws {
    stub.sequence([("/support/installations", 201), ("/support/reports", 401),
                   ("/support/installations", 409), ("/support/installations", 201), ("/support/reports", 201)])
    try await relay.enqueue(.fixture()); await relay.flush()
    XCTAssertEqual(stub.paths, ["/support/installations", "/support/reports", "/support/installations",
                                "/support/installations", "/support/reports"])
    XCTAssertNotEqual(stub.json(2)["installationId"] as? String, stub.json(3)["installationId"] as? String)
    XCTAssertEqual(stub.requests[4].value(forHTTPHeaderField: "X-TV-Installation"), stub.json(3)["installationId"] as? String)
    XCTAssertEqual(await relay.pendingReports().count, 0)
}

// Review Focus 4
func testConcurrentFlushSendsOnce() async throws {
    stub.reply(["/support/installations": (201, "{}"), "/support/reports": (201, result1)], delay: .milliseconds(200))
    try await relay.enqueue(.fixture())
    async let a: Void = relay.flush(); async let b: Void = relay.flush()
    _ = await (a, b)
    XCTAssertEqual(stub.paths.filter { $0 == "/support/reports" }.count, 1)
}

// Review Focus 1
func testDecodesHubDatesWithAndWithoutFraction() async throws {
    stub.reply(["/support/tickets": (200, """
    {"data":[{"id":"c1","ref":"TV-000001","status":"WAITING_FOR_USER","category":"BUG","description":"x","unread":true,
      "createdAt":"2026-08-02T09:00:00Z","updatedAt":"2026-08-02T10:00:00.000Z",
      "lastMessage":{"senderRole":"ADMIN","createdAt":"2026-08-02T10:00:00.000Z","excerpt":"Welke site?"}}]}
    """)])
    let tickets = try await relay.tickets()
    XCTAssertEqual(tickets.first?.updatedAt, Date(timeIntervalSince1970: 1_785_664_800))
    XCTAssertEqual(tickets.first?.unread, true)
    XCTAssertEqual(tickets.first?.lastMessage?.excerpt, "Welke site?")
}

func testThreadRoutes() async throws {
    stub.reply(["/support/tickets/c1/messages": (200, #"{"data":[{"id":"m1","body":"Hoi","senderRole":"ADMIN","createdAt":"2026-08-02T10:00:00.000Z"}]}"#),
                "/support/unread-count": (200, #"{"data":{"count":3}}"#)])
    XCTAssertEqual(try await relay.messages(ticketId: "c1").first?.body, "Hoi")
    XCTAssertEqual(try await relay.unreadCount(), 3)
    try await relay.sendMessage(ticketId: "c1", body: "Dank")
    XCTAssertEqual(stub.requests.last?.httpMethod, "POST")
    XCTAssertEqual(stub.json(stub.requests.count - 1)["body"] as? String, "Dank")
    stub.reply(["/support/tickets/c2/messages": (404, "{}")])
    await XCTAssertThrowsErrorAsync(try await relay.messages(ticketId: "c2")) { XCTAssertEqual($0 as? SupportRelayError, .http(404)) }
}
```

- [ ] **Step 2: Draai de tests en zie ze falen**

Run: `-only-testing:ThoughtVaultTests/SupportRelayTests`
Expected: compileerfout `cannot find 'SupportRelay' in scope`.

- [ ] **Step 3: Implementeer `SupportModels.swift` en `SupportRelay.swift`** en registreer beide in beide targets

Vastgelegde keuzes:
- `SupportReport.make`: kapt `shownMessage` op 5000 en `errorText` op 2000 tekens, `clickPath` op de laatste 30 regels van 80 tekens; vult `DeviceInfo` en `occurredAt = Date()`. Bij `kind == "auto"` gaan `shownMessage`, `errorText` en elke klikpadregel door `LogRedact.scrub`; eigen tekst bij `manual` blijft ongemoeid.
- `DeviceInfo`: `appVersion = "<CFBundleShortVersionString> (<CFBundleVersion>)"`, `os = "<platform> <major>.<minor>.<patch>"`, `device` = `hw.model` via `sysctlbyname` op macOS en `utsname.machine` op iOS, `platform` = `"macOS"` of `"iOS"`.
- `isValidEmail`: na trimmen geen spaties, precies één `@`, niet-leeg deel ervoor, domein met een `.` die niet vooraan of achteraan staat. `isComplete`: getrimde naam niet leeg en `isValidEmail(email)`.
- `SupportJSON.decoder`: datumstrategie `.custom` met twee `ISO8601DateFormatter`s, eerst met `.withFractionalSeconds`, dan zonder. `encoder`: `.iso8601`.
- Aanmelden (lui, vóór het eerste verzoek dat headers nodig heeft): kenmerk uit defaults of nieuw `UUID().uuidString.lowercased()`; geheim uit de Keychain of 32 bytes `SecRandomCopyBytes` als base64url zonder `=`. `POST /installations` met `{"installationId","secret"}`; 200 en 201 gelden als aangemeld (vlag in het geheugen van de actor), 409 geeft een nieuw kenmerk en geheim en één nieuwe poging.
- Wachtrij: bestandsnaam `"<ms sinds 1970>-<uuid>.json"`, inhoud `SupportReport` met `log = nil`, `name` en `email` leeg. Na schrijven alleen de nieuwste 50 bestanden houden.
- `flush`: vlag `isFlushing` in de actor; staat hij aan, direct terug. Zonder volledige identiteit (`isComplete` op de defaults) niets versturen. Per bestand op naamvolgorde: naam, e-mail en `log = await logTail(1_048_576)` invullen en `POST /reports`.
  - 2xx: bestand weg.
  - 401: één keer opnieuw aanmelden (vlag resetten, zelfde kenmerk en geheim; 409 als hierboven) en opnieuw versturen.
  - 413: één keer opnieuw met `logTail(262_144)`; daarna bestand weg en `AppLog.warning`.
  - 429, 5xx of `URLError`: bestand houden en de ronde stoppen.
  - Overige 4xx: bestand weg en `AppLog.warning` met de status.
- Ticketroutes: 2xx decoderen met `SupportJSON.decoder`, anders `SupportRelayError.http(status)`.
- Geen gebruik van `APIService` (r.201 blokkeert in lokale modus).

- [ ] **Step 4: Draai de tests en zie ze slagen**

Expected: `Test Suite 'SupportRelayTests' passed`, 12 tests.

- [ ] **Step 5: Targetcontrole en AppStore-build**

Run: `grep -c` voor `SupportModels.swift` en `SupportRelay.swift` (beide `4`), `SupportRelayTests.swift` (`2`); AppStore-build `BUILD SUCCEEDED`; `git grep -n "support" -- macos/Services/SettingsSyncService.swift` geeft geen uitvoer.

- [ ] **Step 6: Commit**

```bash
git add macos/Services/SupportModels.swift macos/Services/SupportRelay.swift ThoughtVaultTests/SupportRelayTests.swift ThoughtVault.xcodeproj/project.pbxproj
git commit -m "Add the support relay client with an offline outbox"
```

---

### Task 5: SupportViewModel, vingerafdruk en de haken in RecordingViewModel

**Files:**
- Create: `macos/ViewModels/SupportViewModel.swift`, `macos/ViewModels/RecordingViewModel+Support.swift`
- Modify: `macos/ViewModels/RecordingViewModel.swift` (r.19 `recordingState`, r.1391 `updateTask`, één opgeslagen property)
- Modify: `ThoughtVault.xcodeproj/project.pbxproj`
- Test: `ThoughtVaultTests/SupportViewModelTests.swift`

**Interfaces:**
- Consumes: `SupportRelay` (`enqueue`, `pendingReports`, `send`, `tickets`, `unreadCount`, `messages`, `sendMessage`), `SupportReport.make`, `SupportStage`, `SupportCategory`, `SupportIdentity`, `SendOutcome` (Task 4); `AppLog.tail`, `AppLog.clickPath(in:)`, `AppLog.setSessionStage` (Task 1); `TaskStatus` en `RecordingState` (`macos/Models/Models.swift`).
- Produces:
  ```swift
  enum SupportPane: Hashable { case report, tickets }
  @MainActor @Observable final class SupportViewModel {
      init(relay: SupportRelay = .shared, defaults: UserDefaults = .standard)
      var unreadCount: Int
      var tickets: [SupportTicket]
      var thread: [SupportMessage]
      var pane: SupportPane
      var isAutoReportEnabled: Bool { get }   // defaults "supportAutoReport", absent = true
      func report(stage: SupportStage, shown: String, error: String) async
      func reportCrash(runningStage: SupportStage?) async
      func submit(category: SupportCategory, description: String) async -> SendOutcome
      func refreshUnread() async
      func loadTickets() async
      func openThread(_ ticket: SupportTicket) async
      func reply(_ body: String, to ticket: SupportTicket) async throws
      func startPolling() async               // refreshUnread, then every 15 minutes until cancelled
      static func fingerprint(stage: SupportStage, error: String) -> String
      static func shouldReport(_ message: String) -> Bool
      static func stage(afterFailureOf status: TaskStatus) -> SupportStage
  }
  // RecordingViewModel
  @ObservationIgnored var onFailure: ((SupportStage, String) -> Void)?
  func syncSessionStage()   // in RecordingViewModel+Support.swift
  ```

- [ ] **Step 1: Schrijf de falende tests**

```swift
func testFingerprintIgnoresDigits() {
    XCTAssertEqual(SupportViewModel.fingerprint(stage: .transcriberen, error: "WhisperKit-model laden duurde langer dan 120 s (code 3)"), "7ea3d39b266b6289")
    XCTAssertEqual(SupportViewModel.fingerprint(stage: .transcriberen, error: "WhisperKit-model laden duurde langer dan 90 s (code 17)"), "7ea3d39b266b6289")
    XCTAssertEqual(SupportViewModel.fingerprint(stage: .notule, error: "WhisperKit-model laden duurde langer dan 120 s (code 3)"), "63e4d3d1c415c47c")
}

func testUserInstructionsAreNotReported() {
    for message in ["Microfoontoestemming geweigerd. Geef toegang via Instellingen.",
                    "Opname is leeg of te kort om te verwerken.",
                    "Opname is te kort (minimaal 3 seconden). Probeer opnieuw.",
                    "Geen profiel geselecteerd. Kies een profiel en probeer opnieuw.",
                    "Geannuleerd door gebruiker."] {
        XCTAssertFalse(SupportViewModel.shouldReport(message), message)
    }
    XCTAssertTrue(SupportViewModel.shouldReport("Kon het audiobestand niet importeren."))
}

func testStageFromPreviousStatus() {
    XCTAssertEqual(SupportViewModel.stage(afterFailureOf: .generatingLocal), .notule)
    XCTAssertEqual(SupportViewModel.stage(afterFailureOf: .transcribing), .transcriberen)
    XCTAssertEqual(SupportViewModel.stage(afterFailureOf: .uploading), .transcriberen)
}

func testRecordingErrorTransitionReportsOnce() {
    let vm = RecordingViewModel(); var calls: [(SupportStage, String)] = []
    vm.onFailure = { calls.append(($0, $1)) }
    vm.recordingState = .error("Kon het audiobestand niet importeren.")
    vm.recordingState = .error("Kon het audiobestand niet importeren.")
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.0, .opnemen)
}

func testUpdateTaskErrorReportsStageOfPreviousStatus() {
    let vm = RecordingViewModel(); var calls: [(SupportStage, String)] = []
    vm.onFailure = { calls.append(($0, $1)) }
    let task = makeTask(status: .generatingLocal)   // build like RecordingViewModel+Notule.swift r.~127
    vm.addTask(task)
    vm.updateTask(task.id, status: .error, errorMessage: "Notule mislukt")
    vm.updateTask(task.id, status: .error, errorMessage: "Notule mislukt")
    XCTAssertEqual(calls.map(\.0), [.notule])
    XCTAssertEqual(calls.first?.1, "Notule mislukt")
}

func testSessionStageFollowsActiveTask() throws {
    _ = AppLog.beginSession()
    let vm = RecordingViewModel(); let task = makeTask(status: .transcribing)
    vm.addTask(task); vm.updateTask(task.id, status: .transcribing)
    XCTAssertEqual(try String(contentsOf: AppLog.directory.appending(path: "session.open"), encoding: .utf8), "transcriberen")
    vm.updateTask(task.id, status: .completed)
    XCTAssertEqual(try String(contentsOf: AppLog.directory.appending(path: "session.open"), encoding: .utf8), "")
}

// Review Focus 3
func testAutoReportScrubsShownMessage() async {
    await supportVM.report(stage: .opnemen, shown: "Bestand niet gevonden: Klant.m4a", error: "Bestand niet gevonden: Klant.m4a")
    let report = await relay.pendingReports().first
    XCTAssertEqual(report?.kind, "auto")
    XCTAssertEqual(report?.category, .bug)
    XCTAssertEqual(report?.stage, "opnemen")
    XCTAssertEqual(report?.shownMessage, "Bestand niet gevonden: k-cc794b")
    XCTAssertEqual(report?.fingerprint?.count, 16)
}

func testAutoReportOffSkipsAutomaticReports() async {
    defaults.set(false, forKey: "supportAutoReport")
    await supportVM.report(stage: .notule, shown: "Notule mislukt", error: "Notule mislukt")
    await supportVM.reportCrash(runningStage: nil)
    XCTAssertTrue(await relay.pendingReports().isEmpty)
}

func testCrashReportUsesRunningStage() async {
    await supportVM.reportCrash(runningStage: .transcriberen)
    await supportVM.reportCrash(runningStage: nil)
    let reports = await relay.pendingReports()
    XCTAssertEqual(reports.map(\.stage), ["transcriberen", "crash"])
    XCTAssertEqual(reports.map(\.errorText), ["gestopt tijdens transcriberen", "onverwacht gestopt"])
}
```

`supportVM` en `relay`: een `SupportRelay` met de stub uit Task 4 die elk verzoek met `URLError(.notConnectedToInternet)` laat falen, zodat meldingen in de outbox blijven; defaults-suite per test.

- [ ] **Step 2: Draai de tests en zie ze falen**

Run: `-only-testing:ThoughtVaultTests/SupportViewModelTests`
Expected: compileerfout `cannot find 'SupportViewModel' in scope`.

- [ ] **Step 3: Implementeer**

- `fingerprint`: `stage.rawValue + "|" + error` zonder de tekens `0` tot en met `9`, SHA-256, eerste 16 hex in kleine letters.
- `shouldReport`: `false` voor precies de vijf zinnen uit de test (r.330, r.453, r.467, r.474/r.533 en r.917). Comment boven de set: een nieuwe instructiezin moet hier worden toegevoegd.
- `stage(afterFailureOf:)`: `.generatingLocal` wordt `.notule`, elke andere status `.transcriberen`.
- `report`: niets bij `!isAutoReportEnabled` of `!shouldReport(shown)`; altijd `AppLog(category: "Support").warning(...)` met stap en fout. Anders `SupportReport.make(kind: "auto", category: .bug, stage:, shown:, error:, fingerprint: fingerprint(...), clickPath: AppLog.clickPath(in: await AppLog.tail()))`, `relay.enqueue`, daarna `Task { await relay.flush() }`.
- `reportCrash`: stage `runningStage ?? .crash`; `shown` en `error` gelijk: `"gestopt tijdens <stage>"` of `"onverwacht gestopt"`; verder als `report`.
- `submit`: `kind "manual"`, `stage ""`, `fingerprint nil`, `shown = description`, `error ""`, via `relay.send`. Altijd, ook met de schakelaar uit.
- `openThread` laadt de berichten (de relay markeert gelezen) en ververst daarna `unreadCount`. Fouten van ticketroutes naar `AppLog.warning`; lijst en teller blijven dan staan.
- `RecordingViewModel.swift`: r.19 krijgt `didSet { recordingStateDidChange(from: oldValue) }`. `updateTask` (r.1391) bewaart `let previous = activeTasks[idx].status` na de bestaande guard; na het toewijzen `taskDidChange(from: previous, to: status, message: activeTasks[idx].errorMessage)`. Plus `@ObservationIgnored var onFailure: ((SupportStage, String) -> Void)?`.
- `RecordingViewModel+Support.swift`: `recordingStateDidChange(from:)` roept `onFailure?(.opnemen, m)` bij een overgang naar `.error(m)` met `oldValue != recordingState`, en `syncSessionStage()`. `taskDidChange` roept `onFailure?(SupportViewModel.stage(afterFailureOf: previous), message ?? "")` alleen als `status == .error && previous != .error`, en daarna `syncSessionStage()`. `syncSessionStage()`: `opnemen` bij `.preparing/.recording/.paused/.stopping/.uploading`, anders de stap van de laatst toegevoegde taak met `status.isActive`, anders `nil`, via `AppLog.setSessionStage(_:)`.

- [ ] **Step 4: Draai de tests en zie ze slagen**

Expected: `Test Suite 'SupportViewModelTests' passed`, 9 tests. Daarna `-only-testing:ThoughtVaultTests/CancelRecordingTests` en `-only-testing:ThoughtVaultTests/LocalPipelineTests` blijven groen.

- [ ] **Step 5: Targetcontrole, AppStore-build, regeltelling**

Run: `grep -c` voor de twee nieuwe bronbestanden (`4`) en `SupportViewModelTests.swift` (`2`); AppStore-build; `wc -l macos/ViewModels/RecordingViewModel.swift` geeft hoogstens 1560 (1555 plus de haakjes).

- [ ] **Step 6: Commit**

```bash
git add macos/ViewModels ThoughtVaultTests/SupportViewModelTests.swift ThoughtVault.xcodeproj/project.pbxproj
git commit -m "Report failed recordings, transcriptions and minutes automatically"
```

---

### Task 6: Crash- en vastloperdetectie bij de start, koppeling in de app

**Files:**
- Create: `macos/App/MenuBarViews.swift` (verhuisd: `MenuBarContentView` en `MenuBarStatusLabel`, `ThoughtVaultApp.swift` r.154-402, zonder gedragswijziging)
- Modify: `macos/App/ThoughtVaultApp.swift`, `macos/Services/AppLog.swift`, `ThoughtVault.xcodeproj/project.pbxproj`
- Test: `ThoughtVaultTests/AppLogTests.swift`

**Interfaces:**
- Consumes: `AppLog.beginSession/resumeSession/endSession` (Task 1), `SupportViewModel` (`reportCrash`, `report`, `startPolling`, `refreshUnread`), `RecordingViewModel.onFailure` (Task 5), `SupportRelay.shared.flush()` (Task 4), `NetworkMonitor.shared.isConnected`.
- Produces:
  ```swift
  #if os(macOS)
  extension AppLog { static func endSessionOnTermination(center: NotificationCenter = .default, directory: URL = AppLog.directory) }
  #endif
  ```
  en een `SupportViewModel` in de environment van de `WindowGroup` en de `Settings`-scene.

- [ ] **Step 1: Schrijf de falende test (Review Focus 2)**

```swift
#if os(macOS)
func testTerminationNotificationRemovesMarkerSynchronously() {
    let center = NotificationCenter()
    _ = AppLog.beginSession(in: dir)
    AppLog.endSessionOnTermination(center: center, directory: dir)
    center.post(name: NSApplication.willTerminateNotification, object: nil)
    XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "session.open").path))
}
#endif
```

- [ ] **Step 2: Draai hem en zie hem falen**

Expected: compileerfout `type 'AppLog' has no member 'endSessionOnTermination'`.

- [ ] **Step 3: Implementeer**

- `endSessionOnTermination`: `center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in AppLog.endSession(in: directory) }`. Blok-observer met `queue: nil` draait synchroon in `post`; geen `notifications(named:)`-lus, die is async en loopt mogelijk niet meer vóór het proces stopt.
- Verhuis r.154-402 naar `MenuBarViews.swift` (zelfde `#if os(macOS)`), zodat `ThoughtVaultApp.swift` ruimte heeft.
- `ThoughtVaultApp`: `@State private var supportVM = SupportViewModel()`. In `init()` op macOS `AppLog.endSessionOnTermination()`. Bovenaan de tweede `.task` (die met `checkAllPermissions`): `if case .crashed(let stage) = AppLog.beginSession() { await supportVM.reportCrash(runningStage: stage.flatMap(SupportStage.init(rawValue:))) }`, daarna `recordingVM.onFailure = { stage, message in Task { await supportVM.report(stage: stage, shown: message, error: message) } }` en `await SupportRelay.shared.flush()`. Nieuwe `.task { await supportVM.startPolling() }`. `.onChange(of: NetworkMonitor.shared.isConnected)`: bij `true` `Task { await SupportRelay.shared.flush() }`. `@Environment(\.scenePhase)`: bij `.active` `Task { await supportVM.refreshUnread() }`; alleen op iOS ook `.background` naar `AppLog.endSession()` en `.active` naar `AppLog.resumeSession()` (nooit `beginSession`, dat zou de lopende sessie als crash zien).
- `.environment(supportVM)` op `RootView()` en op `SettingsView()` in de `Settings`-scene; die scene krijgt ook `.environment(updateCheckService)`.
- `TestHostApp` blijft leeg; onder tests draait niets hiervan.

- [ ] **Step 4: Draai test en build**

Run: de test uit Step 1, daarna de volledige suite, de AppStore-build en `wc -l macos/App/ThoughtVaultApp.swift`
Expected: PASS, `** TEST SUCCEEDED **`, `BUILD SUCCEEDED`, onder 400 regels. `grep -c "MenuBarViews.swift in Sources"` geeft `4`.

- [ ] **Step 5: Commit**

```bash
git add macos/App macos/Services/AppLog.swift ThoughtVaultTests/AppLogTests.swift ThoughtVault.xcodeproj/project.pbxproj
git commit -m "Detect crashes and stalled steps at launch and flush the outbox"
```

---

### Task 7: Identiteitspoort in RootView

**Files:**
- Create: `macos/Views/SupportIdentityView.swift`
- Modify: `macos/App/ThoughtVaultApp.swift` (`RootView`, r.127-139), `macos/Services/SupportModels.swift`, `macos/Resources/nl.lproj/Localizable.strings`, `macos/Resources/en.lproj/Localizable.strings`, `ThoughtVault.xcodeproj/project.pbxproj`
- Test: `ThoughtVaultTests/SupportRelayTests.swift`

**Interfaces:**
- Consumes: `SupportIdentity.nameKey/emailKey/isValidEmail/isComplete` (Task 4); het eigen profiel dat de onboarding via `LocalTranscriptStore.upsertSelfProfile` opslaat.
- Produces:
  ```swift
  extension SupportIdentity { static func showsGate(name: String, email: String, arguments: [String]) -> Bool }
  struct SupportIdentityView: View
  ```

- [ ] **Step 1: Schrijf de falende tests**

```swift
func testEmailValidation() {
    XCTAssertTrue(SupportIdentity.isValidEmail("anna@example.com"))
    XCTAssertTrue(SupportIdentity.isValidEmail(" anna@example.com "))
    XCTAssertFalse(SupportIdentity.isValidEmail("anna@example"))
    XCTAssertFalse(SupportIdentity.isValidEmail("anna example.com"))
    XCTAssertFalse(SupportIdentity.isValidEmail("anna@@example.com"))
}

func testGateShowsUntilIdentityComplete() {
    XCTAssertTrue(SupportIdentity.showsGate(name: "", email: "anna@example.com", arguments: []))
    XCTAssertTrue(SupportIdentity.showsGate(name: "Anna", email: "anna@", arguments: []))
    XCTAssertFalse(SupportIdentity.showsGate(name: "Anna", email: "anna@example.com", arguments: []))
}

#if DEBUG
func testDebugRoutesSkipOrForceTheGate() {
    XCTAssertFalse(SupportIdentity.showsGate(name: "", email: "", arguments: ["-TVDebugTab", "settings"]))
    XCTAssertTrue(SupportIdentity.showsGate(name: "Anna", email: "anna@example.com", arguments: ["-TVDebugOpen", "identity"]))
}
#endif
```

- [ ] **Step 2: Draai de tests en zie ze falen**

Expected: compileerfout `type 'SupportIdentity' has no member 'showsGate'`.

- [ ] **Step 3: Implementeer**

- `showsGate`: alleen in `#if DEBUG` naar `arguments` kijken: `-TVDebugOpen` direct gevolgd door `identity` geeft `true`; een ander argument dat met `-TVDebug` begint geeft `false` (screenshot- en testroutes, spec hoofdstuk 8). Anders `!isComplete(name:email:)`.
- `RootView`: `@AppStorage("supportName")` en `@AppStorage("supportEmail")`; eerst `SupportIdentityView()` als `showsGate(..., arguments: ProcessInfo.processInfo.arguments)`, anders de bestaande keuze `OnboardingView`/`ContentView`. `hasCompletedOnboarding` blijft onaangeroerd. De `.onChange(of: recordingVM.recordingState)` blijft op de `Group`.
- `SupportIdentityView`: naam voorvullen uit het eigen profiel (zoek de leesfunctie naast `upsertSelfProfile` in `LocalTranscriptStore.swift`; bestaat er geen, dan leeg laten). Velden "Naam" en "E-mailadres", knop "Doorgaan" uitgeschakeld tot `isComplete`; opslaan getrimd; klikpadregel `Identiteit ingevuld`. Foutregel onder het e-mailveld zodra er tekst staat die niet klopt.
- Vaste tekst (Localizable, nl als sleutel, en-vertaling erbij):
  - Titel: "Voor wie zijn de antwoorden?"
  - "Antwoorden op je meldingen verschijnen in de app en komen per e-mail."
  - "Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee."
  - "Naam", "E-mailadres", "Doorgaan", "Dit e-mailadres klopt niet."

- [ ] **Step 4: Draai de tests en zie ze slagen**

Expected: 3 nieuwe tests PASS; AppStore-build `BUILD SUCCEEDED`; `grep -c "SupportIdentityView.swift in Sources"` geeft `4`.

- [ ] **Step 5: Schermafbeeldingen**

macOS `.screens`-build (Global Constraints) met `-TVDebugOpen identity -TVDebugSnapshot identity -TVDebugWindow <maat>` op 1920x1080, 1440x900 en 1280x800. iOS-simulator met `-TVDebugOpen identity -AppleLanguages "(nl)"` op 390 en 320 breed (of melden welke breedte ontbreekt). Daarna simulator afsluiten en container verwijderen. Bewijs: de beelden tonen beide velden, de twee zinnen en een uitgeschakelde knop.

- [ ] **Step 6: Commit**

```bash
git add macos/Views/SupportIdentityView.swift macos/App/ThoughtVaultApp.swift macos/Services/SupportModels.swift macos/Resources ThoughtVaultTests/SupportRelayTests.swift ThoughtVault.xcodeproj/project.pbxproj
git commit -m "Ask for name and email before the app opens"
```

---

### Task 8: Meldformulier, Mijn meldingen en thread

**Files:**
- Create: `macos/Views/SupportViews.swift`
- Modify: `macos/App/DebugScreenshotSeed.swift` (voorbeeldmeldingen bij `-TVDebugSeed YES`), de bestaande `-TVDebugOpen`-afhandeling (zoek `TVDebugOpen` in `macos/App` en `macos/Views/Components/IOSTheme.swift`), `Localizable.strings` nl en en, `ThoughtVault.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SupportViewModel` (`pane`, `tickets`, `thread`, `unreadCount`, `submit`, `loadTickets`, `openThread`, `reply`), `SupportCategory`, `SupportTicket`, `SupportMessage`, `SendOutcome` (Task 4 en 5).
- Produces:
  ```swift
  struct SupportCenterView: View           // picker between .report and .tickets, reads SupportViewModel from the environment
  struct SupportReportForm: View
  struct SupportTicketList: View
  struct SupportThreadView: View { let ticket: SupportTicket }
  ```
  Debugroutes `-TVDebugOpen support-report`, `support-tickets`, `support-thread`.

- [ ] **Step 1: Bouw de views**

- Formulier: categorie als segmented picker ("Fout" = `.bug`, "Idee" = `.featureRequest`, "Vraag" = `.question`), meerregelig veld "Omschrijving" (max 5000, knop uit bij lege tekst), knop "Versturen". Na `.sent`: "Verstuurd. Het antwoord zie je in Mijn meldingen en in je e-mail." Na `.queued`: "Geen verbinding. De melding gaat vanzelf de deur uit zodra je weer online bent." Bij openen klikpadregel `Melding maken geopend`.
- Lijst: per ticket `ref`, eerste regel van `description`, statuslabel, `updatedAt` relatief, ongelezen-stip in `Color.brandPrimary` bij `unread`. Statuslabels: `NEW` "Nieuw", `IN_PROGRESS` "In behandeling", `WAITING_FOR_USER` "Wacht op jou", `RESOLVED` "Opgelost", `CLOSED` "Gesloten", onbekend: de ruwe waarde. Leeg: "Nog geen meldingen. Via Melding maken stuur je een fout, idee of vraag." Bij openen `loadTickets()` en klikpadregel `Mijn meldingen geopend`.
- Thread: berichten op `createdAt`, eigen berichten rechts, antwoorden (`senderRole == "ADMIN"`) links; veld "Antwoord" en knop "Stuur". Mislukt versturen: "Versturen lukte niet. Probeer het zo nog eens."
- In DEBUG met `-TVDebugSeed YES` vult `DebugScreenshotSeed` `tickets` en `thread` van de `SupportViewModel` met twee voorbeeldmeldingen (een met status `WAITING_FOR_USER` en `unread`) zonder de relay aan te roepen.

- [ ] **Step 2: Build en targetcontrole**

Run: AppStore-build en `grep -c "SupportViews.swift in Sources"`; `wc -l macos/Views/SupportViews.swift`
Expected: `BUILD SUCCEEDED`, `4`, onder 400 regels.

- [ ] **Step 3: Schermafbeeldingen**

macOS `.screens`-build met `-TVDebugSeed YES -TVDebugOpen support-report|support-tickets|support-thread -TVDebugSnapshot <naam>` op 1920x1080, 1440x900 en 1280x800; iOS-simulator met dezelfde routes op 390 en 320. Simulator afsluiten, container verwijderen. Bewijs: formulier met drie categorieën, lijst met stip en statuslabel, thread met antwoordveld.

- [ ] **Step 4: Commit**

```bash
git add macos/Views/SupportViews.swift macos/App macos/Views/Components/IOSTheme.swift macos/Resources ThoughtVault.xcodeproj/project.pbxproj
git commit -m "Add the report form, my reports and the reply thread"
```

---

### Task 9: Instellingen-sectie, klembordsheet weg

**Files:**
- Create: `macos/Views/SettingsView+Support.swift`
- Modify: `macos/Views/SettingsView.swift` (weg: r.95-118 sheet, `showBugReportSheet`, `feedbackTitle`, `feedbackDescription`; verhuisd: `feedbackSection` r.1491-1511 en `updatesSection` r.1546-1566), `macos/Views/SettingsView+iOS.swift` (r.96-103), `Localizable.strings` nl en en, `ThoughtVault.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SupportViewModel` uit de environment (Task 6), `SupportCenterView`, `SupportReportForm`, `SupportTicketList` (Task 8), `SupportIdentity` (Task 4).
- Produces: `extension SettingsView { var feedbackSection: some View; var updatesSection: some View }` in `SettingsView+Support.swift`, met dezelfde compilatievoorwaarden als nu.

- [ ] **Step 1: Verhuis en herschrijf**

- `updatesSection` ongewijzigd verhuizen (het macOS-updatedeel van fase d valt buiten dit plan).
- `feedbackSection`: knop "Melding maken", knop "Mijn meldingen" met de teller (`unreadCount > 0`), schakelaar "Foutrapporten automatisch versturen" op `@AppStorage("supportAutoReport")` met standaard `true`, met eronder de zin uit Task 7 die begint met "Gaat er iets mis", en de velden "Naam" en "E-mailadres" op `supportName`/`supportEmail` (opslaan alleen bij geldig adres). Op macOS openen de knoppen het venster uit Task 10 met het juiste `pane`; op iOS een `NavigationLink` naar `SupportReportForm` en `SupportTicketList`.
- `SettingsView+iOS.swift` r.96-103 ("Over ThoughtVault"): de meldrijen gebruiken de nieuwe `feedbackSection`.
- Het klembordsheet en zijn drie state-variabelen verdwijnen.

- [ ] **Step 2: Build en controles**

Run: AppStore-build; volledige testsuite; `git grep -n "showBugReportSheet\|feedbackTitle\|feedbackDescription" -- macos`; `wc -l macos/Views/SettingsView.swift macos/Views/SettingsView+Support.swift`
Expected: `BUILD SUCCEEDED`, `** TEST SUCCEEDED **`, grep zonder uitvoer, `SettingsView.swift` kleiner dan 1686 regels, `SettingsView+Support.swift` onder 400. `grep -c "SettingsView+Support.swift in Sources"` geeft `4`.

- [ ] **Step 3: Schermafbeeldingen**

macOS `.screens`-build met `-hasCompletedOnboarding YES -TVDebugTab settings -TVDebugSettingsTab account -TVDebugSnapshot settings-support` op 1920x1080, 1440x900 en 1280x800; iOS-simulator met `-TVDebugTab settings` (en `-TVDebugBottom YES` om naar "Over ThoughtVault" te scrollen) op 390 en 320. Simulator afsluiten, container verwijderen.

- [ ] **Step 4: Commit**

```bash
git add macos/Views/SettingsView.swift macos/Views/SettingsView+Support.swift macos/Views/SettingsView+iOS.swift macos/Resources ThoughtVault.xcodeproj/project.pbxproj
git commit -m "Move feedback settings to the relay and drop the clipboard sheet"
```

---

### Task 10: Help-menu, meldvenster en ongelezen-teller

**Files:**
- Modify: `macos/App/ThoughtVaultApp.swift` (`.commands`, nieuwe `Window`-scene), `macos/Views/Components/MainSidebar.swift` (instellingenitem), het iOS-tabblad Instellingen (zoek de `TabView` in `macos/App/ContentView.swift`), `Localizable.strings` nl en en

**Interfaces:**
- Consumes: `SupportViewModel.pane`, `unreadCount` (Task 5), `SupportCenterView` (Task 8).
- Produces:
  ```swift
  #if os(macOS)
  struct SupportCommands: Commands { let supportVM: SupportViewModel }   // in ThoughtVaultApp.swift
  #endif
  // Window("Meldingen", id: "support") hosting SupportCenterView
  ```

- [ ] **Step 1: Implementeer**

- `SupportCommands`: `CommandGroup(replacing: .help)` met "Melding maken…" (`pane = .report`) en "Mijn meldingen" (`pane = .tickets`), beide daarna `openWindow(id: "support")` via `@Environment(\.openWindow)`. `.commands { PrintCommands(); SupportCommands(supportVM: supportVM) }`.
- `Window("Meldingen", id: "support") { SupportCenterView().environment(supportVM).preferredColorScheme(.dark) }` alleen op macOS.
- Teller: in `MainSidebar` naast het instellingenitem een badge met `unreadCount` als die groter is dan 0, ook in de smalle 52px-kolom; op iOS `.badge(supportVM.unreadCount)` op het instellingentabblad.

- [ ] **Step 2: Build en regeltelling**

Run: AppStore-build; iOS-build `heavy run --label tv-faseb-ios -- xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'generic/platform=iOS' -derivedDataPath $TMPDIR/tvbuild-faseb-ios build CODE_SIGNING_ALLOWED=NO`; `wc -l macos/App/ThoughtVaultApp.swift`
Expected: twee keer `BUILD SUCCEEDED`, onder 400 regels.

- [ ] **Step 3: Schermafbeeldingen**

macOS `.screens`-build met `-TVDebugSeed YES` en een open Help-menu is niet vast te leggen zonder toetsen; leg daarom het meldvenster (`-TVDebugOpen support-tickets`) en de zijbalk met teller (`-TVDebugSeed YES -hasCompletedOnboarding YES`) vast op de drie macOS-maten, en de iOS-tabbalk met teller op 390 en 320. Het Help-menu zelf: bewijs met `git grep -n "CommandGroup(replacing: .help)" -- macos/App` en een korte handmatige controle door Michel, als open punt melden.

- [ ] **Step 4: Commit**

```bash
git add macos/App macos/Views/Components/MainSidebar.swift macos/Resources
git commit -m "Add report entries to the Help menu and an unread badge"
```

---

### Task 11: PrivacyInfo.xcprivacy

**Files:**
- Modify: `macos/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Voeg de gegevenstypen toe**

Onder `NSPrivacyCollectedDataTypes`, naast het bestaande e-mailadres: `NSPrivacyCollectedDataTypeName`, `NSPrivacyCollectedDataTypeCrashData` en `NSPrivacyCollectedDataTypeOtherDiagnosticData`, elk met `NSPrivacyCollectedDataTypeLinked` `true`, `NSPrivacyCollectedDataTypeTracking` `false` en doel `NSPrivacyCollectedDataTypePurposeAppFunctionality`.

- [ ] **Step 2: Controleer**

Run: `plutil -lint macos/PrivacyInfo.xcprivacy && plutil -p macos/PrivacyInfo.xcprivacy | grep -c "NSPrivacyCollectedDataType\(Name\|CrashData\|OtherDiagnosticData\|EmailAddress\)\""`
Expected: `OK` en `4`.

- [ ] **Step 3: Commit**

```bash
git add macos/PrivacyInfo.xcprivacy
git commit -m "Declare name and diagnostics in the privacy manifest"
```

---

### Task 12: Eindbewijs

Geen nieuwe code. Pas starten als fase a live staat (`curl -s -o /dev/null -w "%{http_code}" -X POST https://thoughtvault.yinga.ai/support/installations -H 'Content-Type: application/json' -d '{}'` geeft 4xx en geen 404 of 502).

- [ ] **Step 1: Volledige suite en builds**

Run: volledige testsuite, AppStore-build, iOS-build.
Expected: `** TEST SUCCEEDED **`, twee keer `BUILD SUCCEEDED`.

- [ ] **Step 2: Handmatig op een `.screens`-build**

1. Transcriptie laten mislukken (geen WhisperKit-model geïnstalleerd, `modelNotInstalled`) en twee keer herhalen. Hub: één `TV`-ticket met teller 2 en `thoughtvault-log.txt` (`list_tickets`, `get_ticket`).
2. App met `kill -9 <pid>` stoppen en opnieuw starten: crashmelding in de hub.
3. Netwerk uit, fout opwekken, netwerk aan: de melding komt alsnog binnen.
4. Antwoord via `reply_ticket`: de teller in de app en de thread tonen het.
5. Logbestand in de `.screens`-container nalezen: geen e-mailadres, geen absoluut pad, geen titel.
Testtickets daarna sluiten met `set_ticket_status`. Container verwijderen, simulators afsluiten (`xcrun simctl list devices booted` leeg voor eigen toestellen), eigen buildmappen in `$TMPDIR/` verwijderen.

- [ ] **Step 3: Terugmelden**

Per stap de uitvoer of het beeld, plus wat niet te bewijzen was (Help-menu, ontbrekende simulatorbreedte). Niet mergen naar `main`; dat besluit ligt bij Michel, met `git -c core.hooksPath=/dev/null merge`.

---

## Self-review

1. Dekking van de spec, fase b: AppLog met rotatie, tail, maskeren en markering (Task 1); 28 Logger-bestanden, `privacy:`-regels, `os_log`, `DebugLogger` en `CrashReporter` (Task 2, 3); gevoelige regels (Task 2, 3); SupportRelay met kenmerk, geheim, wachtrij en leegmaken bij start en netwerk (Task 4, 6); SupportViewModel met vingerafdruk, ongelezen bij start, activeren en elke 15 minuten (Task 5, 6); haken in `updateTask` en `recordingState` met de overgeslagen zinnen (Task 5); vastlopen via de stap in `session.open` (Task 5, 6); crash en `endSession` per platform (Task 6); klikpad (Task 3, 7, 8); identiteitspoort met debugvoorvulling (Task 7); formulier, lijst en thread (Task 8); Instellingen en het schrappen van het sheet (Task 9); Help-menu en teller (Task 10); privacymanifest (Task 11); handmatig bewijs en schermafbeeldingen (Task 7 tot en met 10, 12). De privacylink op het naamscherm hoort bij fase e en ontbreekt hier bewust.
2. Stappen: elke codestap noemt bestand, signatuur en de vaste waarden; bodies staan er alleen voor maskeren, vingerafdruk, rotatie, tail en de wachtrij.
3. Typen: `SupportStage`, `SupportCategory`, `SupportReport.make`, `SendOutcome`, `SessionOutcome`, `AppLog.setSessionStage(_: String?)` en `onFailure: ((SupportStage, String) -> Void)?` zijn overal gelijk gebruikt.
4. Review Focus: vijf regels, elk met een test in de taak die de code bezit (Task 4, 5, 6).
5. Verhouding: het plan legt de beslissingen vast; views staan als tekst en schermafbeelding, niet als code.
