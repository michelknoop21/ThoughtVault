# iOS functionele acceptatie — 19 oktober 2026

Status: IN UITVOERING. Geen interne release of productiepublicatie.

## Bron en isolatie

Kandidaat `codex/windows-audit290`, uitgangspunt `063610e118faca1aab1a178b1f5d7d4d617fe1d4` plus de lokale soundwave- en Sparkle-correcties. Michel autoriseerde na de fysieke Wave QA-test ook volledige appacceptatie en native Windows-controle.

De volledige app wordt uit het oorspronkelijke project gebouwd met uitsluitend tijdelijke QA-configuratie-overrides: bundle-ID `com.buildmind.ThoughtVault.AcceptanceQA`, naam `ThoughtVault QA`, lege eigen entitlements, geen productie-URL-schema. Geen toegang tot gedeelde productie-keychain of iCloud-instellingen. De QA-Info.plist maakt de eigen Documents-testmap bereikbaar voor bestandsimport; deze instelling is geen productiebronwijziging. De bestaande ThoughtVault 256 blijft behouden. Deze isolatie toetst geen iCloud-sync, productie-login of upgradebehoud.

Geen DebugBridge geïnstalleerd: de iOS-QA-skill ondersteunt die bootstrap niet voor dit Xcode-project. Er is een apart XCUITest-project buiten de productiebron gemaakt, dat de volledige geïnstalleerde QA-app via echte schermacties controleert. Alle testresultaten blijven gescheiden van echte provideracceptatie. Geen macOS-app gebouwd of gestart.

## Acceptatiematrix

| Onderdeel | Bewijs/status |
|---|---|
| Gewone iOS-build + signing | PASS in eerder soundwaveverslag |
| Volledige geïsoleerde QA-app bouwen/installeren | PASS: BUILD SUCCEEDED, codesign strict PASS, exacte QA-ID en geïsoleerde keychain/iCloud-entitlements bevestigd, installatie geslaagd |
| Onboarding zonder optionele agenda-/profieltoestemming | PASS: welkom → microfoon overslaan → agenda → profiel → finish vóór opname |
| Home / Opnemen / Notulen / Taken / Instellingen | PASS: alle vijf tabs bereikbaar en geselecteerd, eigen screenshots |
| Normaal sluiten en heropenen | PASS: QA-app beëindigd/heropend, Opnemen met Start opname bereikbaar |
| Echte mic, spectrum, zacht/luid, pauze/hervat en visueel uitdoven | PASS in aparte Wave QA-host; volledige app nog OPEN |
| Opnemen → verwerken → eigen resultaat bewaren/heropenen | OPEN |
| Import / annuleerroute / onjuist bestand | OPEN |
| Providerfout / retry / behoud gedeeltelijk resultaat | OPEN |
| Export / zoeken / filteren | OPEN |
| Achtergrond / routewissel / systeem-Reduce-Motion / latency | OPEN |
| Upgrade en iCloud/account/integraties | NIET GETEST in geïsoleerde identiteit |

## Veilige fixture

Eigen synthetische Nederlandse testspraak: “Dit is een testvergadering van ThoughtVault. Alex maakt maandag het verslag. De afspraak is dat het team dinsdag de resultaten controleert. Deze opname bevat alleen verzonnen testgegevens.” 16 kHz mono WAV, SHA-256 `db8876f074c1382ef7eec2378b6fb0e17c161f83cae76f26c02283017bc486cf`. Geen privéaudio gebruikt.

## Windows — actuele toegang

Royal TSX / bestaande Dalf38 VPN op 19 oktober circa 14:26–14:27 opnieuw bekeken. Er is een eigen gemarkeerde PowerShell-tab “ThoughtVault QA 19okt” geopend; bestaande tabs/vensters behouden. Procesfilter op thoughtvault/transcript geeft geen resultaat; geen crashoorzaak uit afgeleid. Werkelijke Program Files executable rapporteert **1.0.288**. De gecorrigeerde wave zit daar nog niet in. Geen app gestart of MSI geïnstalleerd, geen gegevens gelezen of providerinstellingen gewijzigd. Private CI/pakketgate blijft geblokkeerd zolang geen herstelmelding van Billing & plans beschikbaar is; geen run herhaald of betaling aangepast.

## Lokale uitvoering

Tijdelijke testbuild en runner: `/tmp/thoughtvault-full-ios-qa-20261019/`. Opbouw van de QA-build mislukte eerst door een ongeschikte conditionele command-line buildsetting; gewone `CODE_SIGN_ENTITLEMENTS`-override gebruikt voor de correctie. Dit is een QA-aanroepfout, geen nieuwe productfout.

14:32 CEST: XCUITest-runner gebouwd (**TEST BUILD SUCCEEDED**). Fysieke teststart wacht op ontgrendelen van het toestel; Michel om ontgrendeling gevraagd. Geen vergrendeling omzeild.


## Eerste schermresultaten

`test02TabsAndRelaunch` PASS (19,777 s). `test01OnboardingWithoutOptionalPermissions` eerste poging FAIL door een notificatieprompt die de tik op Beginnen onderschepte; expliciete afhandeling van de eigen optionele notificatieprompt in de runner toegevoegd. Daarna PASS (14,158 s). Geen productcode hiervoor gewijzigd.

Een aanvullende test verwachtte aanvankelijk dat Premium model na heropenen behouden bleef. De native proef toont 1 → 0 na heropenen; de bron definieert dit als gewone sessievariabele `usePremium = false`, zonder opslagcontract. Dit is een vastgelegde observatie, geen stilzwijgend weggewerkte productfout of reden om macOS-gedrag te wijzigen. De echte persistentiecontrole gebruikt nu de bestaande AppStorage-voorkeur Transcriptie op apparaat en herstelt de oorspronkelijke testwaarde.

Het toestel vergrendelde zichzelf tussen de testrondes. Michel heeft opnieuw ontgrendeld; de runner wachtte daarbij zonder een vergrendeling te omzeilen.


## Aanvullende native controles

- `test03ModalRoutesAndSettingPersistence`: **PASS**, 27,208 s. Transcriptie op apparaat via echte toggle gewijzigd; app beëindigd/heropend; gewijzigde waarde behouden; oorspronkelijke waarde teruggezet. Opgeslagen opnames (lege eigen QA-opslag) en opnameprofielen geopend. Geen providerconfiguratie gewijzigd.
- `test05PrepareRealRecordingPermissions`: **PASS**. Eigen QA-microfoon- en spraakherkenningsrechten via de echte onboarding gegeven; opname niet automatisch gestart. QA-app daarna idle op Opnemen met Standaard-profiel en Start opname geverifieerd.
- `test04ImportOwnFixture`: tweemaal **BLOCKED in testbesturing**. Bestandskiezer en Op mijn iPhone bereikt, maar de exact benoemde QA-map wordt niet door de runner gevonden. Geen eigen bestand geselecteerd, dus geen import- of verwerkings-PASS. Geen privébestanden geopend of bestandslijsten gedumpt. Geen productcode gewijzigd op basis van deze selectorfout.
- Michel gevraagd om een veilige circa20-seconden-opname in de volledige QA-app, met uitsluitend de bekende fictieve testzin, pauze/hervat en Stop en verwerk. Tot zijn antwoord geen appherstart of nieuwe UI-run uitvoeren.

Eigen logs, testbron en expliciete eigen-appbeelden: `build/ios-acceptance-2026-10-19/` (genegeerd). Geen file-picker-failurebijlagen geëxporteerd of gepubliceerd. Geen volledige xcresultbundel gekopieerd.


## Bevestigde verwerkingsfout — Windows krijgt voorrang

Michel meldde na de eigen opname aanvankelijk “Resultaat of notulen verschijnen”. Een verse screenshot van de QA-app toonde echter nog `recording_1792413642.wav`, 17%, Transcriberen, 1 actief en nog geen notulen. De app is niet herstart. Daarna meldde Michel expliciet de fout: **“Lokale transcriptie mislukt: Model gereedmaken duurde te lang (300s). Probeer opnieuw of kies e...”**.

Status volledige opname→transcriptie→notulen: **FAIL / OPEN**, geen resultaat- of opslag-PASS. De fout valt in de modelinitialisatie van `WhisperKitTranscriber` met de bestaande 300s-grens, vóór geslaagde transcriptie. Download, Core ML-specialisatie en andere initialisatieoorzaken zijn nog niet onderscheiden; geen onbewezen hoofdoorzaak claimen en de timeout niet blind verhogen.

Michel gaf vervolgens expliciet Windows prioriteit. Geen verdere iOS-tests, appherstarts of gebruikersvragen totdat Windowswerk dat toelaat of Michel iOS hervat. Bestaande opname in QA-container behouden, geen audio gekopieerd of verwijderd.
