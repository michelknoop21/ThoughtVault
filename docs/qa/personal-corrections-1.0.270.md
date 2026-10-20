# Persoonlijke woordcorrecties 1.0.270

Gecontroleerd op 2026-10-09. De feature is geïmplementeerd en samengevoegd met Gitea main.

## Bron en artifacts

- macOS-bron: `8d8941a` met profielgebonden herkenningshints.
- Windows-buildbron: `178e4ce39344f9bb5be70d06a817bf4e4861403e`.
- De Windows-bron, buildworkflow en Windows-verificatiescripts verschillen niet
  tussen deze twee commits. De latere wijziging is uitsluitend voor macOS.
- Windows CI: https://github.com/michelknoop21/ThoughtVault/actions/runs/37915084903
- CI-resultaat: success. `publish=false`; Upload to server is skipped.
- Beide installers blijven private kandidaten; de publieke downloadfeed is niet gewijzigd.
- Geïnstalleerd op Michels Mac en echte Windows-pc via Royal TSX op 2026-10-09.

## Geslaagde controles

- Windows frontend: 34 testbestanden, 88 tests; TypeScript en Vite productiebuild.
- Native Rust: 23 tests lokaal op macOS; 24 tests in de Windows Release-build.
- Windows: self-contained C++ runtime, MSI-installatie en upgrade, twee starts,
  behoud van opgeslagen notulen op de CI-runner.
- macOS: Swift-correctiechecks en `ARCHIVE SUCCEEDED` voor de Release-app.
- macOS-app: Apple Development-handtekening geverifieerd, sandbox ingeschakeld,
  Intel en Apple Silicon. De designated requirement komt overeen met de
  geïnstalleerde `/Applications/ThoughtVault.app`.
- macOS-DMG: checksumcontrole door hdiutil geslaagd.
- macOS: `/Applications/ThoughtVault.app` meldt 1.0.270, handtekening geldig,
  app gestart en bestaande notulen zichtbaar. Vorige appbundel lokaal bewaard.
- Windows: MSI-checksum gecontroleerd, upgrade van 1.0.269 naar 1.0.270 met
  exitcode 0. Lokale notulenback-up gemaakt; SHA-256 van de notulen onveranderd
  na installatie en appstart. Draaiende executable meldt 1.0.270 en Responding=True.
- Beide geïnstalleerde apps: Instellingen > Verwerking > Woorden en namen
  bereikbaar. Geen gebruikersnotulen gewijzigd tijdens deze controle.
- Avast CyberCapture controleerde de Windows-executable bij de eerste start;
  de controle verdween en de app werd bruikbaar zonder beveiliging te omzeilen.
- UI-fixture: geselecteerde variant wordt vooringevuld; Jengo wordt in de notule
  Yinga; ruwe transcriptie blijft Jengo. Correctievenster past bij 880 x 600
  zonder scroll of horizontale overflow; focus blijft in de dialoog.
- Componenttests: opslagfout houdt het formulier open en leert geen regel;
  alleen na succesvolle notuleopslag wordt de woordenlijst opgeslagen.
- Provider- en exporttests: gecorrigeerde afgeleide invoer, beschermde HTML/code,
  profielafbakening, terugschrijffouten en gecorrigeerde Obsidian-Markdown.

## SHA-256

- `build/ThoughtVault_1.0.270_universal.dmg`: `3d522ff5a503fe4197e8b3625d1c45a8e43208f060b5675e9e6858782a30624a`
- `build/personal-corrections-1.0.270/windows/ThoughtVault_1.0.270_x64.msi`: `6bab5344900cf8df0129fb3dedf75f6562095d0aa0df3780ecc884461f4775f4`

## Nog te verifiëren

Het opslaan en toepassen van een nieuwe woordregel in de geïnstalleerde apps
is nog niet interactief gecontroleerd. Een nieuwe opname met een echte
lokale/cloudprovider en een echte Obsidian-vault blijft open. CI-installatie
en fixtures bewijzen dat niet. De macOS-kandidaat is niet genotariseerd.

De woordenlijst blijft per apparaat; geen automatische synchronisatie. Alleen
expliciet goedgekeurde varianten worden exact vervangen. Door HTML-entiteiten of
tags opgesplitste namen blijven buiten de eerste vervangingsversie.
