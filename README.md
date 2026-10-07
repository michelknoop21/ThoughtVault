# ThoughtVault

Desktopapp van Yinga voor opnames, lokale transcriptie en notulen. Audio en notulen
blijven lokaal opgeslagen. Voor notulengeneratie kiest de gebruiker lokale AI of
een cloudprovider. Er is geen ThoughtVault-account of eigen backend nodig.

- **Bronrepository:** `ssh://gitea/michelk/ThoughtVault.git` (`origin`).
- **Windows-build:** GitHub Actions in `michelknoop21/ThoughtVault`, workflow
  `.github/workflows/build-windows.yml`; geen RDP of Gitea CI nodig.
- **Website en downloads:** https://thoughtvault.yinga.ai.
- **Versie:** `VERSION`.

## Ontwikkelen en testen

Mac: Swift 6, SwiftUI en SwiftData. Bouw gesandboxed en met de bestaande signing
identity, zodat gegevens en toegangsrechten behouden blijven:

```bash
xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug -allowProvisioningUpdates build
xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS' test
```

Windows: Tauri 2, Rust, React en TypeScript. Native opnamecontrole vereist Windows.

```bash
cd windows
npm ci
npx vitest run
npm run build
npm run tauri dev
```

## Bouwen en publiceren

Lees [het Windows-buildproces](docs/WINDOWS-BUILD-WORKFLOW.md),
[release-instructies](docs/RELEASE.md) en
[downloads en updates](docs/AUTOMATISCHE-UPDATES.md).
Gitea is de bron; de Windows-runner staat op GitHub. Bouw altijd een expliciete,
gecontroleerde bronref. Een tag naar Gitea alleen start geen GitHub-build.

Controleer vóór dispatch dat de expliciete buildref de actuele ThoughtVault-bron
bevat. Leg de commit vast en vergelijk hem met `headSha` van de CI-run. Bouw geen
oude defaultbranch en gebruik geen vorige installer voor een nieuw versienummer.
Normale tests en installercontroles volstaan; geen standaard visuele releasegate.

Mac-distributie vereist Developer ID signing en notarization. Een lokaal
Apple Development-build is geen openbare distributiebuild.

## Project

`macos/`: native app. `windows/`: Windows-app. `ThoughtVaultTests/`: native tests.
`data/`: gedeelde gegevens. `scripts/`: builds en publicatie. `docs/`: documentatie.
Lees `CLAUDE.md` vóór projectwerk.
