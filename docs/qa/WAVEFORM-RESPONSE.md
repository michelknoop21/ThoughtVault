# Soundwave: berekening en verificatie

De aangeleverde Windows-video laat een kleine, bijna gelijkmatige golf zien terwijl het audioniveau uitslaat. Een schermopname zonder audiotrack bewijst geen exacte vertraging ten opzichte van geluid. Brononderzoek en vaste PCM-tests tonen twee oorzaken: gaten in de frequentiemeting en het vervangen van volume/lettergreeptiming door frequentiedata in de renderer.

## Aangetoonde meetfout

De oude Goertzel-code meet 21 losse frequenties: zeven centra met telkens factoren 0,85, 1 en 1,15. Daartussen is geen complete bandmeting. De ongewijzigde Rust-code geeft bij even luide 250-, 350-, 700- en 1.400-Hz-tonen respectievelijk 0,864, 0, 0 en 0 terug. Een afzonderlijke berekening van dezelfde Hann-probes toont voor 350 Hz circa 55 dB ondermeting ten opzichte van 250 Hz. Dit is geen volumeverschil in de testbron.

![Gelijke testtonen met oude en nieuwe native berekening](waveform-frequency-response.svg)

De grafiek vergelijkt de sterkste genormaliseerde band van de echte oude Rust-code met de nieuwe Swift-code bij 16 kHz, sinusamplitude 0,1 en vijftien analyseframes. Bij een bandgrens verdeelt de correcte berekening energie over twee banden; de sterkste afzonderlijke band is daar iets lager. De volledige energie blijft aanwezig.

## Berekening

Voor PCM-samples x[n] bepaalt RMS = sqrt(sum(x[n]^2)/N) het totale volume. De bestaande gekalibreerde volume-envelope en noise gate blijven behouden.

Een periodiek Hann-venster w[n] onderdrukt randlekken. De FFT analyseert alle frequentiebins van de laatste macht-van-twee samples, maximaal 4.096. De bestaande capturebuffer bevat maximaal 64 ms. Bij stabiele 16-kHz-capture zijn dat 1.024 samples (64 ms); bij 48 kHz zijn dat 2.048 samples (42,67 ms).

De zeven aaneengesloten banden hebben grenzen 80, 177, 354, 707, 1.414, 2.828 en 5.657 Hz; de hoogste band loopt door tot Nyquist. Voor iedere band:

```
P_band = sum(m[k] * |FFT(x*w)[k]|²) / (N * sum(w[n]²))
dB_band = 10 * log10(max(P_band, 1e-20))
target = clamp((dB_band + 60) / 48, 0, 1)^0.8
alpha = 1 - exp(-dt / tau)
smoothed += alpha * (target - smoothed)
```

m[k] is 2 voor gespiegeld real-input spectrum en 1 op Nyquist. De vensterenergiecorrectie bewaart het juiste vermogen. tau is 25 ms bij stijging en 140 ms bij daling. FFT-plan, Hann-venster en Windows-buffers worden hergebruikt. macOS gebruikt Accelerate; Windows hergebruikt de FFT van de bestaande Symphonia-audiodecoder. Er is geen nieuwe appdependency, eigen FFT-implementatie of tweede capturebron nodig.

## Visualisatie

Het ontwerp blijft een gestileerde spectrale visualisatie. De hoofdgolf gebruikt de totale volume-envelope; frequentiemetingen kunnen hoorbare spraak daardoor niet vlak maken. Andere lijnen worden gewogen naar hun gemeten band en krijgen verschillende ruimtelijke golfpatronen. De gemeten verdeling tussen lage en hoge banden beïnvloedt het hoofdpatroon. De bestaande vertraagde lettergreeplobben blijven behouden. Dit is geen schatting van een exacte grondtoon in Hz.

Het opnamevenster en de widget gebruiken dezelfde aangepaste component op ieder platform. Pauze/inactiviteit blijft vlak; oude frequentiedata mag een stille volume-envelope niet laten bewegen. Clipping, beperkte widgethoogte en Reduce Motion blijven behouden.

## Verificatie

- Negatieve controle: echte oude Rust-processor geeft nul voor 350, 700 en 1.400 Hz bij een hoorbare sinusamplitude van 0,1.
- Nieuwe Swift- en Rust-tests: elf even luide tonen, waaronder die gaten, op 16, 44,1 en 48 kHz. Alle sterkste bandwaarden liggen tussen 0,68 en 0,87.
- Streaming-fixture met 1.200 Hz, 533 samples per 30-Hz-frame en een rollende 1.024-samplebuffer: native Swift-bandwaarde 0,564 na 33 ms, 0,746 na 66 ms en 0,795 na 99 ms. Na 500 ms stilte is de resterende waarde 0,028. Rust toetst dezelfde grenzen.
- Rendererregressie: hoorbaar volume blijft zichtbaar bij nul/smal spectrum; lage/hoge banden leveren verschillende paden; stale spectrum maakt stilte niet levend; compacte paden blijven binnen hun canvas en Reduce Motion blijft stabiel.
- Lokale Windows-suite: 76 frontendtests en 22 native Rust-tests slagen. Windows bevat één extra platformgebonden native test in CI.
- Dezelfde daadwerkelijke Swift-bron is afzonderlijk gecompileerd en getoetst met de 33 toon/sample-rategevallen, streamingreactie en niet-eindige PCM. Appbuild, native XCTest, uiteindelijke installers en runtimecontrole worden afzonderlijk in de releasecontrole vastgelegd.

Deze getallen meten de DSP-fixture, niet de complete hardware-naar-schermvertraging via Royal TSX. Een volledige nieuwe videomeeting en audiovisuële synchronisatietest zijn daarmee nog niet bewezen. De bronopname en meetinginhoud staan niet in de repo.

## Bronnen

- [W3C Web Audio: FFT windowing and smoothing](https://www.w3.org/TR/webaudio-1.0/#fft-windowing-and-smoothing-over-time)
- [MathWorks: bandvermogen door integratie van PSD](https://www.mathworks.com/help/signal/ref/bandpower.html)
- [MathWorks: vermogen en RMS](https://www.mathworks.com/help/signal/ug/measure-the-power-of-a-signal.html)
- [Apple Accelerate: DiscreteFourierTransform](https://developer.apple.com/documentation/accelerate/vdsp/discretefouriertransform)
- [Bestaande Symphonia FFT](https://docs.rs/symphonia-core/0.5.5/symphonia_core/dsp/fft/struct.Fft.html)


## SiriWave styling, 8 oktober 2026

De renderer op macOS en Windows gebruikt nu de Classic-curve van [kopiro/siriwave](https://github.com/kopiro/siriwave/blob/744cb00235b7900733efff25dc73b4d1ab77c92d/src/classic-curve.ts), commit `744cb00235b7900733efff25dc73b4d1ab77c92d`. De MIT-licentie staat in `docs/licenses/siriwave-MIT.txt` en wordt ook in beide appbundels meegenomen. Er is geen JavaScript-library of nieuwe opname-engine toegevoegd. SwiftUI Canvas en Windows Canvas behouden hun bestaande kleuren, dunne lijnen en clipping.

Voor genormaliseerde positie x gebruiken beide platformen u = 4x - 2 en de SiriWave-attenuatie (4 / (4 + u^4))^4. Een doorlopende, op verstreken tijd gebaseerde fase verplaatst de golf, ook bij constant volume. De hoofdgolf volgt de gekalibreerde RMS-envelope. Steunlijnen hebben verschillende fasesnelheden en worden gewogen door hun echte frequentiebanden en kort vertraagde envelope. Stilte en pauze leveren een vlakke lijn; Reduce Motion bevriest de beweging maar behoudt volumefeedback. Deze gestileerde beweging is geen exacte weergave van de PCM-periode of toonhoogte.

De nieuwe preview `docs/qa/assets/siriwave-soundwave.mp4` bevat twaalf seconden synthetische zachte, normale en harde audio, gevolgd door stilte. De preview gebruikt dezelfde curve en audiodiagnostiek als de app. Een gedeelde klok wordt eenmaal per geëxporteerd frame vooruitgezet, zodat de fase niet opnieuw begint. Alleen de preview-klok, donkere kleurkeuze en AppKit-drag-overlay worden voor headless export aangepast. De video is geen opname van de geïnstalleerde app en bewijst geen hardwarelatency.

Verificatie: 76 Windows-front-endtests slagen en de productie-front-endbuild slaagt. De signed native macOS Release-build slaagt en `codesign --verify --deep --strict` slaagt. De macOS-audioregressiesuite telt 21 geslaagde tests, 2 expliciet overgeslagen hardwaretests en 0 fouten. De nieuwe regressies controleren beweging bij constant volume, 30/60 Hz fasepariteit, vlakke stilte, Reduce Motion en begrensde curvehoogte. Beide gebouwde appbundels bevatten de SiriWave MIT-licentie. Op 8 oktober was de aanpassing nog niet geïnstalleerd of gepubliceerd; de installatiecontrole van 9 oktober staat hieronder.


## Installatie 1.0.268, 9 oktober 2026

Broncommit: `0b420c7d9f6ee0fc8a31a0398068a2fda10bbdba`. De Windows-kandidaat is succesvol gebouwd in [GitHub Actions 37897292052](https://github.com/michelknoop21/ThoughtVault/actions/runs/37897292052), met `publish=false`.

De signed macOS Release-build is op het vaste pad `/Applications/ThoughtVault.app` geïnstalleerd nadat het opnamevenster inactief op 00:00 stond. Het native versievenster bevestigt 1.0.268 (268). De sandbox en het signingteam XL9KN38ATX zijn behouden, de SiriWave-licentie zit in de appbundle en alle 16 opgeslagen opnames zijn zichtbaar gebleven. Het vorige appbundle staat in `/Applications/ThoughtVault-267-before-268.app`; de bestaande store is vóór heropenen naar een lokale backup gekopieerd. De werkelijke sandbox-ID is `com.buildmind.ThoughtVault`. Er is geen nieuwe opname of providerrequest gestart. Executable SHA-256: `5bb49d72c0a4fd7954e81b59eac93e60e12c13ab542e07278ee2b307fd891b07`.

Windows is via de bestaande Royal TSX Dalf38 VPN-sessie bijgewerkt van 1.0.267 naar 1.0.268. Vóór installatie draaide ThoughtVault niet. De bestaande notulen-JSON is lokaal geback-upt en gehasht zonder de inhoud te lezen. De MSI eindigde met exitcode 0; de executable in Program Files bevestigt 1.0.268. Na starten bevestigt het echte Windows-proces versie 1.0.268 en Responding=True. De notulenhash is zowel na installatie als na starten ongewijzigd. Avast heeft de normale startcontrole afgerond zonder bedreigingen; er zijn geen beveiligingsinstellingen aangepast.

De MSI is 8.880.128 bytes; SHA-256: `b8d45ea139ee546fd56911151f983b166343366b2db935e0e4bbfc6d0dcff524`. CI bevestigt 76 geslaagde frontendtests, 23 geslaagde native Rust-tests, de MSI-upgrade en twee native startcontroles met behoud van opgeslagen notulen. De tijdelijke lokale installer-server is afgesloten.

Beide geïnstalleerde apps bevatten de SiriWave-aanpassing. Deze controle bewijst installatie en opstarten, niet de reactie op een nieuwe echte meeting of hardware-audio. De publieke updaterfeed en downloadsite zijn niet naar 1.0.268 bijgewerkt.
