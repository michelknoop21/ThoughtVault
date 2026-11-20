# Windows: systeemgeluid behouden bij een apparaatwissel

## Besluit en basis

Uitvoering op `fix/windows-loopback-recovery`, vanaf lokale main `66f7509` in
`/Volumes/SSD/Projects/thoughtvault-windows-loopback`. De oorspronkelijke werkmap
staat op een oudere auditbranch. De mix met headroom staat al op deze main; `mix_wav_files` blijft ongewijzigd.
Correctie na aanvullende context: de bedoelde fase 3 betreft segmenten en
“Ik/Anderen”, niet alleen de mix. De 28 ongecommitte fase-3-bestanden staan in
`thoughtvault-woordenlijst`. De drie gepushte commits op
`origin/feat/woordenlijst-automatch` (89a8a16, ba418b0, 8236f7f) zitten nog niet
in deze basis. 8236f7f wijzigt uitsluitend macOS-systeemaudio en de bijbehorende
Swift-test. Bij integratie alle drie behouden; fase 3 eerst afzonderlijk testen.
De fase-3-wijziging aan recorder.rs moet met de loopbackwijziging worden gecombineerd.

Een vaste samplerate per cpal-stream sluit niet alle vervorming uit. De concrete
risico's zijn een streamfout en een oude uitvoerstream die stil blijft terwijl
Windows naar een ander apparaat wisselt. Hardwaregedrag is nog niet bewezen.

## Uitvoering

1. Diagnose: log uitvoerapparaten, standaardapparaat, samplerate en kanalen vóór
   de microfoonstream opent en twee seconden na de start. Log streamfouten,
   callbackaantallen en signaalniveau om uitval en stilte te onderscheiden.
   Vergelijk op de pc vóór/na inschakelen van de Beats-microfoon; controleer ook
   of Teams het Windows-standaardapparaat gebruikt. Geen privégesprek opnemen.
2. Bundel Windows-loopback in `audio/loopback.rs` als dit de gedeelde i16/f32-
   callback en herstelcode overzichtelijk maakt. Geen algemene recorderrefactor.
3. Maak de WAV en de geschreven-framepositie eenmalig per opname. Alleen de
   stream, resampler en streamdiagnostiek worden bij een wissel vervangen.
4. Controleer iedere seconde het standaarduitvoerapparaat en de streamfoutvlag.
   Gebruik de WASAPI-apparaatidentiteit, niet alleen de zichtbare naam; detecteer
   ook wijzigingen van het native audioformaat. Sluit de oude stream vóór openen
   van de nieuwe. De bestaande gedeelde actieve klok bewaart gaten als stilte
   en sluit pauzes uit. Stilte alleen is geen fout: WASAPI mag callbacks overslaan.
5. Maximaal tien opeenvolgende herstelpogingen. Een opname die al loopt blijft
   daarna met de microfoon doorgaan, met een duidelijke waarschuwing. Geen fatale
   opnamefout, geen reset van de opname en geen blokkade van bewaren/verwerken.
   Een onbeschikbare systeembron bij de allereerste start blijft expliciet een
   startfout: de gebruiker kan dan bewust Microfoon kiezen. Schrijffouten blijven
   fataal om gegevensverlies niet te verhullen.
6. Log bij elke opening apparaat, rate, kanalen en formaat. Rapporteer elke vijf
   seconden callbackaantallen, frames per callback, signaalniveau en de gemeten
   rate uit capture-timestamps. Vermeld dat gaten de gemeten rate beïnvloeden.
7. Rust-tests: 48 kHz, 0,5 seconde gat, 16 kHz met nieuwe resampler; controleer
   segmentposities, totale lengte en geen dubbele tijd. Test herstelbudget en
   frontendwaarschuwing: opname/timer/bestand blijven behouden en stoppen start
   nog steeds de verwerking. Controleer pauze en late pakketten.
8. Hardwareacceptatie met Beats: vijf minuten gecombineerde testopname met
   Teams of testaudio; microfoon aan/uit, standaardapparaat wisselen, pauze en
   hervatten. Controleer heropening, hoorbaarheid van beide bronnen, duur,
   synchronisatie binnen 50 ms en de normale notulenroute. Bij geforceerd blijvend
   verlies moet de waarschuwing verschijnen en de microfoonopname bewaard blijven.

## Grenzen

Geen Teams-apparaatdetectie op naam, nieuwe dependency, automatische selectie van
andere microfoons, release of openbare bronpush. Lokale tests zijn geen bewijs
voor WASAPI/Beats, MSI-installatie of een gemaakte notule. Hardwareacceptatie en
native Windows-build worden afzonderlijk vastgelegd.

## Uitvoering en bewijs (10 november)

De gedeelde callback en herstelstatus staan in `audio/loopback.rs`. De WAV en
framepositie blijven behouden bij een nieuwe stream; na tien mislukte pogingen
volgt een waarschuwing zonder de microfoonopname of de verwerkingsroute te stoppen.
De initiële startfout en schrijffouten blijven expliciet fouten.

- Rust-audiomodules op macOS: 21 geslaagd, 1 bestaande drie-uursproef overgeslagen.
- Native Windows (Dalf38, Rust/Cargo 1.94.1), gecombineerde audiomodules en
  fase-3-segmenten: **23 geslaagd, 0 mislukt, 1 overgeslagen; exitcode 0**.
  Dit compileert ook de echte WASAPI-tak. De eerste Windows-compile vond een
  onjuist importpad voor `DeviceInner`; gecorrigeerd naar `cpal::platform`.
- Frontend-handler: 4 tests geslaagd; de waarschuwing behoudt opname, bestand,
  timer en de verwerking bij stoppen. TypeScriptcontrole geslaagd.
- Fase 3 is afzonderlijk getest en vastgelegd op `feat/woordenlijst-automatch`
  als `5ad7b10`, bovenop de drie bestaande commits. Zie het bijbehorende
  testverslag `docs/qa/2026-11-10-segmenten.md` op die branch.

De Windows-testkopie bevatte uitsluitend bron/configuratie/testfixtures.
Bronarchief SHA-256: e6eaf37626a879fab4ae3a3ac49738872c295a84e5ec904af257cac254a2f312.
De gecorrigeerde loopback.rs is afzonderlijk overgezet en geverifieerd:
6b905b113c9eafa204212ea2efa4201cf51e5b47cb0fe82b4425f72e39ac8be0.

De Windows-audio-inventaris toonde uitsluitend Steam Streaming-eindpunten,
geen Beats. De vijfminutenproef, omschakeling in belstand, 50ms-synchronisatie
op hardware en het maken van een echte notule zijn daarom nog niet uitgevoerd.
De testcrate is geen volledige Tauri-appbuild of MSI-acceptatie.
