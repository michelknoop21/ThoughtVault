# Claude en ChatGPT koppelen

MCP is optioneel. Zonder koppeling blijft ThoughtVault lokaal werken. De app moet geopend blijven om opdrachten te ontvangen. Er is geen lokale luisterpoort en geen automatische synchronisatie van de transcriptbibliotheek.

## Server activeren

De backendwijzigingen staan in `/Volumes/SSD/Projects/transcript-studio-backend`. Ze zijn nog niet gepubliceerd op de externe server.

1. Installeer de bijgewerkte backendrequirements in de container. De SDK gebruikt `mcp==1.26.0`, `sse-starlette==2.1.3` en `uvicorn==0.31.1`; FastAPI en Starlette behouden hun bestaande versies.
2. Zet `MCP_ENABLED=1`. Standaard is de koppeling uitgeschakeld.
3. Gebruik bestaande Redis voor toegang en apparaatmetadata. Opdrachten, antwoorden en PDF's gebruiken `MCP_TRANSIENT_REDIS_URL`, of dezelfde Redis als die variabele ontbreekt. **De payload-Redis moet `save ""` en `appendonly no` hebben.** De backend controleert beide instellingen bij opstarten en weigert MCP te starten bij schijfpersistentie of een niet uitvoerbare controle. Verander hiervoor niet de persistentie van andere bestaande wachtrijen; wijs zo nodig een afzonderlijke, niet persistente Redis toe.
4. Publiceer de HTTP-routes met het bestaande `/tstudio/`-pad. De bestaande Nginx-route alleen is onvoldoende voor discovery buiten dat pad. Voeg de volgende twee routes toe aan dezelfde HTTPS-vhost:

```nginx
location = /.well-known/oauth-authorization-server/tstudio/api {
    proxy_pass http://127.0.0.1:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
}
location = /.well-known/oauth-protected-resource/tstudio/api/mcp {
    proxy_pass http://127.0.0.1:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
}
```

Behoud voor `/tstudio/api/mcp` en de apparaat-longpoll de autorisatieheader en een proxytimeout van minimaal 60 seconden. Zet responsebuffering voor MCP uit. De container publiceert volgens de bestaande compose-configuratie poort 5000. Controleer de werkelijk gebruikte upstream bij uitrollen. Dit document verandert de Nginx-configuratie niet.

Het endpoint is `https://n8n.prezent.nl/tstudio/api/mcp`. De OAuth-issuer is `https://n8n.prezent.nl/tstudio/api`. Discovery bestaat ook op `/tstudio/api/.well-known/oauth-protected-resource` en `/tstudio/api/.well-known/oauth-authorization-server`.

## Apparaat koppelen

Open **Instellingen → AI-koppelingen**. Windows gebruikt de bestaande instellingenrijen; macOS gebruikt hetzelfde gegroepeerde instellingenformulier als de overige tabs.

Kies de rechten en klik **Apparaat koppelen via browser**. Log in met je bestaande ThoughtVault-account en eventuele 2FA-code. Dit levert een afzonderlijk loginbewijs op en vervangt het normale apptoken niet. Voltooi de browserstap binnen vijf minuten. De apparaatcredential wordt uitsluitend in de lokale sleutelhanger/keyring bewaard.

| Recht | Wat het toestaat |
| --- | --- |
| `read` | Transcripts, notulen, profielen en appstatus lezen; exporteren |
| `write` | Notulen, titels, tags en eigen profielen wijzigen; schermen openen |
| `record` | Opname starten, pauzeren, hervatten en stoppen |

Opnamebediening vereist apart toestaan. De zichtbare opnamewidget blijft bestaan; Windows toont de opnamefase ook in de titelbalk. Microfoon- en systeemaudiorechten blijven OS-rechten. Windows ondersteunt de bestaande microfoon- en gecombineerde audiomodi; macOS ondersteunt ook uitsluitend systeemaudio.

Wijzig rechten met dezelfde schakelaars. **Ontkoppelen** trekt het apparaat op de server in. Als de server niet bereikbaar is, blokkeert de app lokaal de bediening en toont dat intrekking nog niet bevestigd is; probeer ontkoppelen opnieuw zodra de verbinding hersteld is.

## Claude

Open **Customize → Connectors → Add custom connector** en voer het MCP-endpoint in. Kies aanmelden via OAuth en **Register automatically** als OAuth-clientinstelling. Deze implementatie ondersteunt dynamische clientregistratie, niet de optie voor Claude's gepubliceerde clientidentiteit. Gebruik geen vast normaal apptoken als requestheader.

De actuele Anthropic-documentatie noemt Free, Pro, Max, Team en Enterprise; Free heeft een limiet van één eigen connector. Bij Team/Enterprise moet een bevoegde organisatiebeheerder de connector eerst beschikbaar stellen via **Organization settings → Connectors**. Daarna meldt ieder lid zich afzonderlijk aan. Zie [Anthropic: eigen remote MCP-connectors](https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp).

## ChatGPT

De actuele OpenAI-handleiding gebruikt **ChatGPT Plugins → plus → Add custom MCP server**. Kies een publiek HTTPS-endpoint, voer de MCP-URL in en configureer OAuth met automatische clientregistratie. Installeer de eigen koppeling, begin een nieuw gesprek en selecteer de koppeling via `@`. De beschikbaarheid van het toevoegen van eigen MCP-servers wordt door het account en het workspacebeleid bepaald; er is hier geen specifieke betaalde accountvariant gegarandeerd. Zie [OpenAI: koppelen en testen](https://developers.openai.com/apps-sdk/deploy/connect-chatgpt).

Voor beide clients geldt: de OAuth-aanvraag moet de gewenste scopes (`read write record`) aanvragen, PKCE S256 gebruiken en de `resource` op het exacte MCP-endpoint binden. De browser toont welke rechten de client aanvraagt. De effectief bruikbare rechten zijn de overlap tussen deze OAuth-toestemming en de rechten van het apparaat. Alleen apprechten aanzetten vergroot geen bestaande OAuth-toestemming: autoriseer de client opnieuw als die aanvankelijk alleen `read` aanvroeg.

Deze server heeft een stateless Streamable HTTP-transport met JSON-antwoorden via de officiële Python SDK. Er is geen SSE-only- of stdio-endpoint. Zie [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk).

## Voorbeeldworkflow

1. Vraag `list_devices` op en kies expliciet het juiste `device_id`.
2. Zoek met `list_transcripts`; haal tekst op met `get_transcript`. Gebruik `offset`, `limit` en `next_offset` voor langere transcripts.
3. Laat Claude of ChatGPT notulen genereren uit die tekst. De ingestelde lokale AI-provider hoeft niet te veranderen.
4. Roep `save_minutes` aan met `transcript_id`, de gelezen `revision`, HTML-inhoud en eventueel `style`.
5. Vraag `export_minutes` met `format="pdf"` aan. Download de teruggegeven URL binnen vijf minuten. HTML, Markdown en TXT komen direct als tekst terug.

Voorbeeldvormgeving:

```json
{
  "font": "Georgia",
  "size": 11,
  "text_color": "#222222",
  "accent_color": "#3454d1",
  "line_height": 1.5,
  "margin_mm": 20,
  "paper": "A4",
  "orientation": "portrait"
}
```

Het gedeelde JSON-contract staat in [minutesStyle.schema.json](../../data/minutesStyle.schema.json). CSS wordt uit deze begrensde waarden gegenereerd. HTML wordt gesanitiseerd; scripts, externe stylesheets en afbeeldingen worden niet meegenomen. De PDF-engine krijgt een fetcher die alle externe bestanden en netwerkresources blokkeert. Een profielwijziging beïnvloedt toekomstige uitvoer; een bestaand transcript behoudt zijn opgeslagen notule. Aanpassen van een standaardprofiel maakt een eigen kopie.

Opnames gebruiken `start_recording(device_id, profile_id, mode)` en vervolgens `pause_recording`, `resume_recording`, `stop_recording`. Stoppen gaat door de bestaande verwerkingsflow. De app meldt ontbrekende systeemrechten of een ongeschikte opnamefase.

## Conflicten, intrekking en privacy

Schrijfacties vergelijken de gelezen revisie met de actuele inhoud binnen de opslagoperatie. Lees opnieuw na een conflict. Een opslagfout levert geen succes op.

Opdrachten verlopen na 45 seconden. De relay levert ze eenmaal; de app bewaart een ontvangstbewijs vóór uitvoering en controleert toestemming opnieuw op de server. Een onzekere uitkomst wordt niet automatisch herhaald. Lees de appstatus om een opname-uitkomst te controleren voordat je zelf een nieuwe opdracht geeft.

De relay bewaart alleen tijdelijk de gevraagde inhoud. Opdracht- en resultaatkeys hebben een TTL; PDF-downloads verdwijnen na 300 seconden. De MCP SDK-lognamespace en validatie-inputs worden niet naar applicatielogs geschreven. Zet ook in een reverse proxy of externe observability-tool geen request-/responsebodylogging voor deze routes aan.

## Verificatie en resterend bewijs

Lokaal geverifieerd op 7 oktober 2026:

- Signed macOS-build en vijf nieuwe XCTest-controles voor vormgeving, revisies, profielen en Markdown-tabellen.
- Windows TypeScript/Vite-build en 44 geslaagde tests (17 bestanden), waaronder de daadwerkelijke appopdrachten: lezen → opgemaakte notulen opslaan → vier exportformaten; conflicten, opslagfouten, rechten en eenmalige opnameovergangen.
- Acht geslaagde backendtests met de gepinde FastAPI 0.109.0, Starlette 0.35.1 en Redis-client 4.5.1: account-/apparaatgrenzen, PKCE, replay, refresh/intrekking, offline apparaten, deadlines, SDK-HTTP-handshake en ophalen → opslaan → echte PDF-download. Het desktopapparaat is in deze backendtest geëmuleerd.
- Instellingenlayout bij 360/768/1024/1440 zonder horizontale overflow. De screenshots gebruiken de echte Windows-instellingencomponenten in een browserharnas; verbonden/offline zijn expliciet gesimuleerde UI-states, geen live verbindingsbewijs.

[Niet gekoppeld, 360px](screenshots/windows-unpaired-360.png) · [Verbonden, 360px](screenshots/windows-connected-360.png) · [Offline, 360px](screenshots/windows-offline-360.png) · [Naast de bestaande instellingen, 1440px](screenshots/windows-settings-1440.png).

Nog uit te voeren in de echte doelomgeving: backend/container en discovery publiceren; native Windows-build op Windows; beide desktopapps aan de externe server koppelen; de volledige workflow met Claude én ChatGPT uitvoeren; echte audio starten/pauzeren/hervatten/stoppen vanaf verschillende schermen en één verwerkingstaak na stoppen aantonen. Ook de macOS-documentweergave en PDF met dezelfde stijl visueel vergelijken. Er is geen publicatie in een appcatalogus gedaan.
