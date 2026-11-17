# Herkomst van de iOS-teller bij Instellingen

Branch: `fix/ios-support-badge-20261117`, basis `origin/main` op `e06b9ec2`.

De badge op de iOS-tab Instellingen gebruikt `SupportViewModel.unreadCount`.
De route naar de betreffende meldingen stond onder Account → Over ThoughtVault →
Mijn meldingen. Daardoor vertelde de badge niet wat aandacht vroeg.

Instellingen heeft nu bovenaan een directe ingang naar de bestaande lijst
Mijn meldingen, met het aantal ongelezen antwoorden van support. De toelichting
verbindt dat aantal expliciet aan de badge en legt uit dat antwoorden ook over
automatisch verstuurde foutrapporten kunnen gaan. Nederlands en Engels zijn
bijgewerkt. Het openen van de lijst markeert geen gesprekken als gelezen.

De bestaande debugfixture voor de supportbadge gebruikt nu ook bij het openen
van de lijst en een gesprek de voorbeeldgegevens. Daardoor verstuurt deze
simulatorcontrole geen supportaanvragen naar de echte dienst.

## Verificatie

- Swift-syntaxis van gewijzigde bestanden gecontroleerd.
- Beide Localizable.strings-bestanden: plutil geslaagd; count-placeholder geldig.
- `git diff --check` geslaagd.
- Native iOS Simulator-build (arm64 en x86_64): `BUILD SUCCEEDED`.
- Native macOS SupportViewModelTests: 33 tests geslaagd, `TEST SUCCEEDED`.
  Inclusief `testUnreadBadgeRemainsUntilTheThreadIsOpened` en behoud van de
  bestaande teller/inhoud als het ophalen van een gesprek mislukt.
- iPhone 17 Pro-simulator, iOS 27.0: teller 0 en 1, uitleg zichtbaar,
  Instellingen → Mijn meldingen → TV-001 → antwoord daadwerkelijk geopend;
  terugnavigatie gecontroleerd. Screenshots en toegankelijkheidsboom bewaard.
- Grootste Dynamic Type-stand: uitleg blijft volledig leesbaar via scrollen,
  ingang en teller bereikbaar. De bestaande IOSRow-typografie blijft behouden.

De oorspronkelijke testaanvraag met alleen `platform=macOS` is uitsluitend uit
de wachtstand geannuleerd. Daarna is dezelfde test met het expliciete Mac-id
ingediend, zodat de planner de bestemming kent. De planner heeft die aanvraag
toegelaten; de andere apparaatproeven zijn niet gestopt.

De UI-controle gebruikt voorbeeldantwoorden; het werkelijk als gelezen markeren
is met de afgeschermde relaystub geautomatiseerd getest. Geen live supportbericht
verstuurd. Fysieke iPhone en TestFlight nog niet gecontroleerd.

De eigen simulator en appdata zijn verwijderd. Interne simulatorlogs eerst naar
de externe bewijsmap gekopieerd en via SHA-256 gecontroleerd, daarna verwijderd:
253.952 bytes interne opslag vrijgemaakt. Gedeelde caches en andere apparaten
zijn behouden.

Bewijs: `/Volumes/SSD/Projects/task-evidence/thoughtvault-ios-support-badge/`.
Geen versie verhoogd, push/merge, TestFlight-upload of productie-uitrol gedaan.
