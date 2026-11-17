# Huisstijlen — implementatie en verificatie, 17 november 2026

De functie en het kant-en-klare Yinga-importbestand zijn geïmplementeerd op `feat/document-huisstijlen-20261117` in `/Volumes/SSD/Projects/thoughtvault-huisstijlen`, vanaf `f9ff3e1e`. De volledige macOS- en iOS-testbuilds slagen. De fysieke Mac/iPhone-proef met CloudKit Production is in beide richtingen geslaagd. Er is vanuit deze werkboom niets gepubliceerd of naar een remote gepusht.

Gebruik [Yinga.tvhuisstijl](Yinga.tvhuisstijl), of **Yinga toevoegen** in de app. De [gebruiksinstructie](README.md) beschrijft importeren, standaard maken en toepassen.

## Wat is aangesloten

- Instellingen en huisstijlkeuze op Windows, macOS en iOS/iPadOS: beheer, live voorbeeld, standaard, dupliceren, import/export en versies.
- Optionele snapshots in SwiftData, Swift-/TypeScript-overdrachtsmodellen en de bestaande Apple-syncpayload. Oude notulen zonder snapshot houden hun weergave. Nieuwe notulen bewaren ook voor Standaard ThoughtVault een snapshot.
- Resultaat, archief en inhoudseditor. Alleen de inhoud is bewerkbaar; afbeeldingen en documentkader blijven in de huisstijl. Bibliotheekwijzigingen veranderen opgeslagen snapshots niet.
- Gedeelde HTML/CSS, lokaal gebundelde Word-export en A4-paginering. Apple-PDF legt afzonderlijke A4-pagina's vast; macOS drukt de PDF af en iOS deelt een echt PDF-bestand.
- Originele Yinga-assets, lokale Carlito/Caladea-fonts en ongewijzigde SIL OFL-licenties. De oorspronkelijke vier afbeeldingen zijn byte voor byte vergeleken; alle acht TTF-bestanden hebben `OS/2.fsType=0` voor embedding.
- Validatie vóór opslag, bestaande HTML-sanitatie, geen externe documentassets of scripts, binaire opslag via de bestaande Tauri-bestandsroute en de macOS-print-entitlement.

## Verholpen paginabeperkingen

De oorspronkelijke fout bij een actierij of lijstpunt groter dan A4 is gereproduceerd en verholpen in de gedeelde paginering. Lange tabelcellen en lijstpunten lopen door op vervolgpagina's, met behoud van rijke tekst, links, bijzondere tekens en lijstnummering. Tabelkoppen worden herhaald; UTF-16-surrogaatparen worden niet gesplitst. De fixtures controleren exact tekstbehoud per tabelkolom en doorlopende lijstnummering.

De fysieke weergavetest vond daarnaast tekstoverflow na CSS `zoom` op smalle schermen. De papierweergave gebruikt nu een visuele transformatie met passende kaderafmetingen, zonder de inhoud opnieuw te laten afbreken. Mobiele tekstinflatie is voor het papier op 100% gezet; appbediening en documentzoom staan daar los van. Ligaturen zijn voor de documenttekst uitgeschakeld omdat WebKit een combinatie in de PDF-tekstuitlezing als een ander teken doorgaf.

## Definitief bewijs

De eerste verificatieronde staat onder `/Volumes/SSD/Projects/task-evidence/thoughtvault-huisstijlen/`. Het definitieve vervolgbewijs staat onder `/Volumes/SSD/Projects/task-evidence/thoughtvault-huisstijlen-followup/`.

| Controle | Resultaat | Bewijs in vervolgmap |
|---|---|---|
| Volledige macOS-app en testbundel | `TEST BUILD SUCCEEDED` | `macos-final-build.log` |
| Volledige iOS-app en gerichte testbundel | `TEST BUILD SUCCEEDED` | `ios-export-build.log` |
| Apple-ondertekening | Geldige handtekeningen; bestaande iCloud-container, Production; macOS gesandboxed | `macos-signed-entitlements.plist`, `ios-signed-entitlements.plist` |
| Gerichte native tests op fysieke Mac | 23 behandeld: 22 geslaagd, 1 expliciete opt-in overgeslagen, nul fouten | `mac-final-tests.log`, `mac-final-tests.xcresult` |
| Dezelfde tests op fysieke Myphone 18 Pro | 23 behandeld: 22 geslaagd, dezelfde opt-in overgeslagen, nul fouten | `iphone-export-tests.log`, `iphone-export-tests.xcresult` |
| Werkelijke iCloud-rondreis | Mac upload → fysieke iPhone ontvangt/bewerkt → Mac verifieert retour en verwijdert tijdelijke zone; alle drie fasen geslaagd | `mac-tests.log`, `iphone-tests.log`, `mac-return.log`, bijbehorende xcresults |
| Windows TypeScript en productiefrontend | Geslaagd | `windows-build.log` |
| Windows-tests | 819 geslaagd, 2 bestaande skips | `windows-tests.log` |
| Gedeelde module | 7 geslaagd | `shared-tests.log` |
| Korte/lange notulen en grote blokken | 2/17/18/11 pagina's op Mac en iPhone; geen overflow, fonts en afbeeldingen geladen; Word-data geproduceerd | Native weergavetest in beide definitieve xcresults |
| Echte iPhone-PDF's | A4, paginatelling en uitleesbare titel gecontroleerd; voorblad en inhoud visueel bekeken | `iphone-pdfs/Yinga-*.pdf`, `iphone-cover.png`, `iphone-content.png` |
| Browserpaginering | Dezelfde vier fixtures; inhoud behouden, herhaalde koppen en juiste lijstnummers | `browser-pagination.log` |
| Smalle weergave en vergroten/verkleinen | 390 → 768 → 1440 → 390 px; 17 pagina's behouden, geen horizontale of verticale inhoudsoverflow | `browser-final-responsive.log`, `yinga-final-mobile.jpg` |
| Microsoft Word | Korte en lange export daadwerkelijk geopend en bewerkbaarheid getest in eerste ronde. Ook de grote actierij in Word geopend: 18 pagina's, inclusief lege slotalinea na de tabel; doorlopende tekst en emoji op pagina 17 bekeken | `word-check.txt`; eerste bewijsmap bevat eerdere Word-controle |

De native test gebruikt de echte productresources en exporter. Eerst wordt de weergave van 390 px tweemaal opgebouwd; vervolgens gebruikt de PDF-controle dezelfde A4-breedte als de productie-exporter. De vier PDF's worden als XCTest-attachments bewaard. De iOS-testconfiguratie selecteert de drie relevante testklassen omdat andere bestaande testbestanden macOS-specifiek zijn; de app zelf wordt volledig gebouwd.

De optionele iCloud-test is buiten de gewone suite expliciet uitgevoerd in fasen `mac-write`, `phone-edit` en `mac-verify`, met één unieke tijdelijke zone en uitsluitend synthetische inhoud. De snapshot, ingebedde afbeeldingen, payloadhash en teruggestuurde inhoud zijn gecontroleerd. De laatste fase heeft de testzone verwijderd. De gewone suite slaat deze externe proef zonder `TV_BRANDING_CLOUD_PHASE` en `TV_BRANDING_CLOUD_RUN` bewust over; dat is geen ontbrekende cloudcontrole.

De hersteltests gebruiken opzettelijk een beschadigde SQLite-fixture. De foutmeldingen daarover in de logs horen bij de geslaagde controle dat synchronisatie daarna blokkeert, niet bij de echte notulenopslag.

## Bestaande gegevens en grenzen

De iPhone-opslag is vooraf en na de eerste fysieke proef naar de externe SSD gekopieerd. Een vergelijking van de records bevestigt: alle 47 bestaande notulen ongewijzigd, geen verwijderingen en geen synthetische testnotulen in de echte store. Tijdens het wachten kwam één nieuwe notule bij, aangemaakt om 14:05 vóór de iPhone-tests van 14:14. Beide kopieën doorstaan SQLite `integrity_check`. Journalen, WAL en lokale historie veranderden mee; daarom is inhoud vergeleken en is geen verouderde backup teruggezet. Kopieën en bewijsmap zijn alleen toegankelijk voor de eigenaar. Zie `iphone-logical-record-comparison.json`.

Dit bewijst de fysieke CloudKit-assetoverdracht en de gedeelde syncpayload, plus de gerichte conflict-/offline-/migratielogica. Het is geen volledige handmatige achtergrond-/accountwisselacceptatie van `CKSyncEngine`. De native instellingen, bestands- en deelpanelen zijn niet op ieder fysiek platform handmatig doorgelopen. Volledige VoiceOver/Dynamic Type-acceptatie, een fysieke iPad en een fysieke Windows-installatie/WebView2-afdrukroute blijven buiten dit bewijs.

Op de iPhone staat na de proef een lokale ontwikkelbuild met Production CloudKit. De geïnstalleerde Mac-app is door deze taak niet vervangen. Andere werkbomen voor mappen, opnamefuncties en integratie zijn niet aangepast. Integratie vraagt nog aandacht voor gedeelde notuleviews en opslagcode.

## Publicatie en opruiming

Publicatie, merge en uitrol zijn niet vanuit deze werkboom uitgevoerd. Word mag andere paginaovergangen hebben dan PDF/HTML.

Alle builds, exports en screenshots staan op de externe SSD. Definitieve testapps, afhankelijkheden en xcresults blijven bewaard. De eigen testserver wordt gestopt en vervangbare caches en tijdelijke uitvoer worden opgeruimd; exacte aantallen en gealloceerde bytes staan in `cleanup.json` in de vervolgmap. Tijdelijke bestanden zonder bewezen eigenaarschap en werk van andere sessies blijven staan.
