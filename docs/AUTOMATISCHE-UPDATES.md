# Downloads en updates

De website beheert de pagina `/download/`; app-releases schrijven uitsluitend
bestanden en metadata naar `/releases/`. De bestaande serverdirectory is
`/home/michelk/tstudio-releases`. Het domein gebruikt HTTPS via de bestaande Caddy.
De route staat in `scripts/infra/thoughtvault-releases.caddy`; neem het
`handle_path /releases/*`-blok is opgenomen naast de proxy naar
`thoughtvault-website:80`. Behoud dit blok bij website-deployments. Maak geen tweede
Caddy-site met dezelfde host.

## Contract voor de downloadspagina

Lees `https://thoughtvault.yinga.ai/releases/releases.json`. Gebruik per platform
`windows_x64`, `windows_arm64` (alleen als beschikbaar) of `macos`, met velden
`version`, `filename`, `download_url` en `sha256`. Bestaande `url`-velden blijven
relatief aan `https://n8n.prezent.nl` voor oudere apps. Toon alleen platforms
waarvan daadwerkelijk een installer beschikbaar is; versieverschillen zijn mogelijk.

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

## Checks

- `python3 scripts/test-publish-release.py`
- `cd windows && npx vitest run && npm run build`
- `cd windows/src-tauri && cargo test --lib`
- `xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS' test`
- Verifieer op Windows een MSI-installatie, start en opname/transcriptie/export.
- Verifieer met twee daadwerkelijk verschillende releases de volledige updater,
  behoud van opgeslagen notulen/sleutels en een afgebroken of ongeldige download.
