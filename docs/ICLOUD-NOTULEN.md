# Notulen synchroniseren met iCloud

## Gebruik

Op de Mac: **Instellingen → Algemeen → iCloud**. Op iPhone: **Instellingen → Integraties → iCloud**.
Zet **Synchroniseer notulen via iCloud** op beide apparaten aan en gebruik hetzelfde Apple-account.
De functie staat standaard uit. Bij inschakelen worden ook de bestaande lokale notulen meegenomen.

Notulen, transcripties, titels, tags en bijbehorende notulegegevens worden via de private CloudKit-database
uitgewisseld. Opnamen en lokale audiopaden blijven op hun oorspronkelijke apparaat. De mensenlijst en
opnameprofielen worden niet door deze functie gesynchroniseerd; namen van gebruikte profielen en
vastgelegde deelnemers staan wel in de notule.

Bewerken en verwijderen werkt door op andere aangesloten apparaten. Offline werken blijft mogelijk;
wijzigingen worden later verstuurd. **Synchroniseer nu** vraagt direct een poging aan. iCloud bepaalt
wanneer achtergrondsynchronisatie mogelijk is. Uitschakelen verwijdert geen lokale of cloudgegevens.

Bij gelijktijdig bewerken blijft de serverversie onder de oorspronkelijke notule staan en wordt de
lokale versie als aparte notule met **(bewerkingsconflict)** in de titel bewaard. Ook een wijziging die
samenvalt met verwijderen blijft als conflictkopie beschikbaar. Een herhaald ontvangen conflict
overschrijft geen eerder bewerkte kopie.

## Implementatie en bescherming van bestaande gegevens

De bestaande `Local.store` blijft expliciet lokaal (`cloudKitDatabase: .none`); het SwiftData-model
wordt niet geconverteerd. `NotuleSyncService` gebruikt `CKSyncEngine` en een afzonderlijk, atomair
opgeslagen synchronisatiejournaal in `Application Support/ThoughtVault/iCloud/sync-state.json`.
Het journaal bevat accountbinding, hashes, CloudKit-systeemvelden en de enginecursor. Het bevat geen
notuletekst. Tijdelijke uploadbestanden bevatten uitsluitend de overdraagbare inhoud en worden na de
verzendronde verwijderd. Lange transcripties gebruiken een asset; de huidige grens is 64 MiB per notule.

Alle transcriptmutaties lopen door `LocalTranscriptStore`; na een geslaagde lokale save wordt de
wachtrij bijgewerkt. Bij herstart vergelijkt de synchronisatie de lokale inhoud met het journaal,
zodat ook wijzigingen tussen lokale save en journaalsave worden gevonden. Ophalen moet slagen;
een databasefout wordt nooit vertaald naar een lege verzameling/verwijdering van alle cloudnotulen.

Bij onleesbaar journaal stopt synchronisatie. Bij herstel naar een nieuwe lokale database wordt
`localStoreRecoveryRequiresReview` gezet; synchronisatie mag pas na gecontroleerd gegevensherstel
worden hervat. Een externe verwijdering van de CloudKit-zone zet een blijvende blokkade in het
journaal. De app maakt die zone dan niet stilzwijgend opnieuw aan. Een ander Apple-account krijgt
geen gegevens van het oorspronkelijk gekoppelde account.

## Apple-configuratie vóór gebruik en distributie

Beide app-targets/distributies gebruiken `iCloud.com.buildmind.ThoughtVault`, private database,
zone `Notulen`, recordtype `Notule`. Zet voor de bestaande app-ID CloudKit en pushmeldingen aan;
koppel dezelfde container aan de macOS- en iOS-provisioningprofielen. De broncode-entitlements
bevatten de container, CloudKit-service en pushomgeving. iOS heeft `remote-notification` als
achtergrondmodus. Debug gebruikt Development, Release Production.

Het recordtype heeft drie appvelden: `content` (Asset), `contentHash` (String) en `schemaVersion`
(Int64, momenteel 1). Er zijn geen appqueries of extra query-indexen: de engine volgt zonewijzigingen.
Laat een ontwikkelbuild de ontwikkelschema's aanmaken met synthetische testnotulen. Publiceer dit
schema in CloudKit Console naar Production voordat een distributiebuild beschikbaar wordt gesteld.
Dit is een afzonderlijke releasevoorwaarde; compileren bewijst niet dat provisioning of het
productieschema actief is.

## Acceptatie op twee apparaten

1. Gebruik dezelfde iCloud-account op een Mac en iPhone en een ondertekende ontwikkelbuild.
2. Start met uitgeschakelde synchronisatie: bestaande notulen en audio moeten beschikbaar blijven.
3. Schakel op beide apparaten in. Controleer bestaande en nieuwe notulen, transcriptie, titel en tags
   in beide richtingen. Controleer dat audio uitsluitend op het oorspronkelijke apparaat beschikbaar is.
4. Bewerk offline, herstart de app en herstel de verbinding. Controleer de wachtrij en resultaat.
5. Bewerk dezelfde notule offline op beide apparaten, en herhaal met wijzigen tegenover verwijderen.
   Beide tekstversies moeten behouden zijn; bewerk de conflictkopie en controleer herhaalde import.
6. Verwijder een gesynchroniseerde testnotule en controleer beide apparaten na herstart.
7. Log uit/in; wissel naar een ander testaccount. Geen notulen mogen in het andere account verschijnen.
8. Test ontbrekende iCloud-login, volle opslag en netwerkverlies. De lokale notulen blijven bruikbaar.
9. Test met een lange synthetische transcriptie (> 1 MiB) en herstart tijdens verzenden/ontvangen.
10. Herhaal met Production via TestFlight na schema-publicatie. Een simulator- of unittest vervangt
    deze acceptatie niet.

## Gecontroleerde Apple-configuratie (16 november 2026)

De container is geregistreerd en gekoppeld aan app-ID `com.buildmind.ThoughtVault` in team
`XL9KN38ATX`. Push Notifications en iCloud met CloudKit zijn actief. Vier vernieuwde profielen
zijn via de bestaande App Store Connect API-sleutel aangemaakt en op hun ondertekende
entitlements gecontroleerd: ontwikkeling en App Store voor macOS en iOS.

De profielnamen volgen `ThoughtVault iCloud <TYPE> 20261116`, met als type
`MAC_APP_DEVELOPMENT`, `IOS_APP_DEVELOPMENT`, `MAC_APP_STORE` of `IOS_APP_STORE`.
De bestaande certificaten zijn hergebruikt. De standaard automatische profielkeuze van Xcode
selecteerde lokaal nog de oude profielen zonder cloudrechten; gebruik voor de controle expliciet
het nieuwe profiel op het app-target. Geef dit niet als globale profieloverride aan alle targets:
het testbundle heeft een eigen identifier en krijgt geen app-profiel.

Bewijs en de lokale targetgebonden configuratie staan op de externe ontwikkelschijf onder
`task-evidence/thoughtvault-icloud-notulen/`: `profiles/verified.json`,
`cloud-signing.xcconfig`, `cloud-mac-manual.log` en `mac-signed-entitlements.json`.
Deze lokale paden of profielnamen zijn geen vereiste voor gebruikers van de app. Bij volgende
buildmachines moet een geldig profiel met dezelfde container en de gewenste omgeving worden
geïnstalleerd of vernieuwd.
