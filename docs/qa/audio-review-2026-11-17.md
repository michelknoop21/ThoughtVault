# Oorzaakanalyse en review van de 148-ms-afwijking

Review van `ce54c96c`, uitgevoerd op de aangesloten MyBeats Studio Pro.
Status: oorzaak aangetoond, onjuiste hardwaretest gecorrigeerd; volledige
spraakacceptatie tijdens de overgang blijft open. Geen wijziging aan productiecode.

## Oorzaak

De test vergeleek de positie in het oorspronkelijke afspeelbestand met de positie
in de opgenomen WAV alsof de uitvoervertraging constant bleef. Bij het openen
van de Bluetooth-microfoon verandert die vertraging. Een tijdelijke meetfunctie
heeft 2.591 ruwe audiobuffers met hun Core Audio-hosttijd **vóór** de converter
vastgelegd. Zo is de verplaatsing vóór en ná ThoughtVault onafhankelijk vergeleken.

| Meting bij 48 → 16 kHz | Verplaatsing |
| --- | ---: |
| In ruwe Core Audio-invoer, vóór conversie | −148,095 ms |
| In opgeslagen WAV | −148,063 ms |
| Verschil tussen invoer en uitvoer | 0,032 ms |

Dezelfde verschuiving verschijnt opnieuw bij de tweede omschakeling. Terug naar
48 kHz keert de oorspronkelijke vertraging terug. Dit is geen oplopende drift
van de ThoughtVault-converter. Op de gemeten stabiele segmenten verschilt de
verplaatsing vóór/ná verwerking minder dan één 16-kHz-sample.

Een tweede, stille apparaatproef vroeg de Core Audio-latentie rechtstreeks op:

| Stand | Frequentie | Apparaatlatentie | Streamlatentie | Totaal |
| --- | ---: | ---: | ---: | ---: |
| Luisteren, vóór openen microfoon | 48 kHz | 7.680 frames | 0 | 160 ms |
| Microfoon actief | 16 kHz | 160 frames | 0 | 10 ms |
| Microfoon gesloten | 48 kHz | 7.680 frames | 0 | 160 ms |

Het gerapporteerde verschil is 150 ms, dicht bij de gemeten 148,1 ms. De ruwe
bufferproef lokaliseert het effect vóór de recorder; de apparaatgegevens koppelen
het aan de uitvoerroute. Dit bewijst geen fysiek gemeten tijd van speaker tot oor.
Er is daarom **geen vaste 148/150-ms-correctie aan opnamebestanden toegevoegd**.

## Reviewbevindingen

### P1 — Onjuiste referentie voor de hardwaretijdlijn — opgelost

`SystemAudioStorageTests.checkLiveSpeech` schreef een veranderende afspeellatentie
ten onrechte toe aan de recorder. Bovendien viel het oude meetvenster 14–15 s
soms over de vertraagde routeomschakeling na het sluiten van de microfoon.
Een lage correlatie over dat hele venster was geen bewijs voor langdurige
verslechtering van de opname.

De test leest nu per meetpunt de werkelijk gerapporteerde apparaat- plus
streamlatentie, omgerekend naar 16-kHz-frames. Hij vergelijkt de resterende
tijdverschillen en meet op stabiele punten 2, 8, 16, 20 en 27 s. Pauzetijd wordt
met de monotone hostklok gemeten. De limieten blijven 20 ms en correlatie >0,98;
er wordt geen vaste compensatie afgeleid uit de gewenste testuitkomst.

### P2 — Woordbehoud precies tijdens wissels is nog niet bewezen — open

De synthetische test sluit de wisselranden expliciet uit van zijn gatendetectie
(`SystemAudioStorageTests.swift:129`). Bij vier buffers voorsprong gaat dit om
80 ms vóór tot 60 ms ná de wissel. Ook de gekalibreerde hardwaretest meet bewust
buiten de overgang zelf. Deze tests bewijzen dus timing in de stabiele stukken,
maar niet dat ieder woord tijdens de omschakeling intact blijft.

`TapAudioWriter` kan verkeerd geïnterpreteerde buffers rond een vroeg/laat
ontvangen formaatsignaal niet reconstrueren. Hiervoor blijft afzonderlijke
controle van bekende spraak precies op de wisselmomenten nodig. Een groene
gekalibreerde test is geen reden deze inhoudelijke acceptatie te sluiten.

### P2 — Nog geen directe microfoon-tegen-systeemkalibratie — open

De headsetmicrofoon wordt in de proef geopend om de routewissel op te wekken;
de microfoonspraak wordt niet opgeslagen. De meetreferentie is de afgespeelde
spraak plus apparaatlatentie. Daarmee is de oorzaak van deze testfout onderzocht,
maar niet zelfstandig bewezen dat twee echte gelijktijdige sprekers via beide
opnamebronnen gedurende twee uur binnen 20 ms blijven.

## Verificatie

- Oude test met ruwe meetfunctie: reproduceert de fout; 2.591 inputbuffers en
  WAV als lokale XCTest-bijlagen opgeslagen.
- Apparaatlatentieproef: **TEST SUCCEEDED**, 48 → 16 → 48 kHz bevestigd.
- Gecorrigeerde hardwareproef, twee keer microfoon open/dicht en eenmaal pauze:
  **TEST SUCCEEDED**, geen overgeslagen tests.
- Maximale resterende afwijking: **1,9375 ms** (31 frames).
- Correlaties op de vijf meetpunten: **0,994895–0,999993**.
- Herberekening van dezelfde resultaten: oude gate faalt op 148,125 ms,
  gekalibreerde gate slaagt op 1,9375 ms. Een geïnjecteerde extra fout van
  30 ms wordt nog steeds afgekeurd (30,0625 ms). De 20-ms-grens is niet verruimd.
- De opnamecode is bytegelijk aan `ce54c96c`; de eerdere 14 geslaagde stille
  audiotests worden hergebruikt als bewijs voor die ongewijzigde code, niet
  voorgesteld als opnieuw uitgevoerd. Geen volledige testsuite opnieuw gedraaid.
- Normalisatie blijft uitgeschakeld. Geen uitrol of installatie uitgevoerd.

## Reproduceerbaar bewijs

Alles staat op de externe SSD onder:
`/Volumes/SSD/Projects/task-evidence/thoughtvault-audio-optimalisatie-20261117/review/`.

- `raw-probe.xcresult`, `raw-attachments/`, `raw-analysis.json`: onafhankelijke invoermeting.
- `latency-properties.xcresult` en `.log`: apparaatmetingen in beide standen.
- `calibrated.xcresult`, `calibrated-summary.json`: gecorrigeerde hardwareproef.
- `gate-sensitivity.json`: oorspronkelijke afkeuring en behoud van foutdetectie.
- `analyze-raw.py`: lokale correlatieanalyse, met zelfcontrole op een bekende verschuiving.
- `instrumentation.patch`: de tijdelijke meetwijziging, bewaard voor reproductie;
  deze zit niet meer in de app of de tests.

Audio-inhoud is alleen als lokale bewijsbijlage bewaard, niet in Git of gewone
diagnostische logs. De gebruikerstoepassing en oorspronkelijke opnames blijven behouden.
