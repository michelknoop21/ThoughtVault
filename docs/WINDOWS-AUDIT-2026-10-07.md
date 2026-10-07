# Windows functionele audit — 7 oktober 2026

## Installatie: ontbrekende Visual C++ runtime

- Getest: officiële ThoughtVault 1.0.260 x64 MSI in Windows 11 ARM64 onder Parallels (x64-emulatie).
- MSI-installatie eindigde met exitcode 0. Geïnstalleerd programma: `C:\Program Files\ThoughtVault\ThoughtVault.exe`.
- Eerste appstart blokkeert met Windows-systeemfout: `MSVCP140.dll was not found`.
- De installatie slaagde dus, maar de app is zonder deze dependency niet bruikbaar. Na runtime-installatie start de app succesvol; de onderstaande functies zijn vervolgens in de VM getest.

### Setupverbetering op verzoek van Michel

Controleer tijdens setup of een geschikte Microsoft Visual C++ x64 runtime aanwezig is. Bied alleen wanneer deze ontbreekt een optionele installatie van de officiële Microsoft Redistributable aan, met duidelijke uitleg dat ThoughtVault die nodig heeft om te starten. Een bestaande geschikte runtime niet opnieuw installeren. Wanneer de gebruiker installatie overslaat: toon de ontbrekende vereiste en een herstelroute, in plaats van een geslaagde, direct bruikbare installatie te suggereren.

- Officiële bron: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist/
- Vervolgcontrole: schone Windows-installatie zonder runtime, installatie met runtime aanwezig, weigeren/overslaan en succesvol starten na installatie.
- Nog niet geïmplementeerd; dit is een auditbevinding en setupvoorstel.
- Michel gaf toestemming om Microsofts licentievoorwaarden te accepteren en de runtime in deze test-VM te installeren voor het vervolg van de audit.
- Microsoft Visual C++ v14 Redistributable x64 14.51.36247 vervolgens geïnstalleerd; installer toont `Setup Successful`. ThoughtVault start daarna zonder inlogscherm. De VM-invoer vergde soms herhaalde clicks; oorzaak niet vastgesteld, daarom geen bewezen ThoughtVault-defect.

## Runtimecontroles

Testomgeving: Windows 11 ARM64, 4 cores, 8 GB RAM, x64-emulatie. MacBook-speakers tijdens de audit gemute. Alleen synthetische Nederlandse testspraak gebruikt. Vensters beoordeeld op circa 1200 × 800 en gemaximaliseerd in een 1920 × 1050 VM.

| Controle | Resultaat |
| --- | --- |
| Start na runtime-installatie | Geslaagd; geen login; vijf stappen onboarding |
| Whisper Small downloaden | Geslaagd; gereedmelding |
| Ontbrekende Ollama in onboarding | Duidelijke Nederlandse melding; overslaan werkt |
| WAV importeren en lokaal transcriberen | Geslaagd; 12,4 seconden mono 16 kHz testaudio |
| Notulen zonder Ollama | Mislukt zoals verwacht; transcript blijft beschikbaar |
| TXT-export geïmporteerd transcript | Geslaagd; Downloads/Transcriptie.txt gecontroleerd |
| Gecombineerde opname starten | Geslaagd; systeemtestspraak teruggevonden in transcript |
| Pauzeren en hervatten | Geslaagd; timer bleef op 00:26 staan tijdens pauze en liep na hervatten door |
| Stoppen en verwerken | Geslaagd tot transcript; notulengeneratie faalt zonder Ollama |
| Synthetische persoon toevoegen | Geslaagd; Audit Testpersoon verschijnt in lijst |
| App sluiten en opnieuw starten | Geslaagd zonder nieuwe onboarding/login; beide transcripts blijven in Notulen zichtbaar |

Small maakte herkenningsfouten (ThoughtVault → Dottfold, pilot → pallet). Dit is geen bewijs van perfecte transcriptiekwaliteit. Microfoon en systeemgeluid zijn niet afzonderlijk gevalideerd; de gecombineerde opname bevat aantoonbaar de afgespeelde synthetische spraak.

## Bevindingen op prioriteit

| Prioriteit | Bevinding / reproduceerbare waarneming | Gewenste verbetering |
| --- | --- | --- |
| Hoog | MSI geeft succes maar app start niet zonder MSVCP140.dll | Ontbrekende runtime detecteren en gerichte installatie aanbieden |
| Hoog | Nieuwe gecombineerde opname toont letterlijk `<b>…</b>` in het transcript | Eén veilige tekstnormalisatie voor transcriptweergave en export; geen ongefilterde HTML injecteren |
| Middel | Opnameduur in detail: `1m 17.044177875000003s` | Duur consequent als minuten en gehele seconden formatteren |
| Middel | Verwerking zonder Ollama toont `error sending request for url (http://localhost:11434/v1/chat/completions)` | Nederlandse fout met oorzaak en herstelactie; behouden transcript expliciet tonen |
| Middel | Officiële Windows 1.0.260 bevat nog het door Michel afgekeurde boom/diamant-logo in onboarding, sidebar, titel en appicoon | Goedgekeurde kluisvariant consistent in alle release-assets gebruiken |
| Middel | Bronkeuze popup toont witte/lege tweede rij in donkere UI | Native select en opties op Windows/WebView2 op contrast en schildering controleren |
| Middel | Normaal venster: onderzijde lange model-onboarding/actie wordt door footer aan het zicht onttrokken tot scrollen | Scrollgebied en footer/actiepositie op kleine vensterhoogte corrigeren |
| Middel | Home na herstart op 1200 × 800: nieuwe-opnamekaart en rechterkaart lopen tegen/voorbij rechterrand; rechterkolom deels afgesneden | Grid en minimale kaartbreedtes op normale vensterbreedte corrigeren |
| Middel | Zwevende opnamebalk overlapt tekst onder snelle acties in rechterkolom | Balk ruimte geven of buiten de inhoud plaatsen |
| Middel | Instellingen vrijwel schermbreed; mensen/profielen/taken smal gecentreerd; headers en inhoud beginnen op verschillende assen | Gedeelde inhoudsbreedte en uitlijning voor verwante schermen |
| Middel | Transcript lange regels over bijna volledige breedte, kleine tekst en kleine toolbar-acties | Leesbreedte begrenzen; tekst en klikvlakken verbeteren |
| Laag | Obsidian-instellingen tonen Developed by yinga zowel in paginainhoud als shellfooter | Eén gedeelde merkfooter |
| Laag | Profielen combineren emoji-iconen met lijniconen; dubbele Nieuw profiel-acties | Iconen en actiehiërarchie consistent maken |
| Laag | Taken tonen interne naam `import_Nyjb9y.wav`; recente items heten beide Transcriptie | Oorspronkelijke bestandsnaam of onderscheidende titel behouden |
| Laag | Mislukte taakbanners verdwijnen na appherstart terwijl behouden transcripts terugkomen | Herstelstatus van mislukte verwerking zichtbaar houden; persistentie van taakstatus verder onderzoeken |
| Laag | Niveau-indicator toont volle witte balk bij stilte/pauze | Lege track visueel onderscheiden van actief niveau |

Niet alle punten zijn regressies: audit van de gedownloade release, zonder historische attributie. Geen designregels onderdrukt. Geen applicatiecode gewijzigd.

## Grenzen van deze audit

Lokale Ollama en Obsidian-server ontbreken in de test-VM. Ollama Cloud is inmiddels ingesteld en de appverbindingstest slaagt. Inhoud en export van de nieuw gegenereerde notule, gekoppelde vault-export, agenda-integratie, andere cloudproviders, langdurige opname en fysieke Windows x64-hardware zijn niet volledig bewezen. Geen privégegevens naar een cloudprovider verstuurd. Testartefacten blijven lokaal beschikbaar. Deze notities zijn bevindingen en verbeterpunten, geen claim dat ze al zijn opgelost.

## Vervolg: Ollama Cloud en MCP

- Door Michel aangeleverde testsleutel rechtstreeks tegen Ollama Cloud getest, zonder sleutel in dit rapport op te nemen: `/v1/models` HTTP 200; `/v1/chat/completions` met `gpt-oss:20b`, synthetische verbindingstest, HTTP 200 en antwoord `OK`.
- Michel heeft opslag in Windows-systeemkeyring en selectie van Ollama Cloud voor de audit toegestaan. Uitgevoerd: provider Ollama Cloud, model `gpt-oss:20b`, gemaskeerde sleutel opgeslagen; app meldt `Sleutel opgeslagen in de systeemkeyring.` en na controleren `Notulemodel klaar voor gebruik.`
- Synthetische WAV opnieuw geïmporteerd. Verwerking eindigde en een nieuw recent item `Verslag van de function…` verscheen. Dit ondersteunt aanmaak van AI-notulen; inhoud, opmaak en export zijn nog niet gecontroleerd doordat de Windows-guest niet meer op onze clicks/toetsen/scroll reageert. Ontgrendelen Mac, vernieuwen bedieningssessie en vensterzoom herstelden dit niet. Parallels-menubediening werkt wel. Oorzaak onbekend, geen bewezen ThoughtVault-defect. Gebruiker gevraagd het recente item handmatig te openen.
- ThoughtVault MCP live getest zonder credentials: POST `/tstudio/api/mcp` (initialize) HTTP 502; `/tstudio/api/.well-known/oauth-protected-resource`, `/tstudio/api/.well-known/oauth-authorization-server` en `/tstudio/api/health` eveneens HTTP 502. Root metadata hoort bij een andere n8n-MCP-interface en mag niet met ThoughtVault verward worden.
- Hercontrole circa 21:20 CEST: `/health` en MCP initialize blijven HTTP 502. Koppelknop in de Windows-app nog niet bediend; geen nieuwe MCP-toegang verleend.
- Daardoor geen geslaagde MCP-authenticatie of tooluitvoering bewezen. Ollama-sleutel is voor Ollama Cloud, niet voor ThoughtVault-MCP; niet naar de MCP-server verstuurd.

### MCP-mogelijkheden volgens broncode, nog niet live bewezen

| Recht | Tools / mogelijkheden |
| --- | --- |
| read | Apparaten en bereikbaarheid; opnamestatus/taken; transcripts zoeken en inhoud ophalen; profielen en prompts lezen; export HTML, Markdown, TXT en PDF |
| write | Notulen bij bestaand transcript opslaan; titel/tags wijzigen; profiel/prompts/sjabloon opslaan; appschermen openen |
| record | Opname starten met profiel en bron, pauzeren, hervatten, stoppen en bestaande verwerking starten |

Server bevat 15 tools: `list_devices`, `get_app_state`, `list_transcripts`, `get_transcript`, `save_minutes`, `update_transcript`, `list_profiles`, `get_profile`, `save_profile`, `open_view`, `start_recording`, `pause_recording`, `resume_recording`, `stop_recording`, `export_minutes`.

App moet gekoppeld en geopend zijn; rechten zijn afzonderlijk. Schrijven gebruikt revisies om verouderde wijzigingen af te wijzen. Ingebouwde profielen worden bij aanpassen naar een eigen profiel gekopieerd. PDF-downloads verlopen na vijf minuten. Geen tools gevonden voor algemene bestands-/shelltoegang, verwijdering, personenbeheer of wijzigen van AI-credentials. Dit beschrijft de huidige onderzochte broncode, geen garantie dat productie dezelfde versie draait.
