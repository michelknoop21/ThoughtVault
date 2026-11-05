# Soundwave Windows / iOS — uitvoering 19 oktober 2026

Status: broncorrecties en geautomatiseerde vergelijking PASS; fysieke/native eindacceptatie OPEN. Geen publicatie of Windows-installatie.

## Bron en afbakening

Uitgevoerd in `/Volumes/SSD/codex-worktrees/windows-audit290/thoughtvault-native`, branch `codex/windows-audit290`, uitgangspunt `063610e118faca1aab1a178b1f5d7d4d617fe1d4`. De bestaande buildref `8c93110` bevat deze nieuwe, nog niet gecommitte wijzigingen niet. Geen nieuwe CI-run gestart.

De hoofdcheckout `/Volumes/SSD/Projects/thoughtvault-native` heeft een oudere wave. De actuele, eerder vastgelegde macOS-reference uit de auditkandidaat is gebruikt. SHA-256 van de ongewijzigde `macos/Views/Components/WaveformView.swift`: `5c3e93d2344a2e74b906be86871b846ba3189f137d685baf91afce0a6d5c9ffe`.

Gebruikte skills: `audio-reactive-waveform` inclusief beide referentiebestanden, en `siri-waveform` inclusief SwiftUI/React-implementaties. De huidige productgeometrie bepaalt de vorm; oude voorbeeldwaarden zijn niet overgenomen.

## Bereik en correcties

| Weergave | Werkelijk pad | Uitkomst |
|---|---|---|
| Windows Opnemen | RecordingPage → WaveformVisualizer, niveau en spectrum via bestaande Tauri-events | Gedeelde renderer gecorrigeerd |
| Windows widget | RecordingWidget → dezelfde renderer en dezelfde hooks | Dezelfde correctie bereikt compacte variant |
| Windows Home | HomeDecor-landschap; bewust decoratief en geen live capture | Niet vervangen door fictieve audioreactie |
| iOS Opnemen | RecordingView+iOS → IOSLiveWave → gedeelde WaveformView | Ontbrekende spectrum-provider aangesloten |
| iOS onboarding | IOSLiveWave met isActive=false | Bestaande stille variant behouden via lege standaardprovider |
| macOS Studio/widget | WaveformView + WaveConfig, bestaande audioverwerking | Bron, audiocapture, buildconfig en geïnstalleerde app ongewijzigd |

iOS gaf alleen volumehistorie door, terwijl de bestaande recorder en het viewmodel al frequentiebanden leveren. Nu krijgt de gedeelde renderer ook deze provider. Er is geen tweede microfooncapture of analyser toegevoegd. De iOS-specifieke limiet van 60 Hz is verwijderd: dezelfde renderer kan de schermcadence volgen. De wijzigingen staan uitsluitend binnen het bestaande iOS-compileblok; de gedeelde macOS-renderer is niet aangepast.

Windows bewaarde de fase in een effect dat bij hoogtewijziging opnieuw begon. De klok blijft nu bestaan over zulke wijzigingen, begint net als de Apple-reference met dt=0, en reset timing bij actief/pauze en tijdens waargenomen verborgen frames/reduced motion. Frequentie-input wordt eindig en begrensd gehouden. De gradientkleuren gebruiken nu exact dezelfde procentuele sRGB-waarden als de Swift-reference, zonder hexafronding. Bestaande gloed, lijnen, SiriWave-geometrie en lettergreephistorie behouden.

## Verificatie

- `scripts/waveform-reference.swift` compileert tegen de echte, ongewijzigde `WaveformView.swift` en `AudioEnvelopeProcessor.swift`; dit is een command-line geometriecontrole, geen macOS-appbuild/start. Uitvoer: `tests/fixtures/waveform-reference.json`.
- 36 referentiegevallen: twee hoogtes (32/240), drie cadences (30/60/120) en zes volume-/spectrumcombinaties. In totaal 1.386 gesamplede curvecoördinaten komen overeen binnen 0,00005 px. Fase na resize wordt aanvullend op alle getekende punten getoetst.
- De nieuwe Windows-pariteitstest faalt op de oorspronkelijke HEAD-renderer bij fasebehoud na resize; slaagt met de correctie. Originele bron tijdelijk getest en daarna exact hersteld naar de eigen correctie.
- Volledige Windows-frontendregressie: **42 bestanden / 111 tests PASS**. TypeScript en Vite-productiebuild PASS. Geen native Windows-build/runtimeclaim uit deze frontendresultaten.
- Aanvullende gerichte run na test op niet-eindige spectruminput: **2 bestanden / 2 tests PASS**. De bestaande rendereracceptatie omvat zacht/luid, echte reisbeweging bij constant niveau, stilte met oud spectrum, compactbereik, lage/hoge banden, eerste sample en reduced motion.
- Een eerste brede run gebruikte een oude lokale node_modules-link en miste plugin-updater. Dit is opgelost door de dependencies van de kandidaat met het bestaande lockbestand te installeren. Geen nieuwe dependency toegevoegd en geen lockbestand gewijzigd.
- De gewone iOS-simulatorbuild van het originele project faalt vóór compilatie wegens de Sparkle XCFramework, die geen iOS-library heeft. Alleen in `/tmp/thoughtvault-wave-ios-project-20261019` zijn de Sparkle-verwijzingen uit een projectkopie verwijderd. **De volledige iOS-app compileert daarin succesvol voor simulator met de echte gewijzigde bron.** Het originele Xcode-project en de macOS-pakketconfiguratie zijn ongewijzigd. Dit is geen goedkeuring van de gewone iOS-releasebouwroute.
- Deze iOS-app is geïnstalleerd en gestart op de voor QA gebootte simulator iPhone 17 Pro; de onboarding verschijnt. Geen toestemming gegeven, account ingesteld, microfoonopname gestart of bestaande gebruikersapp op Mac/Windows vervangen.
- Afzonderlijke native iOS-testhost `nl.yinga.ThoughtVault.WaveformParityQA`: compileert de echte gedeelde renderer en de uit het actuele bestand overgenomen IOSLiveWave-wrapper, met synthetisch niveau 0,6 en lage frequentieband. Native afbeelding en 18,695 s schermvideo vastgelegd. Geen microfoontoegang. Hoofdweergave en compacte golf zijn zichtbaar. Twee videoframes bij constante invoer verschillen in de golfregio (gemiddelde RGB-verandering 7,36 / 4,94 / 6,77), consistent met voortgaande beweging. Videometadata is geen gemeten 600-Hz-schermcadence.

Correctie bij vervolgonderzoek: de Simulator-GUI staat in deze Xcode-versie onder `Contents/Applications`; de eerdere aanname dat deze ontbreekt was onjuist. De platformtools voor installatie/start/screenshot/video werkten uiteindelijk wel, na aanvankelijke vertraging. Er is geen Simulator-GUI-navigatie of toetsing van alle schermformaten uitgevoerd.

## Bewijs en reproductie

Lokale bewijsbestanden staan onder `build/waveform-2026-10-19/` (genegeerde map): `ios-wave.png`, `ios-travel.mp4`, `travel-a.png`, `travel-b.png`, de testhostbron, build-/testlogs en `implementation.patch`. Dit zijn synthetische native iOS-previewbeelden, geen opname van de volledige productflow of macOS.

Referentie opnieuw genereren vanuit de kandidaatroot:

```sh
xcrun swiftc macos/Services/AudioEnvelopeProcessor.swift \
  macos/Views/Components/WaveformView.swift scripts/waveform-reference.swift \
  -o /tmp/thoughtvault-waveform-reference
/tmp/thoughtvault-waveform-reference > tests/fixtures/waveform-reference.json
```

Frontend: vanuit `windows`, `npx vitest run --maxWorkers=2` en `npm run build`.

## Open gates, niet weg te strepen

1. **Windows native:** verse Royal TSX-screenshot toont ander gebruikerswerk. Daarom geen invoer/installatie. De bekende private-buildblokkade is niet hersteld gemeld en is niet opnieuw gepolld of omzeild. Juiste nieuwe kandidaatversie, CI/MSI, backup van beide werkelijke stores, idlecontrole en native audio-/beeldcontrole blijven vereist.
2. **Nieuwe fysieke iPhone:** Michel bevestigt een nieuw toestel met dezelfde naam. Devicectl/xctrace tonen alleen de oude, onbereikbare registratie. Nieuwe telefoon via USB verbinden/ontgrendelen en de vertrouwensmelding op het toestel bevestigen; daarna identificatie, pairing, signing en native microfoontest. Geen claim over echte hardwarelatency, routewissels, achtergrondcapture of 120-Hz-toestelgedrag.
3. **iOS bouwroute:** originele projectbuild blijft geblokkeerd op de macOS-only Sparkle-afhankelijkheid. De tijdelijke simulatorbouw is expliciet een validatiekopie; productie-/TestFlight-publicatie is niet uitgevoerd.
4. **Visuele acceptatie:** bewegend synthetisch iOS-bewijs beschikbaar; geen nieuwe macOS-app gestart en geen native Windows-comparisonvideo. Werkelijke mic/system/combined-respons, systeem-Reduce-Motion, overige viewports en CPU/geheugen op doelhardware blijven open. Michel moet de uiteindelijke beweging nog beoordelen.

De soundwave is dus gericht geïmplementeerd en op geometrie en regressies gecontroleerd; volledige platformpariteit is nog niet afgetekend.


## Vervolg — gewone iOS-build en echte iPhone, 19 oktober circa 14:05 CEST

Deze sectie vervangt de eerdere blokkades over Sparkle en de onbereikbare nieuwe iPhone. De bronwijzigingen zijn nog lokaal en ongecommit.

### Sparkle: gewone bouwroute hersteld

De Sparkle-pakketafhankelijkheid stond rechtstreeks op de gedeelde app-target; alleen de frameworkregel gebruikte een enkelvoudig `platformFilter`. De normale iOS-build probeerde daardoor de macOS-only XCFramework te verwerken. In het bestaande project is Sparkle nu een `PBXTargetDependency` met `platformFilters = (macos, )`; de frameworklink gebruikt eveneens deze platformlijst. De macOS-afhankelijkheid, frameworklink en exacte Sparkle-versie 2.10.0 blijven behouden. Geen andere bestaande projectobjecten of buildsettings aangepast.

- Drie contracttests in `scripts/tests/test_sparkle_platforms.py`: de iOS-afhankelijkheidstest faalde vóór de correctie; alle drie slagen erna.
- Gewone volledige simulatorbuild van het originele project: **BUILD SUCCEEDED**.
- Gewone volledige iPhone-build, zonder signing: **BUILD SUCCEEDED**.
- Gewone volledige iPhone-build, met automatische signing voor het nieuwe gekoppelde toestel: **BUILD SUCCEEDED**.
- Ondertekende app met `codesign --verify --deep --strict` gecontroleerd. Geen Sparkle-payload of Sparkle-linkage in de iOS-app gevonden.
- Geen macOS-app gebouwd of gestart. De gedeelde renderer en capturebron zijn ongewijzigd. De gedeelde projectconfiguratie is gericht aangepast om Sparkle tot macOS te beperken; macOS-gedrag is structureel behouden, niet opnieuw native getest.

Logs en metingen: `build/sparkle-iphone-2026-10-19/`. De normale ondertekende app is gebouwd maar niet over de bestaande gebruikersapp geïnstalleerd.

### Nieuwe iPhone en echte audio

Michel heeft de nieuwe telefoon via USB aangesloten, ontgrendeld en vertrouwd. De fysieke apparaatidentiteit is geverifieerd: de zichtbare naam is Myphone16Pro, het nieuwe model is iPhone18Pro. Pairing en ontwikkelaarsmodus zijn bevestigd. Michel heeft zelf in Xcode ingelogd; automatische provisioning voor het nieuwe toestel slaagt. De bestaande ThoughtVault 1.0.256 is behouden.

De aparte app `com.buildmind.ThoughtVault.WaveformQA` (Wave QA) is ondertekend, op dit toestel geïnstalleerd en gestart. Deze compileert de echte `AudioRecorder`, `AudioEnvelopeProcessor`, `WaveformView` en de actuele `IOSLiveWave`-wrapper. Geen account-, cloud-, transcriptie- of gebruikersnotulenfunctionaliteit. Testbron: `scripts/ios-waveform-qa/WaveformQA.swift`. Numerieke meetgegevens zijn uit uitsluitend deze eigen appcontainer gekopieerd. Testaudio blijft op het toestel; niet gelezen/gekopieerd/gepubliceerd/verwijderd.

Michel heeft tweemaal de 35-seconden-microfoontest voltooid en bij de eerste run bevestigd: “golf reageert en beweegt”. De eerste run had volgens Michel omgevingsgeluid tijdens de stiltefasen; die fasen zijn geen stiltebewijs. Tweede run met achtergrondgeluid uit:

| Fase | Samples | Gemiddeld niveau | Maximum |
|---|---:|---:|---:|
| Stilte | 50 | 0,0345 | 0,3457 |
| Zacht spreken | 50 | 0,2568 | 0,7023 |
| Normaal spreken | 50 | 0,4771 | 0,9994 |
| Iets luider spreken | 50 | 0,5609 | 1,0000 |
| Pauze | 50 | 0 | 0 |
| Hervat normaal spreken | 50 | 0,4625 | 1,0000 |
| Stilte na spraak | 50 | 0,3167 | 1,0000 |

Alle 350 niveaumetingen en zeven frequentiebanden zijn eindig en binnen 0..1. Spectrum tijdens spraak aanwezig; pauze is nul; hervatten herstelt de respons. De eerste stilte is aanzienlijk lager dan spraak. De laatste vijf seconden bevatten nog een hoge piek en activiteit. De meetuitvoer bewaart alleen min/max/gemiddelde en bandpieken, geen tijdreeks: daarmee is exacte uitdoving niet aantoonbaar. Michel bevestigt na de tweede test expliciet: “Ja, de golf werd weer rustig”. Daarmee is terugvallen na spraak visueel op het fysieke toestel bevestigd. De exacte uitdooftijd blijft ongemeten; de aggregaten bewijzen geen tijdverloop. Geen DSP-wijziging nodig op basis van deze test.

Dit is echte microfoon-/rendereracceptatie in een geïsoleerde host, geen volledige gebruikersflow in de normale geïnstalleerde app. Video-opname via CoreDevice wordt op dit toestel niet ondersteund; geen fysieke bewegingsvideo claimen. Volledige audio-naar-schermlatency, 120-Hz-cadence, systeem-Reduce-Motion en routewissels blijven open. Windows native acceptatie en pakketgate blijven eveneens open. Geen publicatie, Windows-installatie of vervanging van bestaande gebruikersdata.
