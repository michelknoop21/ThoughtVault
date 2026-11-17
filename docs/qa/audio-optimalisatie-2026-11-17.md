# Audio-optimalisatie — 17 november 2026

Status: implementatie en proefmateriaal op featurebranch; nog geen volledige
hardwareacceptatie en geen uitrol. Basis: main `f9ff3e1e` (1.0.329).
Werkmap: `/Volumes/SSD/Projects/thoughtvault-audio-optimalisatie`.
Bewijsmap: `/Volumes/SSD/Projects/task-evidence/thoughtvault-audio-optimalisatie-20261117`.

## Bewezen problemen en wijzigingen

- Bij vervanging van de resampler bleven gebufferde eindsamples achter. Een
  nieuwe 44,1-kHz-proef vond daardoor 23 stille frames vlak vóór een wissel.
  De converter wordt nu uitgelezen vóór vervanging en stoppen.
- Een formaatmelding kan ook vóór de bijbehorende buffer aankomen. De oude
  eenmalige uitlijning liet dan segmenten 160–400 frames verschuiven. Uitlijning
  gebeurt nu per buffer, met verrekening van samples die nog in de converter
  zitten. Natuurlijke converterbuffering veroorzaakt zo geen extra stiltegaten.
- Core Audio kan callbacks en daarmee de schrijver na stoppen vasthouden.
  In de echte hardwareproef stond daardoor een gevulde WAV nog met duur nul
  in de header. Stoppen sluit het bestand nu expliciet en geeft de schrijver
  vrij. Vanaf macOS 15 wordt ook `AVAudioFile.close()` gebruikt.
- De startdatum voor mengen en de monotone audiotijdlijn worden op hetzelfde
  moment vastgelegd; initialisatietijd wordt niet langer dubbel verschoven.

De gewijzigde gedeelde code zit uitsluitend in `SystemAudioCapture.swift`.
De microfoonrecorder, mixerformule, opslagstructuur, publieke interfaces en
transcriptieproviders zijn niet uitgebreid. Metering en livebufferdoorgifte
blijven behouden. Verkeerd geïnterpreteerde samples rond een formaatmelding
worden hiermee niet achteraf gereconstrueerd; dat blijft een acceptatiepunt.

## Transcriptievergelijking

Lokale MLX Whisper large-v3, snapshot
`49e6aa286ad60c14352c404340ded53710378a11`, Nederlands, temperatuur 0,
`condition_on_previous_text=false`, woordtijdcodes aan en
`hallucination_silence_threshold=2`. Geen downloads of betaalde API-aanroepen.

De bekende Nederlandse QA-spraak is gebruikt voor vijf synthetische varianten.
De twee kandidaten gebruiken maximaal +12 dB vaste gain en −1 dBFS piekgrens.

| Proef | Origineel | Na mengen | Per bron |
| --- | ---: | ---: | ---: |
| Schone QA-spraak | 12% | 12% | 12% |
| Zachte QA-spraak | 12% | 12% | 12% |
| Ongelijke bronsterkte | 12% | 12% | 12% |
| Achtergrondruis | 16% | 16% | 16% |

Dit zijn verkennende WER-scores tegen de beschreven fixturetekst. De synthetische
bronnen splitsen dezelfde zin; het zijn geen twee zelfstandig beoordeelde
sprekers. De overlapproef gaf ook gelijke uitkomsten, maar heeft geen geldige,
handmatig gecontroleerde referentie voor alle overlappende woorden en telt
niet mee als kwaliteitsbewijs. Kritieke feiten zijn niet handmatig beoordeeld.

Daarnaast zijn een ouder opnamefragment uit de normale opnamemap en een apart
beschadigd fragment onderzocht. Na normalisatie veranderde respectievelijk één
woord en 119 woorden in de modeluitvoer. Dat is tekstverschil, **geen WER of
kwaliteitswinst**: een gecontroleerd referentietranscript ontbreekt.

**Besluit: geen normalisatie in de app.** De vereiste 5% relatieve verbetering
is niet bewezen. Daarom blijft de oorspronkelijke audio de transcriptie-invoer.
Er is geen nieuwe verwerkingstaak, instelling of opslagmigratie toegevoegd.
De lokale vergelijkingstools staan in `scripts/audio-quality/` en veranderen
geen bestaande opname of transcriptie. Zie daar de uitvoer- en testinstructies.

## Bewijs en beperkingen

- Bestaande late-notificatietest houdt de oorspronkelijke grens van twee frames.
- Toegevoegd: 16/24/44,1/48 kHz, mono/stereo, vroege meldingen (1 en 4 buffers),
  plus een versnelde twee-uursstroom met 119 formaatwissels. Die controleert
  359.640 blokhandtekeningen buiten de expliciete wisselranden.
- Mixerproeven dekken bronoffsets, verschillende lengtes, clipping en fouten.
- Normalisatie-selfcheck: 32 combinaties van frequentie/kanalen/volume,
  behoud van bron en frameaantal, stilte, piekgrens, voortgang, annulering,
  ontbrekende invoer en weigeren van bestaande uitvoer. Vijf WER-gatetests.
- Korte echte systeemaudioproef via MyBeats Studio Pro en microfoondoorvoer via
  de ingebouwde microfoon uitgevoerd. De microfoonproef bewijst tijdige opslag,
  niet verstaanbare opgenomen microfoonspraak.
- De normale spraak-roundtrip had op drie meetpunten dezelfde lag en
  correlaties van circa 0,996 / 0,996 / 0,985. De opname is digitale systeemaudio;
  de koptelefoon hoeft daarvoor niet akoestisch door de microfoon gehoord te worden.
- De headsetproef opent/sluit de microfoon tweemaal: daadwerkelijk
  48 → 16 → 48 → 16 → 48 kHz. Bij wissels/pauzeren blijft ongeveer 148 ms verschil
  tussen bronafspelen en opgenomen spraak zichtbaar. In de vervolg-review is dit
  gelokaliseerd vóór de converter en gekoppeld aan de apparaatlatentie (160 → 10 ms).
  De gekalibreerde hardwareproef slaagt met 1,9375 ms; de grens is niet verruimd.
  Zie [oorzaakanalyse en resterende acceptatiepunten](audio-review-2026-11-17.md).
- Geen twee uur fysieke opname, geen handmatige luisteracceptatie, geen volledig
  beoordeelde referentieset en geen kalibratie van twee echte sprekers uitgevoerd.
  De twee-uursproef is synthetisch en versneld, geen vervanging hiervan.

Alle originele opnames blijven behouden. Audio en transcriptinhoud staan alleen
in de lokale bewijsmap, niet in Git of diagnostische logs. Resultaatbundels
bevatten de uitgevoerde tests, inclusief mislukte proeven; deze worden niet als
succes gepresenteerd. De app is niet geïnstalleerd, gepubliceerd of uitgerold.

## Laatste verificatie

`regression-final.xcresult`: **14 geslaagd, 2 optionele hardwaretests overgeslagen,
0 fouten**. De twee-uursstroom rapporteert 359.640 gecontroleerde blokken en nul
afwijkingen. De hardwareproeven staan afzonderlijk in `final.xcresult` en eerdere
bundels; deze eerdere afkeuring is in de vervolg-review verklaard. De gekalibreerde
korte Bluetooth-/pauzeproef is groen; volledige spraakacceptatie blijft open.

`selfcheck-final.log`: 32 normalisatiegevallen geslaagd. `score-tests.log`: vijf
gatetests geslaagd. De featurebranch is niet gepusht of gemerged.
