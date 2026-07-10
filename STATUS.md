# STATUS — ThoughtVault

_Laatste update: 2026-07-10_

## Waar was ik

Volle dag aan de opname/transcriptie-pijplijn. Grote bestanden transcriberen nu wel op iOS/macOS: `AudioChunker` splitst sample-exact en `LocalTranscriber` flusht met expliciete `.endOfStream`, watchdog-timeout verruimd. Live mic-visualisatie herbouwd tot een cross-platform pipeline (`AudioEnvelopeProcessor` + Rust `envelope.rs`), pitch-responsieve waveform via FFT, en de neon soundwave is nu een Metal-shader-port van de aangeleverde WebGL-referentie. Onderweg crash bij record-start gefixt, Windows whisper-decode gesegmenteerd, FFT naar workerthread, gedeelde `EmptyStateView`/skeleton + a11y toegevoegd, en een TestFlight-uploadscript (iOS + macOS via ASC API-key). Versie op v1.0.249.

## Volgende stap

Neon-waveform Metal-render visueel verifiëren op device (screenshot/opname) en de grote-bestand-transcriptie end-to-end testen met een echte 90+ MB opname op iOS én macOS. Daarna checken of Windows dezelfde chunk/endOfStream-garantie heeft.

## Open blockers

- Geen harde blockers. Nog te verifiëren: waveform-styling op device en grote-bestand-transcriptie e2e.

## Recente sessies

- **2026-07-10** — Grote-bestanden-transcriptie (AudioChunker sample-exact + endOfStream), cross-platform live envelope, pitch-FFT waveform, neon Metal-shader soundwave, TestFlight-script. v1.0.249.
- **2026-05-06** — Upload pipeline hardening v1.0.124, YAML CI fix, backend `[VALIDATION-422]` log uitgebreid met `sha=`/`client=`. Backend deployed op 3.69.205.209.
- **2026-04-03** — macOS notule detail-pagina aligned met Windows: inline titel editing, compacte unified toolbar, oude tab bar verwijderd.
- **2026-04-02** — Admin task monitoring username display, macOS detail header parity met Windows, zakelijk profiel CSS upgrade.
- **2026-03-20** — Screen capture permission flow vereenvoudigd (DEC-051); upload retry refactor naar reprocess pattern (DEC-052).
