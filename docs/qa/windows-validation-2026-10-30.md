# Windows 1.0.296: begrensde inhoudscontrole en conceptbehoud

De kandidaat voegt geen ASR-fix of nieuw model toe. De bedragfix behoudt punten
tussen cijfers. De bestaande concept-/correctiepasses blijven; daarna volgt
maximaal één vaste inhoudsaudit bij dezelfde ingestelde provider/model.
Geen automatische herkansing op een gunstig antwoord.

De audit ontvangt de volledige gecorrigeerde originele transcriptie (geen verkorte
samenvatting), afzonderlijke gebruikersnotities en de definitief nabewerkte
notuletekst. Bron- en notule-eenheden krijgen door de app IDs. JSON moet ieder ID
precies eenmaal afdekken, bekende verwijzingen en wederzijdse onderbouwing bevatten;
onzekerheid, ontbrekende/tegenstrijdige/ongefundeerde inhoud of een onvolledig,
ongeldig of afgebroken antwoord blokkeren voltooiing. Expliciete bronbeperkingen
mogen niet als niet-feitelijk worden genegeerd. Correcte parafrases mogen met
volledig auditbewijs door; alleen letterlijk kopiëren is niet verplicht.
Alleen exact gelijke volledige tekst kan zonder modelaudit door.

Grenzen: 64.000 tekens bron+notities+notule, maximaal 400 totale eenheden;
boven die grens beoordeling vereist, nooit stil afkappen. Automatische controle
ondersteunt eenvoudige semantische HTML zonder CSS, classes, verborgen inhoud
of mediacontent. Andere opmaak wordt voor beoordeling bewaard. Dit is een
expliciete ondersteunde grens, geen bewijs dat een dergelijk document inhoudelijk
fout is. Complexe templates kunnen hierdoor menselijke beoordeling vereisen.

Bewijsverwijzingen bewijzen structurele dekking, geen semantische waarheid.
Dezelfde modelinstantie kan gecorreleerde beoordelingsfouten maken, waaronder
onjuiste classificatie als niet-feitelijk. Geen algemene semantische zekerheid
of correctheid tegenover oorspronkelijke audio geclaimd. Echte vaste positieve/
negatieve runtimeproeven op de kandidaat blijven verplicht; mocktests zijn geen
modelkwaliteitstest. Beschadigde ASR en ontbrekend luisterbewijs blijven apart.

Bij falende controle wordt NotuleReviewError met het concept afgehandeld in
zowel de opnameketen als regeneratie. Het concept en de reden staan apart in
optionele velden van de bestaande lokale recordstore. Vorige notulen/transcript
blijven behouden; taak is failed en er is geen succesprogress of Obsidian-autoexport.
Mislukte conceptopslag wordt eerlijk gemeld. De detailpagina toont een apart,
veilig gerenderd concept ter beoordeling; gewone notule-export gebruikt dit niet.
Een nieuwe geslaagde vervanging wist oude concept-/reviewvelden.

Verificatie vóór Windowsbouw: 206 frontendtests groen, tsc --noEmit en frontendbuild
groen. Contracttests zijn behouden, aangevuld met andere namen, meerdere acties,
voorwaarden/negaties, correcte parafrases voor alle vier providerroutes, echt
JSON-negatief bewijs, protocolfouten, verborgen inhoud en opslagfouten.
De oorspronkelijke contractmocks die HTML als auditantwoord geven testen nu
veilige afwijzing van ongeldig bewijs, niet zelfstandige semantische detectie.
Onafhankelijke read-only review leidde tot aparte rode regressies voor lege,
volledig niet-feitelijke en verborgen-inhoudsrapporten. De bevindingen zijn
verholpen, inclusief ARIA-veilige conceptweergave. Native/build/runtimebewijs
wordt afzonderlijk geregistreerd; geen vrijgave-GO uit deze bronchecks afleiden.
