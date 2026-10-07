# ThoughtVault: Windows-build en publicatie

Gitea (`origin`: `ssh://gitea/michelk/ThoughtVault.git`) is de bronrepository.
Een Gitea-remote betekent niet dat de Windows-build op Gitea draait.
Het bewezen buildproces gebruikt GitHub Actions in de private repository
`michelknoop21/ThoughtVault`, workflow `.github/workflows/build-windows.yml`.
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
4. Voor publieke upload moet `scripts/check-windows-design.py` slagen volgens
   `docs/design/windows/README.md`. Het huidige herstel staat op `pending` en
   mag dus nog niet worden gepubliceerd. De nieuwe gate is broncode in deze
   checkout; hij stond nog niet in de uitgevoerde 1.0.257-workflow.
5. Controleer de CI-artifacts, de download, SHA-256, `releases/releases.json`
   en `releases/windows/stable.json` op `https://thoughtvault.yinga.ai`.

De GitHub-build gebruikt de bestaande secrets `TAURI_SIGNING_PRIVATE_KEY` en
`SSH_PRIVATE_KEY`. Print hun inhoud niet. Publicatie schrijft alleen in
`/home/michelk/tstudio-releases`; websitepagina's zijn van het websiteproject.
De website moet `/releases/*` blijven doorsturen naar de releasebestanden.

Gebruik `bash scripts/deploy-dev.sh <github-ref>` of
`bash scripts/deploy-production.sh <github-ref>` om deze bestaande workflow te
starten. Deze scripts veranderen geen remotes en pushen geen broncode/tags.
