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

## Private kandidaat vóór publicatie

De workflow heeft een boolean `publish` (standaard `true`). Gebruik voor een
installatie-/visuele controle vóór publicatie:

```bash
gh workflow run build-windows.yml --repo michelknoop21/ThoughtVault --ref <gecontroleerde-ref> -f channel=production -f publish=false
```

Dit bouwt en test de MSI op Windows en bewaart private CI-artifacts. Het verandert
geen downloadmanifest of updaterfeed. Publiceren blijft een afzonderlijke run met
`publish=true`, met de juiste broncommit en geslaagde normale controles.

## Instructies voor agents en ontwikkelaars

De gezaghebbende bronkeuze staat in `CLAUDE.md` (via `AGENTS.md`). Lees die vóór
bouwen. De GitHub-repository is een builddienst, geen reden om terug te gaan naar
oude appcode. Bij een geïsoleerde bronkopie: kopieer de actuele wijzigingen en
assets, registreer de bronhashes, dispatch die ref en controleer de CI-commit.
Gebruik de daadwerkelijk gebouwde MSI met zijn eigen versie/signature. De
website leest artifacts van de server; zij bouwt de desktopapp niet.
