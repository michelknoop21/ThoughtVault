# ThoughtVault landingpage

Commerciële desktopproductpagina: van gedachten en gesprekken naar een notitie of notulen in je Obsidian-vault. Statische HTML, CSS en JavaScript, zonder buildstap. Gepubliceerd op https://thoughtvault.yinga.ai/ in een eigen Dockercontainer op n8n01.

## Beelden en inhoud

- `assets/thoughtvault-mark.png`: door de gebruiker goedgekeurde vrijstaande variant met kluis, afgeleid van het bestaande beeldmerk. Bronbestand: `logo/thoughtvault-vault-mark.png`.
- `assets/yinga-logo.svg`: officiële Yinga-vector van https://www.yinga.nl/wp-content/uploads/2023/03/logo.svg.
- `assets/macos-recording.png` en `assets/macos-processing.png`: echte appvensters vastgelegd op 7 oktober 2026. De website kadert de screenshots bij; de bestanden blijven volledig. Er is geen Windows-screenshot als live bewijs gebruikt.
- De vier geanimeerde stappen en de voorbeeldnotitie zijn illustraties, geen nagebouwde appvensters. De animatie ondersteunt pauzeren, herhalen, toetsenbordbediening en verminderde beweging.
- Obsidian-export vereist een ingestelde koppeling. Automatisch exporteren is gecontroleerd in `macos/Services/ObsidianService.swift` en de Windows-exportaanroepen.
- Alle 16 productvoordelen zijn in vier categorieën beschikbaar. Publieke downloadacties vragen de privélink aan per e-mail; demo opent een e-mailconcept. De echte downloadpagina staat achter een server-only capability URL. Geen verzonnen reviews of prestatiecijfers.

## Controle

Start vanuit de repositoryroot:

```sh
python3 -m http.server 8769 --bind 127.0.0.1
~/.claude/skills/gstack/browse/dist/browse goto http://127.0.0.1:8769/docs/design/high-end-yinga/index.html
~/.claude/skills/gstack/browse/dist/browse viewport 1440x900
~/.claude/skills/gstack/browse/dist/browse eval docs/design/high-end-yinga/verify.js
```

`landing-verification.txt` bevat controles en geometrie op zes CSS-viewports. `viewport-density-audit.md` beschrijft de dekking. Oudere lokale prototypebestanden en audits zijn niet onderdeel van deze pagina.
