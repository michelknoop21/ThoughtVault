# Centrale Windows-appscenario's

Dit zijn de bestaande beproefde SSH/UI Automation-scenario's, nu in Git.
Materialiseer de expliciete kandidaatversie, de **geïnstalleerde MSI-payload-EXEhash**
en de gekozen LLM in een nieuwe bestandkopie. Imports vereisen daarnaast één
fixturepad en SHA256; gebruik dezelfde importproef voor elk van de zeven formaten.
Registreer pas daarna de kopie met de exacte script-SHA via acceptance-register.
Onvervangen metadata stopt vóór appstart; wijzig geen bestaande registraties.

De scripts bewijzen vooralsnog opname/import en verwerking, geen export,
bewerken/heropenen, lange vergadering of fysieke microfoon. Die assertions volgen
in taak 3/5. Originele gegevens worden vergeleken; gewijzigde modelinstellingen
worden hersteld. Herstel krijgt eigen rapportvelden en overschrijft de oorzaak
van een eerdere verwerkingsfout niet. Er wordt geen ontbrekend model gedownload.

UI-helpers blijven bewust zelfstandig: de bestaande centrale registratie pinnt
en kopieert één script. Geen losse, veranderlijke module buiten die hash laden.
