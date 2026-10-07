# Windows-opmaak: releasecontrole

De huidige Mac-app is de visuele referentie. De oude Windows-indeling is geen
referentie. Home gebruikt `../home/thoughtvault-home-northstar-approved.png` en
`macos/Views/HomeView+*.swift`; Opnemen gebruikt `macos/Views/RecordingView+*.swift`.
De definitieve productafbeelding is `logo/thoughtvaultlogo.png`.

## Voor elke release met presentatieveranderingen

1. Controleer de echte Windows-app bij 1280×800 en 150% schermschaal: Home,
   Opnemen (idle, actief en pauze), Notulen en Instellingen. Vergelijk naast de
   huidige Mac-app. Controleer ook scrollen, focus en bereikbaarheid van acties.
2. Bewaar screenshots onder deze directory. Geen mockup of ander platform als
   Windows-bewijs gebruiken.
3. Vul `verification.json` met status `reviewed`, SHA-256 van alle relevante
   Mac- en Windows-presentatiebestanden (componenten, stylesheets, logo), en
   `screenshots` met sleutels `home`, `recording`, `transcripts`, `settings`, ieder
   met `path` (relatief aan repo-root) en `sha256` van het PNG-bestand.
4. Run `python scripts/check-windows-design.py`. Een gewijzigde bron of ontbrekend
   bewijs blokkeert publicatie. Update de hashes nooit automatisch in CI.

De eerste herstelreview staat op `pending`: nieuwe presentatiecode is nog niet
visueel geverifieerd op Windows. Dit blokkeert bewust een nieuwe openbare release.
Een screenshotcontrole vermindert regressies; zij garandeert geen foutloze UI.
