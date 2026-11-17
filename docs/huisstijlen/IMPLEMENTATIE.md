# Huisstijlen — implementatie en verificatie, 17 november 2026

De bronimplementatie staat op `feat/document-huisstijlen-20261117` in `/Volumes/SSD/Projects/thoughtvault-huisstijlen`, gestart vanaf actuele `origin/main` op `f9ff3e1e`. Er is niets gepubliceerd of naar een remote gepusht.

Het kant-en-klare importbestand is [Yinga.tvhuisstijl](Yinga.tvhuisstijl). De app biedt daarnaast **Yinga toevoegen**. Zie [de gebruiksinstructie](README.md).

## Wat is aangesloten

- Instellingen en notulekeuze op Windows, macOS en iOS/iPadOS, inclusief beheer, live voorbeeld, standaard, dupliceren, import/export en versies.
- Optionele snapshots op SwiftData, Swift/TypeScript-overdrachtsmodellen en de bestaande Apple-syncpayload. Oude notulen zonder snapshot houden hun weergave. Nieuwe notulen bewaren ook voor Standaard ThoughtVault een versie-1 snapshot.
- Resultaat, archief en inhoudseditor. Alleen de inhoud is bewerkbaar; documentassets blijven in de huisstijl. Wijzigingen aan de bibliotheek veranderen opgeslagen snapshots niet.
- Gedeelde HTML/CSS, gebundelde `docx`-export en A4-paginering. Apple-PDF gebruikt afzonderlijke WebKit-pagina's op A4 en macOS drukt de geproduceerde PDF af. iOS deelt een echt PDF-bestand.
- Lokale fontbestanden en originele SIL OFL-licenties; vier ongewijzigde Yinga-assets uit Prospect Flow. Alle vier afbeeldingen zijn byte voor byte met hun bron vergeleken. Alle acht TTF-bestanden hebben `OS/2.fsType=0` voor embedding.
- Tauri krijgt alleen de bestaande opslaanroute met binaire schrijfrechten voor het door de gebruiker gekozen bestand. macOS krijgt de print-entitlement. Geen externe assets of scripts uit imports.

## Uitgevoerd bewijs

Bewijsmap: `/Volumes/SSD/Projects/task-evidence/thoughtvault-huisstijlen/`.

| Controle | Resultaat | Bewijs |
|---|---|---|
| Windows TypeScript en productiefrontend | Geslaagd | `windows-build.log` |
| Volledige Windows-testsuite | 819 geslaagd, 2 bestaande tests overgeslagen | `windows-all-tests.log` |
| Gedeelde module | 7 geslaagd | `shared-tests.log` |
| Beheer in echte browser | Toevoegen, hernoemen, versies, standaard, dupliceren, verwijderen, import/export; ongeldige import en schijffout behouden opgeslagen data | `browser-editor.log` |
| Windows-instellingen in bestaande app-shell | Huisstijleditor en Yinga-voorbeeld bekeken | `windows-shell.jpg`, `browser-shell.log` |
| Telefoonformaat | 390 px breed, geen horizontale overflow, wissel instellingen/voorbeeld | `browser-mobile.log`, `yinga-mobile-fixed.jpg`, `yinga-mobile-preview.jpg` |
| Korte/lange browsernotulen | 2/17 pagina's; lange notule behoudt alle tekst, 120 actierijen en 30 lijstpunten | `test/fixtures.json`, `test/fixture.html`, exports in bewijsmap |
| Native macOS WebKit met productresources | 17 pagina's, 120 actierijen, geen overflow; PDF en DOCX geproduceerd | `webkit.log`, `webkit-long.pdf`, `webkit-long.docx`, `webkit-long.html` |
| PDF-geometrie | 17 pagina's, 595.276 × 841.89 pt, A4 | `pdfinfo`; pagina-afbeeldingen `native-pdf-01.png`, `native-pdf-02.png` |
| Microsoft Word | Korte en definitieve lange export daadwerkelijk geopend. Lange export heeft 13 pagina's, een bewerkbare tabel met 121 rijen inclusief kolomkoppen en juiste fonts/afbeeldingen. Tekst aan documenteinde toegevoegd en ongedaan gemaakt; beide documenten gesloten | Waargenomen via native UI, `word-check.txt` in bewijsmap |
| Nieuwe Apple-componenten | Swift 6-typecontrole geslaagd voor macOS en iOS-simulator-SDK, met kleine afhankelijkheidsstubs; dit is geen volledige appbuild | `static-view-typecheck.log`, `static-ios-typecheck.log`, stubs onder `static/` |
| Aangepaste bestaande Swift-bron en XCTest | Syntaxis gecontroleerd | `swift-parse.log` |
| Xcode-resources en plists | Geldige plists; nieuwe services, view en Document-folder in beide app-targets; XCTest in testtarget | `plutil`, gecontroleerde targetlidmaatschappen |

De native controle is reproduceerbaar met:

```sh
scripts/tests/document-webkit-smoke.sh /Volumes/SSD/Projects/task-evidence/thoughtvault-huisstijlen
```

De browserfixtures horen achter een lokale HTTP-server. De testservers zijn na afronding gestopt.

## Nog open voor acceptatie

De volledige Apple-appbuild kon niet starten doordat de gedeelde buildwachtrij exclusief bezet was door `thoughtvault-two-hour-physical` uit een andere sessie. Alleen de eigen wachtende build is geannuleerd; er blijft geen latere buildtaak van deze implementatie achter. De andere proef is niet onderbroken. Er is dus geen `BUILD SUCCEEDED` of uitgevoerde nieuwe XCTest-suite voor de volledige app geclaimd.

Volledige macOS/iOS-builds en de nieuwe `DocumentBrandingTests`, bestaande migratietests en `NotuleSyncTests` moeten nog worden uitgevoerd. Controleer daarna de werkelijke Mac/iPhone/iPad-route, bestaande SwiftData-opslag en iCloud-synchronisatie tussen fysieke apparaten. Windows-native installatie, bestandsdialogen en WebView2-afdrukken zijn niet op een fysieke Windows-pc getest. Volledige VoiceOver- en Dynamic Type-acceptatie is evenmin uitgevoerd.

Er loopt apart werk aan mappen/notulen en PDF/print. Integratie vraagt aandacht voor `LocalTranscriptStore.swift`, de notuleviews en print-entitlements; die andere werkbomen zijn niet aangepast.

Een afzonderlijke tabelrij of lijstpunt moet binnen één A4-pagina passen. Bij een groter blok volgt een foutmelding; tekst wordt niet stil afgekapt. Word mag andere paginaovergangen hebben dan PDF/HTML, zoals ook in het goedgekeurde plan staat.

Publicatie en uitrol blijven een afzonderlijke stap.

## Opruiming

Alle builds, voorbeeldexports en screenshots staan op de externe SSD. De drie eigen localhost-testservers zijn gestopt. Elf tijdelijke npm-logs van uitsluitend deze werkboom zijn op de interne SSD verwijderd (45.056 gealloceerde bytes). De totale vrije interne ruimte veranderde tegelijk door andere sessies; dat is geen geïsoleerde nettometing. Vervangbare test-apps, modulecaches en mislukte tussentijdse uitvoer op de externe SSD zijn opgeruimd; het opruimrapport staat in `cleanup.json`. De definitieve exports blijven met SHA-256-manifest bewaard. Bestanden van andere sessies zijn blijven staan.
