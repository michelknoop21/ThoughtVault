# ThoughtVault pilot — 5 november 2026

## Besluit

**NIET GEREED VOOR UITROL.** Lokale code-integratie en regressietests zijn afgerond;
Windows-native acceptatie, inhoudskwaliteit, herstel en distributie zijn niet bewezen.
Gebruiker heeft iPhone/iPad-acceptatie uitgesteld en Dalf38 via RustDesk aangewezen.
Er is niets gepubliceerd, geïnstalleerd op gebruikersapparaten of aan collega's verstuurd.

## Kandidaat en herkomst

Werkbranch `codex/pilot-readiness-20261105`, geïsoleerd in
`/Volumes/SSD/codex-worktrees/thoughtvault-pilot-20261105`.
Integreert uitgangscommit `fd98691` met auditbranch `71dab28` (124 ontbrekende commits).
Oorspronkelijke werkmap en ongecommitte gebruikerswijzigingen zijn behouden.
De auditbranch had alleen `.router/` en een sessieverslag ongecommit; deze zijn niet overgenomen.

Conflicten: latere SiriWave/frequentie-implementatie en tests uit auditbranch behouden;
huidige website HTML/CSS/JS en website-inspectiescript uit uitgangsbranch behouden.
NVIDIA-bestanden in de integratie zijn de reeds gecommitte Parakeet-runtime-integratie,
geen losse werkmapexperimenten. Dit blijft een brede integratie die native hertest vereist.

Aanvullende correcties:
- DOMPurify-lockversie bijgewerkt binnen bestaande dependencygrens wegens kritieke auditmelding.
- `testflight.sh [ios|macos|all] --no-upload`: lokale export zonder upload; onbekende argumenten falen.
- `build.sh`: pipefail voorkomt dat een mislukte Xcode-build door `tail` wordt verborgen.
- Swift-testcommando gebruikt het bestaande schema ThoughtVault.
- Verouderde providertest aangepast aan de bestaande gedeelde Ollama lokaal/cloud-keuze.
- Apple-versies gesynchroniseerd met VERSION 1.0.296. Dit is een bronkandidaat,
  niet hetzelfde artifact als de historische MSI 1.0.296. Voor distributie een nieuwe unieke versie vastleggen.

## Actueel bewijs

| Controle | Resultaat | Bewijs / grens |
|---|---|---|
| Windows frontend | PASS | 50 bestanden, 209 tests; 1 opt-in modelkwaliteitstest overgeslagen |
| TypeScript/Vite | PASS | `npm run build`; bundel-/Browserslistwaarschuwingen |
| Productiedependencies | PASS | `npm audit --omit=dev`: nul kwetsbaarheden; development-audit niet schoon |
| Scriptregressies | PASS | `python3 -m unittest discover -s scripts/tests -v`: 8 tests |
| macOS tests | PASS | 69 PASS, 3 SKIP; `/tmp/thoughtvault-pilot-swift-final.log` en xcresult in `/tmp/thoughtvault-pilot-derived/Logs/Test` |
| iOS compilatie | PASS | `/tmp/thoughtvault-pilot-ios.log`; unsigned generic iOS build, vóór uitsluitend Apple-versiesync |
| Native Windows x64 | BLOCKED | Dalf38 via RustDesk gevraagd; lokale schermbediening door macOS geweigerd |
| iPhone/iPad | UITGESTELD | Expliciete gebruikerskeuze; geen apparaatacceptatie claimen |
| macOS distributie | BLOCKED | Apple Development/Distribution aanwezig, geen Developer ID in actuele identitycheck |
| Website visueel | NOT TESTED | Inspectiescript vereist browsercontext; Node-aanroep was ongeldig, geen productfout bewezen |

De eerste Swift-run vond een verouderde verwachting dat Ollama Cloud een eigen tegel
heeft; de app biedt die via het gedeelde locatiepaneel. Na aanpassing volledige suite groen.
Drie opt-in hardwaretests zijn geen PASS. Bestaande Windows-bewijsstukken gelden uitsluitend
voor hun eigen historische bron/pakket, niet automatisch voor deze integratie.

## Verplichte native matrix

Voer iedere rij afzonderlijk op macOS en Windows uit; iOS/iPadOS volgen later.
Elke uitvoering legt commit/pakkethash, fixture, stappen, werkelijk resultaat en bewijs vast.
Alle onderstaande rijen zijn voor deze kandidaat **NOT TESTED**, tenzij BLOCKED vermeld.

| ID | Scenario / verwacht resultaat |
|---|---|
| N01 | Schone installatie, onboarding, lokale route zonder verplichte login; rechten weigeren en herstellen |
| N02 | Alle navigatie, home-acties, personen, profielen, zoeken/filteren; lege/loading/foutstatus bruikbaar |
| N03 | Microfoon/systeem/gecombineerd waar aangeboden; pauze/hervatten/stop, widget en juiste duur; bron hoorbaar |
| N04 | Alle geclaimde importformaten, stilte, ongeldig bestand, annuleren; bronbestand blijft behouden |
| N05 | Iedere aangeboden engine downloaden/selecteren/herstarten/gebruiken; echte engine-identiteit, geen stille fallback |
| N06 | Transcriptie en notulen met standaard/eigen profiel; brongetrouwe feiten, onzekerheden, bedragen en afspraken |
| N07 | Bewerken/regenereren/heropenen; has_notes consistent, afgewezen concept apart, bestaande inhoud intact |
| N08 | Taken/progress/resultaatlinks; gelijktijdige jobs, fout/annuleren/retry zonder dubbelen of schijnsucces |
| N09 | Bibliotheek en audio, verwijderen met annulering; alle exportformaten inhoudelijk controleren |
| N10 | Instellingen/providerkeuzes en credentials blijven behouden; validatie en annuleren correct |
| N11 | Eigen agenda-event en Obsidian-testmap; ontbrekende toegang BLOCKED |
| N12 | Tien opeenvolgende korte runs, verdeeld over echte opname en import; unieke opslag en heropening |
| N13 | Minimaal één uur opname; volledige audio/tekst, geheugen/procesboommeting over volledige keten |
| N14 | Geïsoleerde netwerk/provider/model/schrijffout; crash/onderbreking; echt hervatten zonder dataverlies |
| N15 | Verse back-up van werkelijk gebruikte stores; upgrade en herstel met tellingen/hashes aantonen |
| N16 | Toetsenbord/focus/toegankelijkheid; Windows 100/125/150%, klein/groot venster; native waveform met bewegend bewijs |
| N17 | Gedownload distributiepakket, identiteit, signing, installatie en rollback; hashes en bron herleidbaar |

## Eerstvolgende uitvoering

1. RustDesk-bediening herstellen. Zowel codex-daemon als osascript kregen volgens gebruiker
   Toegankelijkheidstoestemming, maar verse probes blijven -25211 teruggeven. Geen TCC-reset of bypass.
   Herstart host/achtergrondproces via de gebruiker, daarna opnieuw verse observatie.
2. Dalf38 observeren: identiteit, appversie, idle opname/taken en gebruikerswerk vaststellen.
   Geen blind terminaltypen of onderbreken van actieve verwerking.
3. Bestaande Windows-buildworkflow volgen met nieuwe bronmap, source-only ZIP en SHA-256;
   `npm ci`, Vitest, frontendbuild, native Rust-tests en runtime/packageverificatie uitvoeren.
4. Eerst actuele inhoudelijke baseline met synthetische Nederlandse fixtures en bestaande provider.
   Historische Opname10-afwijzing blijft blocker; modelcontrole-hulpmiddeltests bewijzen geen inhoudskwaliteit.
   Productfix pas na reproduceerbare baseline; geen privé-audio of credentials in bewijs.
5. Alleen na pakketchecks, idle app en geverifieerde back-up installeren. Matrix invullen;
   huidige checks niet vervangen door historische PASS. Signing en herstel blijven aparte gates.

## Collega-handleiding — concept, nog niet verspreiden

Installeer uitsluitend het vrijgegeven pakket met bijbehorende versie/hash.
Maak eerst een korte eigen testopname, controleer transcript en notulen tegen de opname,
heropen het resultaat na herstart en probeer export. Controleer namen, cijfers en afspraken
zelf vóór gebruik. Meld platform, versie, stappen en foutmelding; stuur geen vertrouwelijke
opname mee. Stop bij verdwenen gegevens of vastgelopen opname en bewaar de bronbestanden.
Pilot: 3–5 collega's, vijf werkdagen, pas na afzonderlijke vrijgave en groene native gates.

## Vervolg 5 november, 11:40–11:45

Toegankelijkheid is inmiddels bruikbaar na toestemming voor Supacode: verse
System Events-proef kan RustDesk-venster `Dalf38@desktop-98b3ahb` lezen.
Remote desktop zichtbaar; er is een aparte PowerShell-tab geopend naast de bestaande
gebruikerswerk-tab. Geen installatie, providerwijziging of build uitgevoerd.
Muisinvoer via native events werkt; toetsenbordinvoer kwam onvolledig/afwijkend aan.
Een onverwachte, niet uitgevoerde commandoregel is waargenomen. Invoer gestopt en
exclusief gebruik van deze remote sessie bij de gebruiker nagevraagd. Native
appversie, idle-status en Windows-kandidaatacceptatie blijven onbewezen.
