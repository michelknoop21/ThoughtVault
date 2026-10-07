# ThoughtVault — build en release

## Windows

De bron staat op Gitea; de bewezen MSI-runner is GitHub Actions in
`michelknoop21/ThoughtVault`. Volg [WINDOWS-BUILD-WORKFLOW.md](WINDOWS-BUILD-WORKFLOW.md).
De workflow test, bouwt MSI + updater-signature, verifieert installatie en gebruikt
`scripts/upload.ps1` voor automatische publicatie.

Gebruik een expliciete bronref met de huidige wijzigingen. De GitHub-defaultbranch
is geen bewijs dat de actuele Gitea-bron wordt gebouwd. Een push naar `origin`
start geen GitHub-build. Voor een reeds aanwezige, gecontroleerde GitHub-ref:

```bash
bash scripts/deploy-dev.sh <github-ref>
bash scripts/deploy-production.sh <github-ref>
```

Deze scripts dispatchen alleen de ThoughtVault-workflow. Ze voegen geen remote toe,
pushen geen broncode of tags en gebruiken geen GitLab.

Publicatie vereist een geslaagde visuele releasecontrole:
`python3 scripts/check-windows-design.py`. Ontbrekend bewijs blokkeert ook
handmatige uploads. Zie [de controle](design/windows/README.md).

## Mac

```bash
bash scripts/sync-version.sh
APPLE_NOTARY_PROFILE=<keychain-profiel> bash scripts/build-macos-release.sh
BUILD_CHANNEL=production bash scripts/upload.sh
```

De bestaande bundle-ID, sandbox, Keychain en toegangstoestemmingen blijven behouden.
Een openbare build vereist Developer ID Application, hardened runtime,
notarization/stapling en een Sparkle-signature. Lokale ontwikkeling gebruikt de
bestaande Apple Development identity; publiceer die build niet als distributie.

## Website en updates

Releases verschijnen onder `https://thoughtvault.yinga.ai/releases/`.
De pipeline beheert artifacts, `releases.json` en platformfeeds. Websitepagina's
worden door het websiteproject beheerd. Bewaar de `/releases/*`-route bij deploys.
Zie [AUTOMATISCHE-UPDATES.md](AUTOMATISCHE-UPDATES.md).

Gepubliceerde versies zijn onveranderlijk: maak een nieuwe versie voor herstel.
Versiesynchronisatie verhoogt het Mac-buildnummer eenmaal per nieuwe versie.
Historische interne opslag-ID's en bestaande OAuth-registraties zijn compatibiliteit,
geen productnaam. Hernoem ze alleen met een afzonderlijk geteste migratie.
