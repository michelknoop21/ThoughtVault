# STATUS — ThoughtVault

_Laatste update: 2026-08-10_

## Waar was ik

Lange lokale opnames mislukten stil — geen transcriptie, geen notule, geen foutmelding. Root cause: `AVAudioFile.read(into:frameCount:)` gooit een kale `nilError` zodra `framePosition` al op EOF staat, en de streaming-lus in `AudioChunker` deed altijd precies één lees-actie te veel. Niet duur- of formaat-afhankelijk: dezelfde throw op een bestand van 2,7 seconden. Het bleef verborgen omdat het chunk-pad pas boven 60 minuten wordt aangeroepen en nooit eerder volledig had gedraaid. Dezelfde lus in `AudioPreConverter` gooide bij élke conversie — gemaskeerd door de fallback die stilzwijgend het originele bestand doorgaf, waardoor geïmporteerde m4a/mp3-bestanden nooit voorgeconverteerd werden. Verder: `isAlreadyWav16kMono()` las `processingFormat` (altijd Float32) in plaats van `fileFormat` en was daardoor een tautologie, en `mixAudioFiles()` schreef float32 in plaats van int16. Mislukkingen verdwenen bovendien na 3 seconden uit beeld. Alles gefixt en end-to-end geverifieerd; de meeting van 10 augustus is alsnog omgezet naar transcriptie + notule.

## Volgende stap

Neon-waveform Metal-render visueel verifiëren op device (screenshot/opname). Daarna checken of Windows dezelfde chunk/EOF-garantie heeft — `hound::WavReader` heeft dit AVFoundation-defect niet, maar de chunkgrenzen zijn niet vergeleken.

## Open blockers

- Geen harde blockers. Nog te verifiëren: waveform-styling op device.
- Bewust niet opgelost (bekend, reëel): geen per-chunk timeout op `pipe.transcribe`, deelresultaten gaan verloren bij een chunk-fout (`AudioChunker` ruimt bij élke fout alle chunks op), en een onderbroken lokale job hervat niet na afsluiten of slaapstand.
- `lastFailedRecording` wordt nu ook in het lokale pad gezet, maar de banner die hem toont (`RecordingView.swift:889`) hangt aan `recordingState == .error` — dat zet géén van beide catch-blokken. De retry-route loopt in de praktijk via "Opgeslagen opnames".

## Recente sessies

- **2026-08-10** — Lange lokale opnames (>60 min) gefixt: read-past-EOF in `AudioChunker` + `AudioPreConverter`, `isAlreadyWav16kMono` op `fileFormat`, `mixAudioFiles` naar int16, foutcontext op de rauwe `try`-calls, mislukte taken blijven zichtbaar. Grote-bestand-transcriptie hiermee daadwerkelijk end-to-end geverifieerd (87 min → 9 chunks → 52.549 tekens → notule). v1.0.251.

- **2026-07-10** — Grote-bestanden-transcriptie (AudioChunker sample-exact + endOfStream), cross-platform live envelope, pitch-FFT waveform, neon Metal-shader soundwave, TestFlight-script. v1.0.249.
- **2026-05-06** — Upload pipeline hardening v1.0.124, YAML CI fix, backend `[VALIDATION-422]` log uitgebreid met `sha=`/`client=`. Backend deployed op 3.69.205.209.
- **2026-04-03** — macOS notule detail-pagina aligned met Windows: inline titel editing, compacte unified toolbar, oude tab bar verwijderd.
- **2026-04-02** — Admin task monitoring username display, macOS detail header parity met Windows, zakelijk profiel CSS upgrade.
- **2026-03-20** — Screen capture permission flow vereenvoudigd (DEC-051); upload retry refactor naar reprocess pattern (DEC-052).
