# Sprekersdetectie: metingen fase 0

Stand 24 november 2026, eind van de middag. Nog geen keuze: er zijn twee opnames gemeten met vier detectoren, maar het luisteroordeel dat zegt wie gelijk heeft ontbreekt nog.

## Opnames

| Naam | Wat | Duur | Stemmen volgens alle detectoren |
|---|---|---|---|
| call34 | call van 18 november | 34 min (2046 s) | 4 |
| meet56 | meeting van 24 november | 56 min (3349 s) | 2 |

Beide zijn een mono mix van microfoon en systeemgeluid, 16 kHz. De opnames staan niet in de repo. Een fysiek overleg met meerdere mensen in één ruimte ontbreekt nog.

## Lokaal op macOS

Beide kandidaten via de CLI van FluidAudio 0.18.3 (de versie die de app al gebruikt), standaardinstellingen, op de Mac van de ontwikkelaar.

| Opname | Kandidaat | Beurten | Korter dan 1,5 s | Rekentijd | Piekgeheugen |
|---|---|---|---|---|---|
| call34 | community-1 + VBx (`process --mode offline`) | 317 | 58 | 9 s | 531 MB |
| call34 | Nemotron 3 Diarization (`nemotron3-diarize`) | 740 | 378 | 104 s | 489 MB |
| meet56 | community-1 + VBx | 360 | 33 | 11 s | 549 MB |
| meet56 | Nemotron 3 Diarization | 1231 | 604 | 169 s | 644 MB |

Nemotron vindt in meet56 een derde stem met vrijwel geen spreektijd. De rekentijd van community-1 bevat het laden van het model niet; met laden was het 18 s bij call34.

## Cloud via OpenRouter

Eén aanroep van `/api/v1/audio/transcriptions` met `response_format: verbose_json` geeft de transcriptie met per woord een tijdstempel en een spreker. De opname ging als mp3 (mono, 32 kbit/s) in één stuk, zonder opknippen. De audio verlaat hierbij het apparaat.

| Opname | Model | Wachttijd | Kosten | Woorden | Beurten | Korter dan 1,5 s |
|---|---|---|---|---|---|---|
| call34 | `elevenlabs/scribe-v2` (`diarize: true`) | 38 s | $0,125 | 6370 | 535 | 219 |
| call34 | `microsoft/mai-transcribe-2` (Azure, `diarization.enabled`) | 8 s | $0,057 | 6791 | 586 | 283 |
| meet56 | `elevenlabs/scribe-v2` | 62 s | $0,205 | 11649 | 954 | 438 |
| meet56 | `microsoft/mai-transcribe-2` | 14 s | $0,093 | 11839 | 1033 | 489 |

Een beurt is hier een reeks opeenvolgende woorden van dezelfde spreker met minder dan een halve seconde ertussen. De documentatie van OpenRouter noemt een grens van 25 MB per upload en een time-out van 60 seconden bij de aanbieder. Scribe deed 62 s over meet56 en kwam er nog doorheen; hoe lang een opname kan zijn voordat dat misgaat is niet gemeten.

## Onderlinge overeenstemming

Aandeel van de spreektijd van de eerstgenoemde dat bij de tweede dezelfde stem krijgt (`scripts/sprekers-bench/score.py`). Tijd die de tweede als stilte ziet telt als verschil, dus een detector die meer spraak aanwijst scoort als eerstgenoemde lager.

| Paar | call34 | meet56 |
|---|---|---|
| community-1 en Nemotron | 87,9% | 85,2% |
| community-1 en Scribe v2 | 83,5% | 85,1% |
| community-1 en MAI-Transcribe 2 | 88,9% | 87,2% |
| Nemotron en Scribe v2 | 86,1% | 90,0% |
| Nemotron en MAI-Transcribe 2 | 92,0% | 92,4% |
| Scribe v2 en MAI-Transcribe 2 | 92,7% | 97,1% |

Omgekeerd gemeten (Nemotron eerst, community-1 tweede) is het 93,0% bij call34 en 92,6% bij meet56. De twee cloudmodellen liggen het dichtst bij elkaar en Nemotron ligt dichter bij hen dan community-1. Dat zegt niet wie gelijk heeft. In meet56 beslaan de passages van een seconde of langer waar community-1 en Nemotron een andere stem aanwijzen samen 40 seconden; de rest van het verschil zit in wissels korter dan een seconde en in spraak die maar één van de twee hoort.

## Luisteroordeel op meet56

Op 24 november zijn 24 passages beluisterd en van een spreker voorzien. De passages zijn gekozen op het verschil tussen de twee lokale detectoren: 14 waar ze een andere stem aanwijzen (4 daarvan bleken gelijktijdig spreken en tellen niet mee) en 10 korte reacties die alleen Nemotron hoort. Per detector telt de stem die hij over het grootste deel van de passage aanwijst.

| Detector | Verschilpassages goed (van 10) | Korte reacties goed (van 10) | Korte reacties zonder spreker |
|---|---|---|---|
| community-1 + VBx | 5 | 0 | 10 |
| Nemotron 3 | 5 | 10 | 0 |
| Scribe v2 | 9 | 9 | 1 |
| MAI-Transcribe 2 | 9 | 9 | 1 |

De keuze van de passages benadeelt de lokale detectoren: bij een verschilpassage heeft per definitie hooguit een van de twee gelijk, en de korte reacties zijn juist de stukken die community-1 niet als spraak ziet. Wat er wel uit volgt: community-1 mist korte reacties die er echt zijn, Nemotron wijst die tien alle tien goed toe, en de cloudmodellen zitten op de lastige wisselmomenten vaker goed dan beide lokale detectoren. Het zijn twintig passages uit één meeting met twee stemmen.

## Opnameniveau

De mix van meet56 was zacht: gemiddeld -37,7 dB, de stem op het systeemkanaal -40,9 dBFS en de stem op de microfoon -34,5 dBFS. Bij call34 lagen de stemmen rond -25 dBFS. Twee oorzaken: de mixer halveerde de som van beide bronnen (6 dB), en de bronnen zelf waren deze keer 10 tot 16 dB zachter dan bij call34, zonder dat iets dat corrigeerde. `AudioMixer.mix` (macOS) en `mix_wav_files` (Windows, nu in `windows/src-tauri/src/audio/mix.rs`) brengen nu elke bron eerst naar hetzelfde spraakniveau en tellen ze dan op. Op nagebouwde bronnen van meet56 komen de stemmen daarmee op -22,7 en -21,6 dBFS, met 0,009% van de samples op vol niveau. De wijziging staat op de branch `fix/mixer-spraakniveau`.

Alle vier de detectoren zijn daarna opnieuw gedraaid op een luidere versie van meet56 en naast hetzelfde luisteroordeel gelegd:

| Detector | Mix | Verschilpassages goed (van 10) | Korte reacties goed / fout / geen spreker |
|---|---|---|---|
| community-1 + VBx | oud | 5 | 0 / 0 / 10 |
| community-1 + VBx | luid | 9 | 3 / 3 / 4 |
| Nemotron 3 | oud | 5 | 10 / 0 / 0 |
| Nemotron 3 | luid | 5 | 10 / 0 / 0 |
| Scribe v2 | oud | 9 | 9 / 0 / 1 |
| Scribe v2 | luid | 9 | 8 / 0 / 2 |
| MAI-Transcribe 2 | oud | 9 | 9 / 0 / 1 |
| MAI-Transcribe 2 | luid | 9 | 9 / 0 / 1 |

Nemotron vindt op de luide mix twee stemmen in plaats van drie. Over de hele opname verschuift weinig: community-1 wijst 97,4% van de spreektijd hetzelfde toe als op de oude mix, Nemotron 98,9%. De cloudmodellen veranderen nauwelijks: Scribe v2 wijst 97,6% van de spreektijd hetzelfde toe als op de oude mix en MAI-Transcribe 2 98,9%; het aantal woorden gaat van 11649 naar 11514 en van 11839 naar 11822. MAI-Transcribe 2 meldt op de luide mix een derde stem met minder dan een seconde spreektijd. De luide versie is nagebouwd, niet door de mixer gemaakt: de echte bronnen zijn weg, dus de versterking is per 10 ms gekozen op de stem die de detectoren op de oude mix aanwezen. Een opname die echt door de nieuwe mixer is gegaan moet dit bevestigen.

## Windows-kandidaten op n8n01: geen uitkomst

Gemeten in Docker op n8n01 met 2 cores en 3 GB per container, op call34.

- Nemotron 3 Diarization via nemo-speech 0.2.0 (`diarize --device cpu`, model `Nemotron-3-Diarization.q8_0.gguf`): na ruim 90 minuten rekenen nog geen uitvoer, daarna gestopt. Piekgeheugen 560 MB. Het commando en `transcribe --diarize` bestaan in 0.2.0; dat is met een proefrun bevestigd.
- sherpa-onnx (pyannote segmentation-3.0 met wespeaker resnet34-LM): na 10 minuten gestopt zonder uitvoer.

De server was in die periode zwaar belast door andere taken (load 7 tot 12 op 4 cores), dus deze tijden zeggen weinig over een gewone Windows-pc. Ze zeggen wel dat Nemotron op CPU geen vanzelfsprekende route is: op de Mac deed hetzelfde model 104 s over dezelfde opname. Een nieuwe meting hoort op een Windows-machine of op een kort fragment, niet op n8n01.

## Nog te doen

- Luisteroordeel op meet56: per stem een naam en bij 25 passages wie er spreekt. Daarmee is te tellen welke detector vaker gelijk heeft, ook bij de korte reacties.
- Hetzelfde voor call34, en een fysiek overleg opnemen.
- Windows lokaal meten op een Windows-machine.
- Dezelfde transcriptie onder de lokale detectoren leggen en per woord scoren.

## Hoe andere notule-apps het doen

Samenvatting van het onderzoek van 24 november. Bronnen: [Granola](https://docs.granola.ai/help-center/taking-notes/speaker-attribution), [Superwhisper](https://superwhisper.com/docs/modes/speaker-separated-meetings), [MacWhisper](https://docs.macwhisper.com/article/32-automatic-speaker-recognition-in-macwhisper) en [versie 15.2](https://9to5mac.com/2026/09/23/macwhisper-update-brings-real-time-meeting-transcripts-improved-speaker-recognition-more/), [Jamie](https://docs.meetjamie.ai/getting-started/identify-speaker), [Fireflies](https://guide.fireflies.ai/hc/en-us/articles/360020248198-How-to-Change-the-Names-of-Speakers). De pagina's van Otter en Wispr Flow zijn alleen via zoekfragmenten of marketingtekst gelezen.

- Kanaalscheiding is bij Granola, Superwhisper en Wispr Flow de basis: microfoon is "ik", systeemgeluid is "zij". Granola zegt zelf dat een gedeeld vergaderapparaat zo niet te splitsen is.
- MacWhisper doet akoestische detectie op het apparaat en stapte in versie 15.2 over van Argmax SpeakerKit op Nemotron 3 Diarization, tot acht sprekers.
- Jamie laat je na de meeting per stem een fragment beluisteren en een naam typen, en onthoudt die. Otter en Teams werken met stemprofielen; Fireflies en Wispr kiezen daar uitdrukkelijk niet voor.
- Namen komen bijna overal uit een tweede bron: de deelnemerslijst van het platform, de agenda, of één keer handmatig labelen. Geen van de onderzochte bot-vrije producten haalt namen uit de stem alleen.
- Corrigeren dat doorwerkt in de notule (hernoemen, stemmen samenvoegen, een passage aan iemand anders hangen) zit in MacWhisper, Fireflies en Meetily.
- Voor Nederlands is geen gepubliceerd nauwkeurigheidscijfer gevonden.
