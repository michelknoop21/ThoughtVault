# ThoughtVault: Windows-build en publicatie

Gitea (`origin`: `ssh://gitea/michelk/ThoughtVault.git`) is de bronrepository.
Een Gitea-remote betekent niet dat de Windows-build op Gitea draait.
Het bewezen buildproces gebruikt GitHub Actions in repository
`michelknoop21/ThoughtVault`, workflow `.github/workflows/build-windows.yml`.
**Controle 28 oktober 2026:** GitHub API meldt `private:false`, `visibility:public`.
Een bronpush daarheen maakt die bron openbaar en vereist afzonderlijk akkoord.
`publish=false` voorkomt serverpublicatie, maar maakt de bronrepository niet privé.
RDP en een handmatige build op een Windows-pc zijn hiervoor niet nodig.

## Bewezen uitvoering

Release 1.0.257 is gebouwd en automatisch gepubliceerd door:
https://github.com/michelknoop21/ThoughtVault/actions/runs/37617125089
Broncommit: `ce1f322712765ac75819efdf1fc0e7bb088ed6aa`.
46 frontendtests en 19 native tests slaagden. De installer is over 1.0.255
geïnstalleerd, de app startte tweemaal en bestaande notulen bleven behouden.
Dit bewijst de build-/installatieroute, niet de juiste visuele opmaak.

## Volgende release

1. Gebruik de actuele ThoughtVault-bron, niet automatisch de GitHub-defaultbranch:
   de vorige build gebruikte een tijdelijke, inmiddels verwijderde buildbranch
   met een gecontroleerde bronkopie. Een GitHub-remote hoeft niet aan de lokale
   Gitea-checkout te worden toegevoegd. Controleer de buildcommit en broninhoud.
2. Maak een nieuwe versie; 1.0.257 mag niet worden overschreven.
3. Start de workflow op die expliciete bronref, met kanaal `production`.
   De workflow bouwt op `windows-latest`, test, maakt MSI + updater-signature,
   controleert installatie en gebruikt `scripts/upload.ps1` voor publicatie.
4. Controleer dat `headSha` van de run overeenkomt met de bedoelde broncommit.
   De buildref moet de actuele ThoughtVault-code en assets bevatten. Bouw niet
   automatisch de oudere GitHub-defaultbranch. Normale tests en installatiecontrole
   zijn vereist; een visuele review is geen standaard releasevoorwaarde.
5. Controleer de CI-artifacts, de download, SHA-256, `releases/releases.json`
   en `releases/windows/stable.json` op `https://thoughtvault.yinga.ai`.

De GitHub-build gebruikt de bestaande secrets `TAURI_SIGNING_PRIVATE_KEY` en
`SSH_PRIVATE_KEY`. Print hun inhoud niet. Publicatie schrijft alleen in
`/home/michelk/tstudio-releases`; websitepagina's zijn van het websiteproject.
De website behoudt de vier updaterfeeds onder `/releases/`; installers staan uitsluitend onder het downloadpad in `docs/AUTOMATISCHE-UPDATES.md`.

Gebruik `bash scripts/deploy-dev.sh <github-ref>` of
`bash scripts/deploy-production.sh <github-ref>` om deze bestaande workflow te
starten. Deze scripts veranderen geen remotes en pushen geen broncode/tags.

## CI-kandidaat zonder serverpublicatie

De workflow heeft een boolean `publish` (standaard `true`). Gebruik voor een
installatie-/visuele controle vóór publicatie:

```bash
gh workflow run build-windows.yml --repo michelknoop21/ThoughtVault --ref <gecontroleerde-ref> -f channel=production -f publish=false
```

Dit bouwt en test de MSI op Windows en bewaart CI-artifacts; behandel die niet als vertrouwelijk op basis van deze workflow-instelling. Het verandert
geen downloadmanifest of updaterfeed. Publiceren blijft een afzonderlijke run met
`publish=true`, met de juiste broncommit en geslaagde normale controles.

## Instructies voor agents en ontwikkelaars

De gezaghebbende bronkeuze staat in `CLAUDE.md` (via `AGENTS.md`). Lees die vóór
bouwen. De GitHub-repository is een builddienst, geen reden om terug te gaan naar
oude appcode. Bij een geïsoleerde bronkopie: kopieer de actuele wijzigingen en
assets, registreer de bronhashes, dispatch die ref en controleer de CI-commit.
Gebruik de daadwerkelijk gebouwde MSI met zijn eigen versie/signature. De
website leest artifacts van de server; zij bouwt de desktopapp niet.

## Lokale testbuild zonder updaterpakket

De bestaande route `cd windows; npm run tauri:portable` voert `tauri build --no-bundle` uit. Hiermee kunnen bronfixes lokaal op Windows worden getest zonder MSI, updaterpakket of signingkey. Behoud publieke updaterkey, endpoints, updaterplugin en beveiliging. Dit bewijst geen installatie of update.

Gebruik een afzonderlijke bronkopie met herkenbare testversie en venstertitel; neem de bestaande `resources` naast de EXE mee, waaronder Faster Whisper en Nemo met hun app-local DLL's. Controleer de runtime-afhankelijkheden met `scripts/verify-windows-runtime.ps1`. Gebruik het directe npm-commando: de kopieerstap van `scripts/build.ps1 -Portable` noemt nog de oude binarynaam `transcript-studio.exe`.

Bouw met aanwezige toolchain, caches en runtimes. Een ontbrekend model of nieuwe toolchaininstallatie eerst voorleggen; deze route vraagt geen nieuwe sleutel. Houd de geïnstalleerde versie en beide appdatamappen met back-up beschikbaar voor herstel.

## Lokale pilot-MSI met bestaande releasekey

Voor de pilot van 29 oktober geldt de expliciet gekozen Dalf38-route; geen
GitHub-push of workflowdispatch. De bestaande private Windows-updaterkey staat
beschreven in [AUTOMATISCHE-UPDATES.md](AUTOMATISCHE-UPDATES.md). Controleer eerst
met een proefhandtekening of deze bij de publieke sleutel in Tauri-config hoort.
De key hoeft niet naar Windows: de bestaande Tauri-signer op de Mac kan de
ongewijzigde Windows-MSI ondertekenen met `signer sign --private-key-path`.

Bouw vanuit een gehashte bronkopie met gesynchroniseerde `VERSION`, Tauri- en
Cargo-versie (inclusief de eigen package-entry in `Cargo.lock`). Behoud
`createUpdaterArtifacts: true`, productie-ID, publieke key en endpoints. Gebruik
alleen aanwezige npm/Cargo- en WiX-caches en bestaande, gehashte resources;
de `prepare-*-runtime.ps1`-scripts downloaden/bouwen runtimes en zijn hier geen
voorbereidingsstap. WiX staat bij `useLocalToolsDir: true` onder
`windows/src-tauri/target/.tauri/WixTools314`; een bestaande gebruikerscache kan
byte-identiek daarheen worden gekopieerd.

`npm run tauri -- build --bundles msi --ci` bouwt de MSI. Zonder signingkey op
Windows kan de afsluitende updater-signingstap falen nadat de MSI is gemaakt.
Dit is nog geen geslaagde pakketbouw of leverbaar bestand: bewaar de exitcode en
log, breng precies die MSI met hashcontrole naar de Mac, onderteken daar met de
bestaande key en verifieer zowel signature als trusted comment met de publieke
productiesleutel. Een gewijzigde MSI-testkopie moet worden afgewezen. Lever alleen
het gecontroleerde MSI/`.sig`-paar, broncommit, SHA-256-manifest en bewijsrapport.
Ontbreekt een geldige handtekening, dan stopt de levering.

Updaterondertekening is geen Windows-uitgeverssignering of antivirusacceptatie.
Een beveiligingsblokkade wordt vastgelegd; een ontbrekende/quarantaine-worker
wordt niet voor een nieuwe test teruggezet of vervangen. De inhoudscontrole en
volledige installatie-/werkketenacceptatie blijven afzonderlijke voorwaarden.
