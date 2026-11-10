# Downloads en updates

De enige downloadspagina is `https://thoughtvault.yinga.ai/d-05921304471ce66e62d0a2b7f324c2354dfb1d895d23a895bba7f86110e2472e/`.
Installers en `releases.json` worden alleen via dit pad aangeboden. De bestaande
serverdirectory blijft `/home/michelk/tstudio-releases`.

De route in `scripts/infra/thoughtvault-releases.caddy` laat onder `/releases/`
alleen de vier updaterfeeds door. Andere oude release-/downloadpaden geven 404.
Behoud deze feedroutes naast de websiteproxy bij deployments.

## Contract voor de downloadspagina

Lees `releases.json` relatief aan de downloadspagina. Per platform staan
`version`, `filename`, `download_url` en `sha256` in de metadata. Beide URL-velden
verwijzen naar het downloadpad. Toon alleen beschikbare installers.

Windows leest `/releases/windows/stable.json` via Tauri; macOS leest
`/releases/macos/stable.xml` via Sparkle. Development gebruikt `dev.json` en
`dev.xml`. Nieuwere Windows-metadata wijzigt het globale `latest_version` niet:
oudere Macs gebruiken dat veld en mogen geen niet-bestaande Mac-update aanbieden.

## Release

`VERSION` is de productversie. Het Mac-buildnummer loopt bij iedere nieuwe versie
op; synchronisatie van dezelfde versie verhoogt het nummer niet opnieuw.
`bash scripts/sync-version.sh` synchroniseert de versies.

Gitea is de bronrepository. `.github/workflows/build-windows.yml` in
`michelknoop21/ThoughtVault` is het bewezen Windows-buildproces. Tests en builds moeten slagen vóór upload. De uploader zet
bestanden in een tijdelijke serverdirectory, valideert de gehele batch en
publiceert onder een lock. Feedbestanden en `releases.json` worden atomair vervangen.
Een reeds gepubliceerd bestand mag niet onder dezelfde naam worden gewijzigd.
De pipeline uploadt geen websitepagina's of screenshots.

Windows vereist `TAURI_SIGNING_PRIVATE_KEY` (en, indien ingesteld,
`TAURI_SIGNING_PRIVATE_KEY_PASSWORD`). De openbare sleutel staat in Tauri-config.
De Windows-private sleutel is lokaal beveiligd opgeslagen in Keychain:
service `ThoughtVaultReleaseKeys`, account `windows`; de buildkopie heeft mode 0600
onder `~/Library/Application Support/ThoughtVaultReleaseKeys/windows.key`.
GitHub heeft een afzonderlijke SSH-sleutel voor releasepublicatie; geen forwarding
of PTY is toegestaan. Behandel de CI als vertrouwd: de publicatiesleutel heeft
SSH-exec-toegang als de bestaande deploymentgebruiker `michelk`.

Mac-publicatie vereist een **Developer ID Application**-certificaat van team
`XL9KN38ATX`, een via `notarytool store-credentials` opgeslagen Keychain-profiel
(`APPLE_NOTARY_PROFILE`) en de Sparkle-signingsleutel (Keychain-account
`ThoughtVault`). `scripts/build-macos-release.sh` archiveert/exporteert met signing,
notariseert en stapelt app en DMG en genereert de Sparkle-signature metadata.
De publicatie weigert een DMG zonder geslaagde notarization. Een lokale
Apple Development-build is voor de geïnstalleerde eigen Mac, niet voor distributie.

Behoud Mac-bundle-ID `com.buildmind.ThoughtVault`, sandbox en Keychain-groepen;
Windows behoudt `nl.prezent.transcript-studio`. Bestaande notulen en sleutels
blijven daardoor bereikbaar. De eerste Mac-versie met Sparkle moet eenmalig via
DMG worden geïnstalleerd; oude Macs kunnen zichzelf nog niet vervangen.

## Bijwerken op Windows

Met "Automatisch bijwerken" aan controleert de app bij het starten en daarna
elke zes uur op updates. Een beschikbare native update wordt op de achtergrond
in het geheugen gedownload; na opnieuw starten moet het pakket opnieuw worden
gedownload als het nog niet is geïnstalleerd. De banner meldt wanneer de download
klaar is.

Bij het afsluiten van het hoofdvenster installeert de app een volledig gedownloade
update, zolang "Automatisch bijwerken" aan staat en er geen opname of verwerking
loopt. Tijdens opnemen of verwerken wordt bij afsluiten geen update geïnstalleerd.
De Windows-installer gebruikt `passive`: een klein voortgangsvenster.

Instellingen > Algemeen bevat de schakelaar "Automatisch bijwerken" en de knop
"Zoek naar updates". Die knop verstuurt `tv-check-updates` en werkt ook wanneer
automatisch bijwerken uit staat; dan volgt geen automatische download of
installatie bij afsluiten. Met "Nu bijwerken" in de banner kan de gebruiker een
native update handmatig downloaden en installeren als de app niet bezig is.

Gebruik voor het dev-kanaal de GitHub-workflow met `channel=dev` via
`bash scripts/deploy-dev.sh <geverifieerde-github-ref>`. Die bouwt "ThoughtVault
Dev" met ID `nl.prezent.transcript-studio-dev` en endpoint
`https://thoughtvault.yinga.ai/releases/windows/dev.json`. De huidige GitLab-route
wijzigt alleen naam en ID en houdt daardoor het standaardendpoint `stable.json`;
zij is niet geschikt voor dit dev-bewijs. De bestaande manifestcontrole blijft
een fallback voor een downloadlink; die bewijst geen native update-installatie.

**Bewijsstatus:** het automatische herstartgedrag van de eigen WiX-installer is
nog niet op Windows geobserveerd. Ook de volledige native update van N naar N+1
met behoud van notulen en instellingen is nog niet uitgevoerd. Vul het feitelijke
herstartgedrag en de bewijsverwijzingen pas na de twee onderstaande dev-rondes in.

## Checks

- `python3 scripts/test-publish-release.py`
- `cd windows && npx vitest run && npm run build`
- `cd windows/src-tauri && cargo test --lib`
- `xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS' test`
- Verifieer op Windows een MSI-installatie, start en opname/transcriptie/export.
- Verifieer met twee daadwerkelijk verschillende releases de volledige updater,
  behoud van opgeslagen notulen/sleutels en een afgebroken of ongeldige download.

Voor fase D horen daar twee echte dev-rondes met verschillende releases N en N+1
bij, in deze volgorde:

1. Installeer N en wacht op de banner dat N+1 is gedownload. Start een opname en
   sluit het hoofdvenster. Er mag geen installer verschijnen; na opnieuw openen
   moet Instellingen nog N tonen. Bewaar banner- en versiebeelden.
2. Wacht opnieuw op de gedownloade N+1-banner en sluit zonder opname of verwerking.
   Leg het `passive`-installervenster vast en controleer daarna N+1, bestaande
   notulen en instellingen. Noteer of de app vanzelf herstart of handmatig moest
   worden geopend. Bewaar het versiebeeld en de workflow-URL's van N en N+1.

Mocktests en browserbeelden tellen niet als dit native N-naar-N+1-bewijs. Beide
rondes staan nog open. Deze Windows-fase wijzigt geen Swift; de macOS-test hierboven
hoort bij het afzonderlijke macOS-deel.
