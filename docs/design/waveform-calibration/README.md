# Soundwave-calibratie (29 september 2026)

De NorthStar bepaalt de vorm. De vaste test gebruikt 210 metingen op 30 Hz:
1 seconde stilte, 1,5 seconde zacht, 2,5 seconden syllabische normale spraak,
0,7 seconde luid en 1,3 seconde stilte. De zes renders zijn 1916 × 821 pixels;
de golf staat op dezelfde verticale positie en in dezelfde 280-pixel-sleuf
als de vaste macOS Studio-layout. [Vergelijking met NorthStar](northstar-comparison.png).
De PNG-export tijdens de test is optioneel: maak eerst
`/tmp/thoughtvault-wave-export-snapshots` aan. Zonder die marker controleert
de test alleen de getallen.

## Audioketen

| Stap | Uitgangssituatie / definitieve instelling |
| --- | --- |
| Microfoon | `AVAudioRecorder.averagePower`, dBFS, 30 Hz |
| Systeemaudio | Tap-PCM RMS, dBFS, maximaal 30 Hz; nu dezelfde envelope als de microfoon |
| Noise floor | 20e percentiel over circa 2 s, begrensd tot −75…−35 dBFS |
| Gate | Vloer +3…+9 dB |
| Envelope | Aanval 35 ms, terugval 220 ms tijdconstante; al vóór de view |
| View | `visualEnergy = 0.72 × envelope³`, zonder tweede smoothing |
| Beweging | Constante fasebeweging 0,3 Hz, maximaal 25% sneller bij luid signaal |

De bestaande debug-overlay toont input-dB, floor, gate, target, envelope en
interval. De systemtap had eerst een eigen vaste −60 dB-schaal en berekende
daarmee een niet-afgevlakte waarde. Dat pad gebruikt nu dezelfde processor.

## Gemeten fixture

Visuele waarde is de input voor hoogte, spreiding en glow. De heldere curve
beslaat bij de renders het volgende deel van de beschikbare halve hoogte
(140 px); de verdere zachte glow is daarbij buiten beschouwing gelaten.

| Moment | Envelope | Visual energy | Heldere amplitude |
| --- | ---: | ---: | ---: |
| [Stilte](silence.png) | 0,000 | 0,000 | 1% |
| [Zacht](soft.png) | 0,574 | 0,136 | 23% |
| [Normaal](normal.png) | 0,762 | 0,319 | 48% |
| [Luid](loud.png) | 1,000 | 0,720 | 73% |
| [200 ms na spraak](release200.png) | 0,403 | 0,047 | 26% |
| [600 ms na spraak](release600.png) | 0,065 | 0,0002 | 1% |

Bij zachte spraak bereikt `visualEnergy` 0,084 na 66 ms en 0,114 na 100 ms.
De [widgetrender op 120 × 32 punten](widget-loud.png) gebruikt dezelfde
envelope, vier lijnen en een kleinere glow. In de vaste render blijven de
heldere pixels binnen de boven- en onderrand.

## Live microfoon

Een aanvullende meting via dezelfde macOS `AVAudioRecorder`-meter registreerde
kamerstilte rond −55 dBFS met `visualEnergy` 0. Tijdens spraak lag die waarde
meestal op 0,20–0,33, met een gemeten piek van 0,49. Na de overgang van
spraak naar stilte zakte hij binnen circa 0,5 s onder 0,05. Het opgenomen
bestand was mono PCM, 16 kHz, 16-bit WAV. De tijdelijke audiofile is na deze
controle verwijderd; alleen deze afgeleide cijfers zijn bewaard.

## Bewuste afwijking

De NorthStar-afbeelding heeft een veel bredere diffuse halo dan binnen de
vaste 280-pixel-golfsleuf mogelijk is zonder de layout of clipping te
veranderen. De Canvas-versie bewaart de violette kern, zeven afzonderlijke
lichtdraden, lokale kruisingen en voldoende marge. De piek is bewust minder
wit en de randen verdwijnen geleidelijk.

De screenshots zijn deterministische renders, geen schermafbeeldingen van een
lopende opname. De live microfoonmeting bewijst de inputrespons; de zwevende
widget en transcriptie zijn hiermee niet end-to-end op een opname getest.
