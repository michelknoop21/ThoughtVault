# Desktop-updatemeldingen — implementatie en bewijs

Bron: aparte worktree `thoughtvault-update-meldingen`, branch
`feat/update-meldingen-20261117`, gebaseerd op main `f9ff3e1e` (1.0.329).
Geen versie gewijzigd, release gepubliceerd of bestaande installatie vervangen.

De goedgekeurde desktopmelding en het detailvenster zijn ingebouwd voor macOS
en Windows. De melding blijft na wegklikken beschikbaar in Instellingen; de
zijbalk toont een update-indicator. Tijdens opname/verwerking is installeren
geblokkeerd; een download-/installatiefout blijft zichtbaar en kan opnieuw worden geprobeerd.
Er is geen nieuwe iOS-updatemelding toegevoegd.

macOS gebruikt Sparkle zodra die een geldige kandidaat geeft. Daarnaast leest de
app de platformspecifieke manifestentry (stable/dev), uitsluitend voor een strikt
nieuwere versie. Bij een ontbrekende Sparkle-feed kan een DMG worden aangeboden.
Alleen eenvoudige DMG-bestandsnamen binnen de bestaande privédirectory zijn
mogelijk. Voor openen in de browser wordt de URL met HEAD gecontroleerd; een
redirect, ontbrekend bestand of hernieuwde opname blokkeert de stap. De gebruiker
rondt de DMG-installatie af volgens de instructies. TestFlight/App Store-builds
blijven via Apple bijwerken.

Windows houdt een native updaterkandidaat en de daarbij horende versie bij elkaar.
Ook een reeds lopende manifestaanvraag mag die kandidaat niet overschrijven.
De MSI-terugval kiest x64/ARM64 op basis van de native Rust-architectuur en weigert
onbekende architecturen, oudere versies, vreemde origins, paden en bestandstypen.
Native updates blijven de bestaande ondertekeningscontrole gebruiken.

## Uitgevoerde controles

- `npx vitest run` voor useUpdateCheck, UpdateBanner, GeneralTab en Sidebar:
  **71 tests geslaagd**.
- `npx tsc --noEmit`: geslaagd.
- `npm run build`: geslaagd (bekende waarschuwing over chunkgrootte).
- `xcodebuild test`, scheme ThoughtVault, macOS, alleen UpdateCheckServiceTests:
  **TEST SUCCEEDED**, zeven tests. Inclusief fallback bij ontbrekende Sparkle-feed,
  geen downgrade naar oude Mac-DMG, URL-begrenzing, opnameblokkade,
  HTTP-fouten en openen/herproberen. Native app en SwiftUI-wijzigingen gecompileerd.
- `python3 scripts/tests/test_windows_installer.py`: drie tests geslaagd.
- Echte Windows-React-componenten in de bestaande Sidebar/HomePage/CSS via lokale
  HTTP-preview bekeken: detailvenster, Escape, focusherstel en blokkade tijdens
  opnemen gecontroleerd. Previewbestanden en server daarna verwijderd/gestopt.

Bewijs: `/Volumes/SSD/Projects/task-evidence/thoughtvault-updates-implementation/`.

## Open acceptatie en distributie

Een native Windows-build is niet uitgevoerd. Dalf38 was bereikbaar en de bestaande
Rust-toolchain aanwezig, maar `heavy run --host dalf38` weigerde de taak met
`command has no validated Dalf38 profile` (exit 75). De planner is niet omzeild.
De twee ongebruikte stagingbestanden zijn na SHA-256-vergelijking verwijderd.

Voor distributie blijven native Windows-compilatie en de echte N-naar-N+1-test
met behoud van notulen/instellingen nodig. Mocktests en een webbuild bewijzen die
installatie niet. Ook een echte Sparkle-installatie is in deze taak niet uitgevoerd.

De live Mac-manifestentry bood bij controle nog 1.0.242 aan; de Sparkle-stablefeed
was 404. Er is daarom bewust geen Mac-update verzonnen. Een nieuw gesigneerd en
gecontroleerd installatiebestand moet eerst worden gepubliceerd. Bestaande apps
krijgen deze nieuwe UI pas met een nieuwe native release; oude Macs zonder updater
hebben daarvoor een eenmalige handmatige installatie nodig.

Ontwikkelbestanden, builds en bewijs staan op de externe SSD. Geen interne
ontwikkelmap aangemaakt; de gebruikte bestaande toolinstallaties/caches blijven staan.
