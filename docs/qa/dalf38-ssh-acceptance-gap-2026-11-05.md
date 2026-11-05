# Dalf38: ontbrekende acties voor uitvoering uitsluitend via SSH

Gebruikerskeuze: alle verdere bediening via de bestaande centrale SSH-beheerlaag;
geen computeruse/Royal TSX als uitvoerroute. Geen nieuwe SSH-server, beheeraccount
of projectgebonden beheerlaag.

## Bewezen huidige grens

- SSH developer en LocalService-builds werken. Native 1.0.299 is gebouwd in job
  18916d4c4d5b4251bfeb9a9f7f8074ee, broncommit
  870c3f93f75620f4a932f6cacf595f7ce2850aea, exit 0.
- 173 frontendinputs zijn hashgelijk aan de 209-PASS-baseline van job
  2c17e207d4784332860a2c58362efd40; frontend herbouwd, tests niet herhaald.
- De ongebruikte credential-printer is uit de bron verwijderd. De nieuwe WiX-
  definitie bevat hem niet, ondanks zijn aanwezigheid in de oude bouwcache.
  Dit is nog geen gecontroleerde uiteindelijke MSI-payload.
- WiX ICE faalt onder zowel LocalService als SSH developer met LGHT0217:
  Windows Installer Service could not be accessed. Onder de bestaande interactieve
  michel-sessie slaagde dezelfde validatie voor de afgewezen kandidaten 297/298.
  De achterliggende Windows-autorisatieoorzaak is niet definitief vastgesteld.
- Developer kan Task Scheduler niet via CIM benaderen: Access denied.
  Get-Service vindt msiserver binnen deze beperkte tokencontext niet; daaruit
  volgt niet dat de service op de machine ontbreekt.
- De bestaande vaste gui-probe rapporteert alleen sessie-identiteit; hij is
  nadrukkelijk geen uitvoerroute voor scripts, installaties of app-tests.
- Geen kandidaat geïnstalleerd. Versie 1.0.295 is nog aanwezig. Verse back-up van
  628 appdatabestanden is hash-/tijdstempelgelijk gecontroleerd op Dalf38.
  Werkelijke installatie, rollback, herstel en opname-/inhoudsacceptatie zijn open.

## Benodigde aanvulling in de bestaande centrale laag

De beheerder moet een expliciete, gecontroleerde route aanbieden voor:

1. MSI-validatie met de aanwezige WiX/Windows Installer-tools, zonder de
   vereiste ICE-controle te laten vervallen.
2. Installatie/rollback van één expliciet geautoriseerd pakket, met versie,
   SHA-256 en updaterhandtekening vastgelegd; gesloten app, geverifieerde verse
   back-up en controle op gegevensbehoud vóór de eerste start.
3. Acceptatietests in de bestaande interactieve gebruikerssessie: app starten,
   opnemen, pauze/hervatten, bron afspelen, verwerken/exporteren, procesboom en
   fouten verzamelen. Echte microfoonkwaliteit blijft afhankelijk van een
   aanwezige microfoon en herkenbare testspraak.

Deze acties moeten via dezelfde dalf.ps1-interface te starten/volgen zijn, met
jobs, logs en artifacts. Geen extra SSH-ingang of persoonlijke credentialkopieën.
De huidige gui-probe niet ombouwen tot een door developer schrijfbare willekeurige
uitvoerbrug naar michel of administrator. Een eventueel taak-/rechtenontwerp moet
vooraf worden beoordeeld; installatie-/taakdefinitie-/ACL-wijzigingen vereisen
volgens de centrale handleiding een concrete lokale beheerderstoestemming.

Dit document is een begrensde overdracht van de ontbrekende mogelijkheden,
geen geïmplementeerde of goedgekeurde centrale uitbreiding. Er zijn geen centrale
beheercode, taakdefinities, Windows Installer-rechten of SSH-instellingen gewijzigd.
