# Mappen en automatisch labelen

Implementatie van het goedgekeurde plan, vanaf geïntegreerde `main` f9ff3e1e (1.0.329), in `feat/mappen-auto-labels-20261117`.

## Gedrag

- In Notulen: Alle notulen, Zonder map, gewone mappen en slimme mappen. Aanmaken, wijzigen en verwijderen; verwijderen laat notulen intact. Eén mapniveau.
- Verplaatsen via de notulecontextactie op Apple, via selectie op alle platformen en via slepen op desktop. Bulkverplaatsen is één lokale opslagtransactie.
- Slimme mappen matchen minstens één gekoppeld label. Gewone maptoewijzing en slimme matches zijn onafhankelijk.
- Labels beheren hergebruikt bestaande labels. Per label: omschrijving en Automatisch toekennen. Nieuwe labels kunnen ook vooraf worden aangemaakt.
- Nieuwe goedgekeurde notulen worden na succesvolle opslag geclassificeerd met de ingestelde provider. Gewone tekstbewerkingen starten geen nieuwe classificatie.
- Bestaande notulen: selectie, aantal en bevestiging vóór verwerking. Voortgang, annuleren en opnieuw proberen bij fouten. Annuleren stopt vervolgwerk en negeert de lopende respons; de provider kan de lopende aanvraag nog afmaken.
- Handmatige labels blijven behouden. Een verwijderd automatisch label blijft onderdrukt; opnieuw handmatig toevoegen heft de onderdrukking op en maakt het label handmatig.
- Verplaatsingen wijzigen geen audio- of exportpad en roepen Obsidian niet aan.

## Opslag en synchronisatie

Apple voegt uitsluitend optionele velden toe aan `TranscriptRecord`: `organizationJSON` en een lokale foutmelding voor classificatie. De bestaande tags blijven strings. De aparte catalogus `ThoughtVault/library.json` bevat stabiele IDs, labelomschrijvingen, mappen, slimme definities en verwijdermarkeringen; hij wordt atomair opgeslagen. Historische labelnamen krijgen op Apple deterministische IDs, zodat twee apparaten dezelfde bestaande labels herkennen.

De bestaande optionele CloudKit-sync transporteert notulemetadata en een apart catalogusdocument, inclusief lege mappen. Catalogusconflicten worden per ID samengevoegd op wijzigingstijd met een stabiele tie-break; verwijdermarkeringen voorkomen herstel door een oudere catalogus. Notuleconflicten behouden de bestaande conflict-kopie. Een oud notulebericht zonder `organizationJSON` behoudt de bestaande map- en herkomstmetadata; een expliciete lege organisatie verwijdert de toewijzing.

**Compatibiliteit vóór uitrol:** gewone notuleberichten houden schemaVersion 1; het catalogusdocument gebruikt schemaVersion 2 in hetzelfde CloudKit-recordtype en dezelfde bestaande velden. Oudere apps stoppen veilig op dat nieuwe document. Werk daarom alle synchroniserende Apple-apps bij voordat mappen worden gebruikt. Er is geen CloudKit-productieschema of gebruikersaccount gewijzigd.

Windows bewaart de catalogus in hetzelfde Tauri-storebestand als de notulen. Wijzigingen publiceren pas na een geslaagde save. Bij een mislukte save wordt ook de tijdelijke storecache teruggezet, zodat een latere save de mislukte wijziging niet alsnog meeneemt. Geen nieuwe synchronisatie tussen Windows en Apple.

## Bewijs en resterende controle

Bewijsmap: `/Volumes/SSD/Projects/task-evidence/thoughtvault-mappen-20261117/`.

- Windows: 35 gerichte tests geslaagd (11 bestanden), TypeScript zonder fouten, Vite-productiebuild geslaagd. Bestaande chunkgroottewaarschuwing blijft.
- Browser, echte React-schermen met bestaande lokale Tauri-fixture: map maken, twee notulen verplaatsen, hernoemen, slimme map met twee treffers, verwijderen met zes behouden notulen. Consolefouten: `[]`.
- Browser: labelomschrijving en automatische instelling opslaan, bulkbevestiging met aantal, annuleren vóór providerverwerking. Bij 800 px geen horizontale overflow; nieuwe navigatieknoppen hebben toegankelijke namen. Geen live cloud-AI-aanvragen gedaan.
- Eerste macOS-build: `BUILD SUCCEEDED`. Dit was vóór de laatste kleine aanvullingen en extra tests; het is geen bewijs voor de uiteindelijke diff.
- Laatste Swift-bronnen en tests: parsercontrole geslaagd. Nieuwe XCTest-cases dekken echte migratie vanaf het vorige model, herstart, read-only opslagfout, bulkverplaatsen, mapverwijdering, slimme matches, handmatige onderdrukking, providerfout/retry, annuleren, catalogusconflicten en oude syncberichten.
- Uiteindelijke Apple-tests en iOS-simulatorbuild staan in de gedeelde buildwachtrij. Een andere sessie voert een exclusieve twee uur durende fysieke audioproef uit (`exclusive-task`). Die is niet onderbroken. Onze testprojectkopie heeft een aparte app-ID `com.buildmind.ThoughtVault.LibraryTests` en gebruikt een eigen DerivedData-map.
- Nog niet bewezen: uitvoering van de nieuwe XCTest-cases, uiteindelijke iOS-build, native macOS/iOS-interactie/VoiceOver, Windows MSI op een fysiek apparaat en echte iCloud-overdracht tussen apparaten. Geen merge, push, release of installatie uitgevoerd.

De browser leverde DOM-/interactiebewijs, maar zijn gerapporteerde tijdelijke screenshotpad was niet vanaf de shell bereikbaar; screenshots zijn daarom niet als visueel bewijs opgevoerd.

## Lokale opslag

Builds, packagecheckouts, Windows-output en testbewijs staan op de externe SSD. De standaard Xcode DerivedData-map verwijst eveneens naar de externe SSD. De tijdelijke projectkopie in `.task-tmp/ThoughtVault.xcodeproj` blijft nodig zolang de ingeplande verificaties lopen. Geen bestanden van andere sessies opgeruimd; geen gebruikersnotulen aangeraakt.

Opruimcontrole: geen vervangbare taakbestanden gevonden in de gecontroleerde interne build-/tijdelijke paden; op de interne SSD is 0 bytes verwijderd. De tijdelijke projectkopie en externe buildcache blijven bewaard voor de ingeplande Apple-controles. Controleer na die tests nog de tijdelijke data van de aparte testapp.
