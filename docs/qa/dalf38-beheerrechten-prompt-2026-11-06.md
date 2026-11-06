# Prompt voor de lokale beheeragent op Dalf38

Werk lokaal op Dalf38 als beheerder. Ik machtig de agent op mijn MacBook om via de bestaande SSH-verbinding zelfstandig beheer uit te voeren voor al mijn huidige en toekomstige projecten, inclusief bouwen, testen, installeren, upgraden, back-uppen en gecontroleerd herstellen. Ik wil hiervoor niet per opdracht of build handmatig hashes goedkeuren of PowerShell-opdrachten overnemen.

Behoud de bestaande verbinding: 192.168.3.104, poort 2222, gebruiker developer, uitsluitend LAN/bestaande VPN. Gebruik de reeds geautoriseerde publieke sleutel van de MacBook. Maak geen nieuwe SSH-server, poort, account of projectgebonden beheerlaag en kopieer geen private sleutels.

Lees eerst C:/ProgramData/Dalf38/management/README.md en docs/msi.md. De centrale beheerinterface is dalf.ps1; het projectregister staat op C:/Dalf38/registry/projects.json. De automatische MSI-snapshotroute is al geactiveerd met centrale commit a442929837bbd7acf5f59fd921d13bd608d37115. Behoud die implementatie.

Regel de ontbrekende technische toegang binnen deze bestaande laag:

1. Maak noodzakelijk verhoogd beheer vanaf de bestaande SSH-identiteit uitvoerbaar zonder terugkerende lokale goedkeuring. Geef developer daarvoor zo nodig lokale beheerdersrechten en behoud een werkende public-keylogin, inclusief de juiste Windows authorized_keys-locatie en ACL's. Laat UAC, firewall en authenticatie ingeschakeld.
2. Maak via dezelfde centrale CLI de installatie en rollback van een expliciet gekozen, op hash en bestaande updaterhandtekening gecontroleerd pakket mogelijk. Controleer eerst dat de app gesloten is en maak een verse geverifieerde back-up van de werkelijke gebruikersstores. Toon iedere fout en herstelstap in jobs/logs.
3. Bied een centrale uitvoerroute voor geregistreerde acceptatiescenario's in de bestaande niet-verhoogde, interactieve sessie van Michel. Hiermee moet de Mac-agent apps kunnen starten, via Windows-automatisering bedienen en opname/import/verwerking/export testen. Gebruik één projectoverstijgende route, geen scripts of SSH-toegang per ontwikkelomgeving. Laat credentials in de bestaande gebruikerscontext.
4. Laat opdrachten doorlopen na verbreken van SSH en geef status, exitcodes, logs en artifacts terug. Controleer werkelijk dat de SSH-beheeractie verhoogde rechten heeft en de app-test in Michels interactieve sessie draait; alleen een account aan een groep toevoegen is onvoldoende bewijs.

Bouw de kleinste werkende uitbreiding met bestaande Windows/PowerShell-middelen. Installeer geen extra toolchains of diensten en zet geen beveiliging uit. Maak vóór configuratiewijzigingen een herstelbare kopie. Voer geen gelijktijdige ThoughtVault-installatie of app-tests uit: die worden door de Mac-agent gecoördineerd. Publiceer niets.

Lever werkende SSH-commando's voor beheer, installatie/rollback en interactieve acceptatie, met bewijs van de juiste identiteit/rechten/sessie en een herstelprocedure. Benoem exact wanneer een ingelogde of ontgrendelde sessie nodig is en welke fysieke microfoonproef nog menselijke testspraak vereist. Claim geen opnameacceptatie op basis van een sessieprobe.


## Klaargezette padcorrectie

De minimale padcorrectie staat al op Dalf38 in
`C:/Dalf38/incoming/dalf38-msi-short-path-75e2feb` (commit
`75e2feba5e54108bfa4ebbd8ef911c3e22de7e70`). Beide MSI-testsuites zijn daar
onder developer geslaagd. Het archief ernaast heeft SHA256
`9d43cfb8255eec516ff9a412702f353abf43caca007ebaf72c0aff5faebe2d6d`.
Controleer vóór activering de actuele geïnstalleerde commit en eventuele wijzigingen.
Werk via de bestaande `Update-Dalf38.ps1` bij, met de bestaande MSI-workerlock
vastgehouden en zonder actieve verpakkingstaak. Herhaal de eenmalige
`Setup-MsiAutomation.ps1` niet: die verwacht de oude basiscommit.
Laat de oorspronkelijke gevalideerde/ondertekende MSI 1.0.300 ongewijzigd;
de Mac-agent start na activering een nieuwe automatische verpakkingsproef.
