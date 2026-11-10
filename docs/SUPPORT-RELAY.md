# Support-relay

De support-relay neemt meldingen en foutrapporten van de ThoughtVault-apps aan en zet ze door naar de feedback-hub. De apps hebben geen login en geen hub-sleutel nodig: de relay kent elke installatie aan een eigen id en geheim en houdt zelf de sleutel van de hub. Besluit en achtergrond: DEC-064 en `docs/plans/2026-11-10-foutrapporten-feedbackhub.md`.

```
app  ->  thoughtvault.yinga.ai/support  (Caddy)  ->  thoughtvault-support:8000  ->  feedback.yinga.ai (hub)
```

Caddy herschrijft `/support/` naar `/tstudio/api/support/`. Dat is ook het interne pad van de routes.

## Contract

Basis: `https://thoughtvault.yinga.ai/support`. Fouten hebben de vorm `{"detail":{"error_code":"...","message":"..."}}` met een Nederlandse tekst.

Alle routes behalve `POST /installations` vragen de headers `X-TV-Installation` (UUID) en `X-TV-Secret`. De relay vergelijkt de sha256 van het geheim met wat bij registratie is bewaard. Het hub-veld `x-widget-user` komt altijd van de geauthenticeerde installatie, nooit uit body of query.

| Route | Body | Limiet | Antwoord |
|---|---|---|---|
| `POST /installations` | `{installationId, secret}`; geheim is 32 willekeurige bytes als base64url (43 tekens) | 4 KB, 5 per uur per IP | 201 nieuw, 200 zelfde paar, 409 `installation_conflict` |
| `POST /reports` | zie hieronder | 1,5 MB, 20 per uur per installatie, 60 per uur per IP | `{ticketId, ref, repeated, count, logAttached}` |
| `GET /tickets` | geen | 120 per uur per installatie (gedeeld) | `{data:[...], pagination:{...}}`, maximaal 50 |
| `GET /unread-count` | geen | gedeeld | `{data:{count}}` |
| `GET /tickets/{id}/messages` | geen | gedeeld | `{data:[...]}`, markeert als gelezen |
| `POST /tickets/{id}/messages` | `{body}` van 1 tot 5000 tekens | 16 KB, gedeeld | het nieuwe bericht |

Bij een bestaand id met een ander geheim blijft de opgeslagen hash ongewijzigd en komt er 409.

### Velden van een melding

| Veld | Regels |
|---|---|
| `kind` | `auto` of `manual` |
| `category` | `BUG`, `FEATURE_REQUEST` of `QUESTION`; bij `auto` altijd `BUG` |
| `stage` | `opnemen`, `transcriberen`, `notule` of `crash`; leeg bij `manual` |
| `shownMessage` | 1 tot 5000 tekens, de melding zoals de gebruiker hem zag |
| `errorText` | maximaal 2000 |
| `fingerprint` | alleen bij `auto`, 16 tot 64 kleine hexcijfers |
| `clickPath` | maximaal 30 items van maximaal 80 tekens |
| `appVersion`, `os`, `device`, `platform` | maximaal 100 |
| `name` | maximaal 200 |
| `email` | maximaal 320 |
| `occurredAt` | maximaal 40 |
| `log` | maximaal 1 MB |

Naar de hub gaat het in twee stappen: eerst het ticket, daarna een bericht "Logbestand van dit apparaat" met bijlage `thoughtvault-log.txt` (text/plain). Mislukt alleen de logstap terwijl het ticket bestaat, dan komt er 200 met `logAttached: false`, zodat een nieuwe poging geen tweede ticket maakt.

Velden van een ticket: `id, ref, status, category, description, createdAt, unread, lastMessage`. Van een bericht: `id, body, senderRole, createdAt` en eventueel bijlagen. Datums uit de hub kunnen milliseconden bevatten. Een ticket van een andere installatie geeft 404 `not_found`. Het ticketid in het pad moet `^[A-Za-z0-9_-]{1,64}$` zijn, anders geeft FastAPI zelf 422 `{"detail":[...]}`.

## Foutcodes en wat de app doet

| Status en code | Betekenis | App |
|---|---|---|
| 401 `installation_invalid` | header ontbreekt, onbekend of geheim klopt niet | opnieuw registreren met hetzelfde paar, daarna één keer herhalen |
| 409 `installation_conflict` | id bestaat met ander geheim | nieuw id en geheim maken, registreren, één keer herhalen |
| 413 `payload_too_large` | body te groot | weggooien, lokaal loggen |
| 422 `validation_error` | veld ongeldig | weggooien, lokaal loggen |
| 429 `rate_limit_exceeded` | van relay of hub, met `Retry-After` in seconden | in de wachtrij houden, na `Retry-After` opnieuw |
| 502 `hub_unavailable` | hub gaf 401, 5xx, een 404 buiten een ticketroute, geen JSON of een misvormd antwoord | in de wachtrij houden, later opnieuw |
| 503 `support_unavailable` | geen hub-sleutel ingesteld | in de wachtrij houden, later opnieuw |
| `hub_error` | andere 4xx van de hub, met die status | melden aan de gebruiker bij handmatige acties |
| netwerkfout | geen verbinding | in de wachtrij houden |

`logAttached: false` geldt als verzonden.

## Dubbele fouten

Alleen bij `kind: auto`, per paar (installatie, fingerprint). Is het ticket nog open, dan gaat er een vervolgbericht "Opnieuw opgetreden (n keer), laatste keer <occurredAt>" met het logbestand, en de teller gaat pas omhoog als dat lukt. Is het ticket RESOLVED, CLOSED of in de hub verwijderd, dan komt er een nieuw ticket en wordt de koppeling overschreven. De bescherming is een lock binnen het proces; dat klopt omdat uvicorn met één worker draait.

De fingerprint is voor alle platforms hetzelfde: SHA-256 van de UTF-8-tekst `<stage>|<ruwe foutmelding>` met de cijfers 0 tot 9 weggehaald, de eerste 16 hexcijfers in kleine letters. Hij wordt berekend vóór het maskeren van het logbestand.

## Waar de code staat

Repo `transcript-studio-backend`, onder `src/insanely_fast_whisper_api/app/`:

| Bestand | Inhoud |
|---|---|
| `support_app.py` | FastAPI-app; de lifespan maakt alleen de twee supporttabellen; `GET /health`; docs en openapi uit; eigen 429-handler |
| `routes/support.py` | de routes |
| `services/support_hub.py` | asynchrone httpx-client voor de hub |
| `support_models.py` | tabellen `support_installations` en `support_issues` |

Buiten `src`: `Dockerfile.support` (python:3.10-slim, gebruiker `relay`, healthcheck, uvicorn met één worker op poort 8000), `Dockerfile.support.dockerignore` (allowlist: alleen `requirements-support.txt` en `src`), `docker-compose.support.yml`, `requirements-support.txt` en `.env.support.example`.

Testen, vanuit de backend-repo:

```bash
PYTHONPATH=src python -m pytest tests/test_support_relay.py tests/test_profile_choice.py tests/test_note_completion_validation.py
```

Dat geeft 85 geslaagd. Draai nooit een kale `pytest`: `tests/test_race_condition_fix.py` praat met productie.

## Deploy en bediening op n8n01

Server n8n01 (`3.69.205.209`, ssh-alias `n8n01`). De oude container `n8n_transcript_studio` draait daar niet (gecontroleerd op 10 november 2026), dus `https://n8n.prezent.nl/tstudio/api/...` geeft 502: nginx (`n8n_nginx`) verwijst `/tstudio/` nog naar dat container.

| Onderdeel | Waarde |
|---|---|
| Map | `/home/michelk/thoughtvault-support` |
| Container | `thoughtvault-support`, netwerk `yinga-network`, `mem_limit: 256m` |
| Volume | `thoughtvault_support_data`, SQLite op `/data/support.db` |
| `.env` | alleen `FEEDBACK_HUB_URL` en `FEEDBACK_HUB_INSTANCE_KEY`, mode 600 |
| `DEPLOYED_FROM` | bestand met de commit die draait |
| Redis | geen; de limiter valt terug op geheugen |

De opstartmelding "Rate limiter: Redis unavailable ..." is dus normaal.

Deployen: kopieer de bestanden naar de map, bijvoorbeeld met `git archive HEAD Dockerfile.support Dockerfile.support.dockerignore docker-compose.support.yml requirements-support.txt src`, en draai daar:

```bash
docker compose -f docker-compose.support.yml up -d --build --wait
```

Schrijf daarna de commit naar `DEPLOYED_FROM`. Logs: `docker logs thoughtvault-support`. De hub is vanuit de container bereikbaar via `https://feedback.yinga.ai` (ingesteld) en `http://172.17.0.1:8085`.

### Caddy

Container `yinga-caddy`, bestand `/home/michelk/yinga/caddy/Caddyfile`, kopie in de repo: `scripts/infra/thoughtvault-releases.caddy`. In het blok `thoughtvault.yinga.ai`, vóór de website-fallback:

```
@support path /support/*
handle @support {
    request_body { max_size 2MB }
    uri replace /support/ /tstudio/api/support/ 1
    reverse_proxy thoughtvault-support:8000
}
```

Caddy overschrijft `X-Forwarded-For` en er staat geen Cloudflare voor, dus de relay ziet het echte IP van de client. Wijzigen gaat zoals in `scripts/deploy-website.sh`: eerst een backup van het bestand (de vorige versie staat op `Caddyfile.support-20261110124655`), dan aanpassen, dan

```bash
docker exec yinga-caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker exec yinga-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

Pas de repo-kopie mee aan. `/releases/macos/stable.xml` gaf al 404 vóór deze route: er staat geen macOS-map bij de releases, omdat macOS via TestFlight loopt.

## De hub

Tool-slug `thought-vault`, naam ThoughtVault, één instantie "ThoughtVault", prefix `TV`, schaduwmodus uit. De hub leidt het prefix af van de slug; `thoughtvault` had `TH` opgeleverd. Refs hebben zes cijfers (`TV-000001`). De hub mailt de melder bij aanmaken, statuswijziging en antwoord, en laat zelf 10 nieuwe tickets per uur per installatie toe (de relay 20). De hub ruimt gesloten tickets nog niet automatisch op; dat is een aparte taak in de hubrepo.

## Testen tegen de echte relay

Gebruik nooit een echt e-mailadres: de hub mailt de melder. Neem `@example.com` en sluit testtickets daarna. Op 10 november liepen `TV-000001` (automatisch, twee gelijke meldingen werden één ticket met teller 2 en logbestand) en `TV-000002` (handmatig, bijlage teruggelezen via de relay, antwoord via de relay) zo door de hele keten; beide zijn gesloten.

## Bekende grenzen

- De dedup-lock zit in het proces. Meer dan één worker breekt de garantie.
- De limiter staat in het geheugen en begint na een herstart opnieuw.
- Gesloten tickets blijven in de hub staan tot het opruimen is gebouwd.
- Zonder `FEEDBACK_HUB_INSTANCE_KEY` geeft elke hubroute 503.
