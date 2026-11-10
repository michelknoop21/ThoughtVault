# STATUS — ThoughtVault

_Laatste update: 2026-11-10_

## Waar was ik

De support-relay staat live: container `thoughtvault-support` op n8n01, bereikbaar op `https://thoughtvault.yinga.ai/support`, doorgezet naar de feedback-hub (tool `thought-vault`, prefix `TV`). De hele keten is op 10 november getest met `TV-000001` en `TV-000002`. Contract en bediening staan in `docs/SUPPORT-RELAY.md`, het besluit in DEC-064. De fasen b (macOS en iOS), c (Windows), d (Windows-updates) en e (privacyverklaring) lopen in eigen worktrees.

## Volgende stap

Fase b en c afronden: de apps laten registreren, rapporteren en antwoorden tonen volgens het contract. Voor fase e (privacytekst) heeft Michel vijf besluiten nodig: verantwoordelijke en contactpunt, lancering vóór of na het automatisch opruimen in de hub, bewaartermijn van installatiegegevens, serverlocatie en verwerkers, en grondslag met klachtrecht.

## Open blockers

- Privacytekst wacht op de besluiten hierboven.
- Automatisch opruimen van gesloten tickets in de hub is nog niet gebouwd (aparte taak in de hubrepo).
- `n8n_transcript_studio` draait niet op n8n01, dus `/tstudio/api` geeft 502 tot de backend opnieuw wordt neergezet of de nginx-route verandert.
- Nog te verifiëren: waveform-styling op device.
- Bewust niet opgelost (bekend, reëel): geen per-chunk timeout op `pipe.transcribe`, deelresultaten gaan verloren bij een chunk-fout (`AudioChunker` ruimt bij élke fout alle chunks op), en een onderbroken lokale job hervat niet na afsluiten of slaapstand.
- `lastFailedRecording` wordt nu ook in het lokale pad gezet, maar de banner die hem toont (`RecordingView.swift:889`) hangt aan `recordingState == .error` — dat zet géén van beide catch-blokken. De retry-route loopt in de praktijk via "Opgeslagen opnames".

## Recente sessies

- **2026-11-10**: Support-relay live op n8n01 (container `thoughtvault-support`, Caddy-route `/support`), end-to-end getest met `TV-000001` en `TV-000002`. DEC-064, `docs/SUPPORT-RELAY.md`, DEC-039 tot en met DEC-053 gearchiveerd.
- **2026-08-10** — Lange lokale opnames (>60 min) gefixt: read-past-EOF in `AudioChunker` + `AudioPreConverter`, `isAlreadyWav16kMono` op `fileFormat`, `mixAudioFiles` naar int16, foutcontext op de rauwe `try`-calls, mislukte taken blijven zichtbaar. Grote-bestand-transcriptie hiermee daadwerkelijk end-to-end geverifieerd (87 min → 9 chunks → 52.549 tekens → notule). v1.0.251.

- **2026-07-10** — Grote-bestanden-transcriptie (AudioChunker sample-exact + endOfStream), cross-platform live envelope, pitch-FFT waveform, neon Metal-shader soundwave, TestFlight-script. v1.0.249.
- **2026-05-06** — Upload pipeline hardening v1.0.124, YAML CI fix, backend `[VALIDATION-422]` log uitgebreid met `sha=`/`client=`. Backend deployed op 3.69.205.209.
- **2026-04-03** — macOS notule detail-pagina aligned met Windows: inline titel editing, compacte unified toolbar, oude tab bar verwijderd.
