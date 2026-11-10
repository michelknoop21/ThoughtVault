# Fase a: support-relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Routes zonder login onder `/tstudio/api/support` in de container `n8n_transcript_studio` die installaties aanmelden, meldingen met logbestand doorzetten naar de feedback-hub (voorvoegsel `TV`) en antwoorden teruggeven, bereikbaar als `https://thoughtvault.yinga.ai/support`.

**Architecture:** Een nieuwe router `routes/support.py` controleert kenmerk en geheim, houdt limieten bij via de bestaande slowapi-limiter en onthoudt per (installatie, vingerafdruk) welk hubticket erbij hoort in twee nieuwe tabellen. De hubclient staat apart in `services/support_hub.py` en praat met `httpx.AsyncClient` met de widget-API van de hub. Caddy op n8n01 herschrijft `/support/` naar `/tstudio/api/support/`, net als het bestaande `@updater`-blok.

**Tech Stack:** FastAPI 0.109.0, SQLAlchemy 2.0.46, slowapi 0.1.9, httpx 0.28.1 (`AsyncClient`, in tests `MockTransport` en `ASGITransport`), pytest met de anyio-plugin die met httpx meekomt.

**Spec:** `docs/plans/2026-11-10-foutrapporten-feedbackhub.md` in de app-repo, branch `docs/plan-foutrapporten-feedbackhub`. Leidend: hoofdstuk 2, 3, 4, 5 "Fase a" en 7. Besluiten uit hoofdstuk 2 liggen vast.

`APP` = `src/insanely_fast_whisper_api/app` in `transcript-studio-backend`. Regelnummers komen van `origin/main` op `7909542`.

## Werkwijze voor de uitvoerder

Werk op een eigen branch vanaf `origin/main` van de backend, in een worktree (superpowers:using-git-worktrees). Nooit op `main` committen, nooit in de hoofdwerkmap: daar staat branch `fix/validate-note-completion` met niet-gecommit werk in `APP/app.py`, `APP/routes/auth.py`, `.env.example` en `requirements.txt` (MCP-relay). Reken bij het samenvoegen op conflicten in `APP/app.py` en `.env.example`.

```bash
cd /Volumes/SSD/Projects/transcript-studio-backend
git fetch
git worktree add -b feat/support-relay /Volumes/SSD/Projects/transcript-studio-backend-support-relay origin/main
```

Testomgeving. Op `origin/main` staat geen pytest-config en geen `conftest.py`, en pytest zit niet in `requirements.txt`. De bestaande tests importeren `insanely_fast_whisper_api...`, dus `src` moet op het pad. De systeem-Python mist slowapi. Eenmalig een venv buiten de worktree:

```bash
python3 -m venv ~/.venvs/tstudio-support
~/.venvs/tstudio-support/bin/pip install fastapi==0.109.0 starlette==0.35.1 SQLAlchemy==2.0.46 slowapi==0.1.9 httpx==0.28.1 redis==4.5.1 python-multipart==0.0.17 "pydantic>=2.0.0" "pydantic-settings>=2.0.0" "python-dotenv>=0.21.0" pytest
```

Testopdracht, vanuit de worktree:

```bash
PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v
```

De suite draait in seconden en hoeft niet via `heavy run`. Draai nooit een kale `pytest` of `pytest --cov=src` (zo staat het in het projectinstructiebestand van de backend, r.15): dat verzamelt ook `tests/test_race_condition_fix.py`, een Playwright-test die uploadt naar productie en via ssh in de productiedatabase kijkt.

`APP/app.py` importeert `faster_whisper` (r.32) en `torch` (r.909) en is in tests dus niet te importeren. De tests bouwen een kleine FastAPI-app met alleen de supportrouter, dezelfde limiter en dezelfde 429-handler.

## Afwijkingen tussen spec en code

Vastgesteld op `origin/main` (`7909542`) en in `/Volumes/SSD/Projects/feedback-hub` (`298ca28`). Het plan volgt de code waar die van de spec afwijkt.

1. De IP-limiet. Spec r.73 zegt dat de limiter het eerste `X-Forwarded-For`-adres gebruikt via `APP/middleware/rate_limiting.py` r.22-27. De limiter zelf (`APP/rate_limiting.py` r.7 en r.37) gebruikt `slowapi.util.get_remote_address`, dus `request.client.host`. Uvicorn draait zonder `--forwarded-allow-ips` (Dockerfile laatste regel, `start.sh` r.3), dus dat is het adres van de proxy en delen alle apps één IP-emmer. De functie uit de middleware wordt alleen in de 429-log gebruikt (r.35). Dit plan geeft de IP-limieten daarom een eigen `key_func` die die middlewarefunctie aanroept.
2. Het voorvoegsel. `connect_tool` heeft geen veld `refPrefix`; de hub leidt het af uit de slug (`backend/src/services/publicRef.ts` r.97-101, `onboarding.ts` r.101), dus `thoughtvault` zou `TH` worden. Besluit van Michel op 10 november: slug `thought-vault`, waarmee de hub zelf `TV` geeft. Geen handwerk in de hubdatabase.

Antwoordvormen van de relay, gedeeld met fase b en c: de leesroutes geven de hub-body ongewijzigd door. `GET /tickets` geeft `{"data": [ticket...], "pagination": {...}}`, `GET /unread-count` geeft `{"data": {"count": n}}`, `GET /tickets/{id}/messages` geeft `{"data": [bericht...]}`. Ticketvelden `id`, `ref`, `status`, `category`, `description`, `createdAt`, `unread`, `lastMessage`; berichtvelden `id`, `body`, `senderRole`, `createdAt`. Hubdatums kunnen milliseconden hebben. Referenties hebben zes cijfers (`TV-000001`). Vingerafdruk op alle platforms: SHA-256 over de UTF-8-string `<stage>|<ruwe foutmelding>` waaruit de tekens 0 tot en met 9 zijn verwijderd, eerste 16 tekens lowercase hex, berekend vóór het afschermen.
3. De referentie heeft zes cijfers: `TV-000001`, niet `TV-1` (`publicRef.ts` r.31-35).
4. `environment` kent op de hub alleen productie, staging en ontwikkeling (`services/context.ts` r.10-31). Een platformnaam wordt stil `null`. Het plan stuurt `environment=production`; het platform staat al in `browserInfo` en `diagnostics`.
5. De hub leest `userId` bij het aanmaken uit de formuliervelden, niet uit de header (`routes/widget.ts` r.243-262). De relay stuurt beide.
6. Een bericht zonder bijlage mag JSON zijn (`middleware/upload.ts` r.146-149). Alleen het logbericht is multipart.
7. `diagnostics` mag maximaal 64 KB zijn (`services/diagnostics.ts` r.9). Met de veldgrenzen uit het contract blijft de blob daar ruim onder.
8. `/tstudio/api/version` bestaat (`APP/routes/auth.py` r.577) en dient als testroute in taak 1.
9. Spec r.95 noemt `docs/BACKEND.md` als bron voor de deploy. Dat bestand staat buiten git en is voor dit plan niet gelezen; taak 11 verwijst ernaar.

## Global Constraints

- De container draait Python 3.10 (conda-pad in de Dockerfile). Geen syntax of stdlib van 3.11 of later.
- Geen nieuwe regels in `requirements.txt`. `httpx==0.28.1` en `slowapi==0.1.9` staan er al.
- Routes onder `/tstudio/api/support`, alles JSON. Behalve `POST /installations` dragen alle verzoeken `X-TV-Installation` en `X-TV-Secret`; de relay vergelijkt `sha256(geheim)` met de opgeslagen hash, mis = 401.
- Limieten: `POST /installations` 5 per uur per IP; `POST /reports` 20 per uur per installatie en 60 per uur per IP, verzoek max 1,5 MB (1 572 864 bytes) anders 413; de vier leesroutes samen 120 per uur per installatie.
- Naar de hub: `x-instance-key` = `FEEDBACK_HUB_INSTANCE_KEY`, `x-widget-user` = installatiekenmerk. Een 403 op een ticketroute wordt 404, een netwerkfout of time-out 502, een 401 van de hub 502, een 429 blijft 429.
- Zonder `FEEDBACK_HUB_INSTANCE_KEY` antwoorden alle supportroutes 503.
- Foutantwoorden via `raise_api_error` uit `APP/errors.py`, met Nederlandse tekst in `ERROR_MESSAGES` en zonder em-dash.
- `APP/routes/support.py` blijft onder 300 regels; `APP/models.py` (747 regels) groeit niet.
- De oude feedbackmodule blijft staan en geregistreerd (besluit 15).
- De hubsleutel staat alleen in de server-`.env`, nooit in een repo, commit of bericht.
- Elke handeling op n8n01 of in de hub pas na akkoord van Michel.
- Commitberichten in de stijl van de repo, `feat(support): ...`, zonder attributieregels.

## Review Focus

1. Een installatie die na herinstallatie hetzelfde kenmerk met een nieuw geheim aanmeldt, krijgt 409 met `error_code` `installation_conflict`; de opgeslagen hash blijft staan en hetzelfde apparaat komt alleen verder met een nieuw kenmerk (de app maakt dan een nieuw paar en meldt opnieuw aan; dat gedrag hoort in fase b en c). Test in taak 3.
2. Een log met tekens die niet als UTF-8 te schrijven zijn (een losse surrogaat via `\ud800`, een NUL-byte) geeft geen 500: de bijlage gaat mee met een vervangteken. Een body met ongeldige UTF-8-bytes geeft 422. Tests in taak 5 en 6.
3. Twee identieke automatische meldingen die tegelijk binnenkomen (crash plus vastgelopen transcriptie bij herstart) leveren één hubticket op; de tweede wordt het vervolgbericht met teller 2. Test in taak 7.
4. Een hub die na het aanmaken van het ticket time-out geeft op het logbericht: de app krijgt 502 en houdt de melding in zijn wachtrij, de koppeling is al opgeslagen, en de herhaling wordt een vervolgbericht op hetzelfde ticket in plaats van een tweede ticket. Test in taak 6.
5. Een ticket dat Michel in de hub heeft verwijderd terwijl de koppeling nog bestaat (`GET /tickets/:id` geeft 404): de volgende identieke melding maakt een nieuw ticket en overschrijft de koppeling. Test in taak 7.

---

## Bestanden

| Bestand | Verantwoordelijkheid |
| --- | --- |
| `APP/config.py` (wijzigen) | twee instellingen voor de hub |
| `APP/errors.py` (wijzigen) | zes nieuwe foutcodes |
| `APP/support_models.py` (nieuw) | tabellen `support_installations` en `support_issues` op de bestaande `Base` |
| `APP/database.py` (wijzigen, r.102-108) | import van `support_models` in `init_database()` |
| `APP/services/support_hub.py` (nieuw) | alle aanroepen naar de hub, foutvertaling |
| `APP/routes/support.py` (nieuw) | zes routes, schema's, identiteitscontrole, ontdubbelen |
| `APP/app.py` (wijzigen, r.970-993) | router registreren |
| `.env.example` (wijzigen) | de twee namen |
| `tests/conftest.py` (nieuw) | omgeving vóór de eerste import |
| `tests/test_support_relay.py` (nieuw) | alle tests van dit plan |

De hubclient staat in een eigen bestand omdat routes, schema's en ontdubbelen samen al rond de 250 regels komen; met de foutvertaling en het multipartwerk erbij gaat `routes/support.py` over de 300.

---

### Task 1: Servercontroles (alleen lezen, geen code)

**Files:** geen.

**Interfaces:**
- Consumes: niets.
- Produces: de waarde voor `FEEDBACK_HUB_URL` (taak 10 en 11), het pad van de servercompose en zijn `env_file`-regel (taak 11), de vergelijking van de serverbestanden met `origin/main` (taak 11), het verschil tussen live Caddyfile en repobestand (taak 12). Vastleggen als notitie bij deze taak in dit planbestand, zonder sleutels of wachtwoorden.

- [ ] **Step 1: Live Caddyfile vergelijken** (vraag akkoord van Michel voor uitvoering)

```bash
ssh michelk@3.69.205.209 'cat /home/michelk/yinga/caddy/Caddyfile' > /tmp/caddy-live.txt
git -C /Volumes/SSD/Projects/thoughtvault-native show origin/main:scripts/infra/thoughtvault-releases.caddy > /tmp/caddy-repo.txt
```

Verwacht: het blok `thoughtvault.yinga.ai { ... }` in de live versie is gelijk aan het repobestand. Noteer elk verschil. Beide bestanden daarna verwijderen.

- [ ] **Step 2: Poort 5678 naar de container** (vraag akkoord van Michel voor uitvoering)

```bash
ssh michelk@3.69.205.209 "curl -sS -H 'Host: n8n.prezent.nl' http://172.17.0.1:5678/tstudio/api/version"
```

Verwacht: `{"version":"1.0.13","minimum_version":"1.0.0","current_version":"1.0.13","is_supported":true}`. Een andere uitkomst: stoppen en melden, want dan klopt de route uit spec hoofdstuk 3 niet.

- [ ] **Step 3: Hub bereiken vanuit de container** (vraag akkoord van Michel voor uitvoering)

```bash
ssh michelk@3.69.205.209 "docker exec n8n_transcript_studio python -c \"import httpx
for u in ('http://172.17.0.1:8085', 'https://feedback.yinga.ai'):
    try: print(u, httpx.get(u + '/api/widget/config', timeout=5).status_code)
    except Exception as e: print(u, type(e).__name__)\""
```

Verwacht: een HTTP-status (401 zonder sleutel) bij minstens één adres. Keuze: het interne adres `http://172.17.0.1:8085` als dat antwoordt (zo doet ProspectFlow het, `ProspectFlow/.env.prod.example` r.80), anders `https://feedback.yinga.ai`. Noteer de keuze.

- [ ] **Step 4: Servercompose en `env_file`** (vraag akkoord van Michel voor uitvoering)

```bash
ssh michelk@3.69.205.209 "docker inspect n8n_transcript_studio --format '{{index .Config.Labels \"com.docker.compose.project.config_files\"}}'"
ssh michelk@3.69.205.209 "grep -n -A2 'env_file' <pad uit de vorige regel>"
```

Verwacht: `env_file:` met `- .env`, zoals `docker-compose.yml` r.10-11 op main. Ontbreekt die, dan krijgen de twee namen in taak 11 ook een regel onder `environment:`. Lees geen omgevingswaarden uit (`docker inspect` zonder `--format`, `docker exec env`).

- [ ] **Step 5: Serverbestanden tegen origin/main** (vraag akkoord van Michel voor uitvoering)

```bash
ssh michelk@3.69.205.209 'docker exec n8n_transcript_studio sh -c "cd /app/src/insanely_fast_whisper_api/app && sha256sum app.py config.py database.py errors.py"'
cd /Volumes/SSD/Projects/transcript-studio-backend && for f in app.py config.py database.py errors.py; do git show origin/main:src/insanely_fast_whisper_api/app/$f | shasum -a 256; done
```

Verwacht: vier gelijke hashes. Wijkt er een af, dan draait op de server code die niet op main staat. Stoppen en aan Michel melden; taak 11 overschrijft die bestanden anders.

---

### Task 2: Testopzet, instellingen en tabellen

**Files:**
- Create: `tests/conftest.py`
- Create: `APP/support_models.py`
- Modify: `APP/config.py:121-125` (nieuw blok na Notifications)
- Modify: `APP/database.py:102-108`
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: `Base` uit `APP/models.py` r.14, `engine` en `get_db_session` uit `APP/database.py`.
- Produces:
  - `settings.feedback_hub_url: str` (standaard `"https://feedback.yinga.ai"`, env `FEEDBACK_HUB_URL`) en `settings.feedback_hub_instance_key: str` (standaard `""`, env `FEEDBACK_HUB_INSTANCE_KEY`), beide via `_env_field`.
  - `class SupportInstallation(Base)`, tabel `support_installations`: `id: String(36)` PK, `secret_hash: String(64)` not null, `created_at: DateTime` standaard `datetime.utcnow`, `last_seen_at: DateTime` nullable.
  - `class SupportIssue(Base)`, tabel `support_issues`: `installation_id: String(36)` FK naar `support_installations.id`, `fingerprint: String(64)`, samen de primaire sleutel (daarmee uniek), `ticket_id: String(64)` not null, `count: Integer` standaard 1, `first_seen` en `last_seen: DateTime`.
  - In `tests/test_support_relay.py`: `pytestmark = pytest.mark.anyio`, fixture `anyio_backend` (geeft `"asyncio"`) en autouse-fixture `clean_db` (`init_database()` en `limiter.reset()` vooraf, `Base.metadata.drop_all(database.engine)` na afloop). Taak 3 voegt `client`, `register(client, iid, secret, ip="203.0.113.7") -> httpx.Response`, `registered(client, ip="203.0.113.7") -> tuple[str, str]`, `auth(iid, secret) -> dict[str, str]` en `code(response) -> str` toe (die laatste leest `response.json()["detail"]["error_code"]`, de vorm van `APIError`). Taak 5 voegt `hub` toe.

- [ ] **Step 1: `tests/conftest.py` schrijven**

Zet vóór elke import van de app: `DATABASE_URL=sqlite://` (in-memory; `database.py` r.26-31 gebruikt dan `StaticPool`), `REDIS_URL=redis://127.0.0.1:1/0` (weigert direct, de limiter valt terug op `memory://`, `rate_limiting.py` r.56-64), `FEEDBACK_HUB_URL=http://hub.test`, `FEEDBACK_HUB_INSTANCE_KEY=fh_test`. Gebruik `os.environ[...] = ...` op moduleniveau. Een conftest is nodig omdat pytest de bestaande testbestanden eerder verzamelt en `settings` maar één keer wordt aangemaakt.

- [ ] **Step 2: Falende tests schrijven**

```python
def test_hub_settings_have_spec_defaults():
    from insanely_fast_whisper_api.app.config import Settings
    assert Settings.model_fields["feedback_hub_url"].default == "https://feedback.yinga.ai"
    assert Settings.model_fields["feedback_hub_instance_key"].default == ""

def test_init_database_creates_support_tables():
    init_database()
    assert {"support_installations", "support_issues"} <= set(sqlalchemy.inspect(database.engine).get_table_names())

def test_support_issue_is_unique_per_installation_and_fingerprint():
    init_database()
    with pytest.raises(IntegrityError):
        with get_db_session() as db:
            db.add(SupportInstallation(id=IID, secret_hash="0" * 64))
            db.add(SupportIssue(installation_id=IID, fingerprint="a" * 16, ticket_id="t1"))
            db.flush()
            db.add(SupportIssue(installation_id=IID, fingerprint="a" * 16, ticket_id="t2"))
```

Constanten bovenaan het testbestand: `IID = "6f1c2a9e-3b4d-4e5f-8a7b-9c0d1e2f3a4b"`, `SECRET = "q" * 43`, `FP = "3fa29c0d1e2f3a4b"`.

- [ ] **Step 3: Draaien en zien falen**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v`
Expected: FAIL, `KeyError: 'feedback_hub_url'` en `ModuleNotFoundError: ...support_models`.

- [ ] **Step 4: Implementeren**

De twee velden in `APP/config.py` onder een kop `# Feedback-hub (support-relay)`. `APP/support_models.py` met de twee klassen uit Interfaces. In `init_database()` direct na `from .models import Base`: `from . import support_models  # noqa: F401`.

- [ ] **Step 5: Fixtures vastleggen**

Nu alleen `anyio_backend` en `clean_db`. De twee hieronder komen in de taak die hun module aanmaakt, zodat het testbestand na elke taak importeerbaar blijft: `client` in taak 3 stap 1, `hub` in taak 5 stap 1.

`hub`: een `FakeHub` met `requests: list[httpx.Request]`, `tickets: dict[str, str]` (id naar status) en `override: dict[tuple[str, str], httpx.Response | Exception]` op (methode, pad). Zonder override antwoordt hij zo:

| Verzoek | Antwoord |
| --- | --- |
| `POST /api/widget/tickets` | 201, `{"data": {"id": "t<n>", "ref": "TV-00000<n>", "status": "NEW"}}`, n telt op vanaf 1, ticket in `tickets` |
| `GET /api/widget/tickets/{id}` | 200 met `id`, `ref`, `status` uit `tickets`, of 404 `{"error": "Melding"}` |
| `POST /api/widget/tickets/{id}/messages` | 201, `{"data": {"id": "m<n>"}}` |
| `GET /api/widget/tickets/mine` | 200, `{"data": [], "pagination": {}}` |
| `GET /api/widget/unread-count` | 200, `{"data": {"count": 3}}` |
| `GET /api/widget/tickets/{id}/messages` | 200, `{"data": []}` |

Een `Exception` in `override` wordt opgegooid; een `float` in `hub.delay` laat de handler eerst `await anyio.sleep(delay)` doen. Installeren met `monkeypatch.setattr(support_hub, "HUB_TRANSPORT", httpx.MockTransport(fake.handler))`.

`client`: maakt `FastAPI()`, een `APIRouter(prefix="/tstudio/api")` met `support.router`, `app.state.limiter = limiter`, `app.add_exception_handler(RateLimitExceeded, custom_rate_limit_handler)`, en levert `httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")`. Starlette's `TestClient` wordt bewust niet gebruikt: met de gepinde combinatie starlette 0.35.1 en httpx 0.28.1 is niet vastgesteld dat hij werkt, `ASGITransport` hangt alleen van httpx af.

- [ ] **Step 6: Draaien en zien slagen, plus de bestaande tests**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py tests/test_profile_choice.py tests/test_note_completion_validation.py -v`
Expected: PASS. Faalt de installatie of import van de gepinde versies op de lokale Python, dan melden; pins niet ophogen.

- [ ] **Step 7: Commit**

```bash
git add tests/conftest.py tests/test_support_relay.py src/insanely_fast_whisper_api/app/config.py src/insanely_fast_whisper_api/app/database.py src/insanely_fast_whisper_api/app/support_models.py
git commit -m "feat(support): add hub settings and support tables"
```

---

### Task 3: Aanmelden van een installatie, 503 zonder sleutel, IP-limiet

**Files:**
- Create: `APP/routes/support.py`
- Modify: `APP/errors.py:19-33`
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: taak 2 (tabellen, fixtures), `limiter` uit `APP/rate_limiting.py`, `get_remote_address` uit `APP/middleware/rate_limiting.py` r.22, `raise_api_error` uit `APP/errors.py` r.59.
- Produces:
  - `ERROR_MESSAGES` krijgt: `support_unavailable` "Meldingen versturen is tijdelijk niet mogelijk. Probeer het later opnieuw.", `installation_conflict` "Deze installatie is al aangemeld met een ander geheim. Meld je opnieuw aan met een nieuw kenmerk.", `installation_invalid` "Deze installatie is onbekend of het geheim klopt niet.", `payload_too_large` "De melding is te groot (maximaal 1,5 MB).", `hub_unavailable` "De meldingen-hub is even niet bereikbaar. De melding wordt later opnieuw verstuurd.", `hub_error` "De melding kon niet worden verwerkt."
  - `router = APIRouter(prefix="/support", tags=["support"], dependencies=[Depends(require_hub)])`
  - `def require_hub() -> None`: 503 `support_unavailable` als `settings.feedback_hub_instance_key` leeg is.
  - `def client_ip_key(request: Request) -> str`: `f"ip:{get_remote_address(request)}"`.
  - `def installation_key(request: Request) -> str`: `f"tv:{request.headers.get('X-TV-Installation', '')}"`.
  - `def hash_secret(secret: str) -> str`: `hashlib.sha256(secret.encode()).hexdigest()`.
  - `class InstallationIn(BaseModel)`: `installation_id: UUID` (alias `installationId`), `secret: str` met patroon `^[A-Za-z0-9_-]{43}=?$` (32 bytes base64url).
  - `POST /installations` → `async def register_installation(request: Request, response: Response, data: InstallationIn) -> dict`, `@limiter.limit("5/hour", key_func=client_ip_key)`. Antwoord `{"installationId": "<uuid>"}` met 201 (nieuw) of 200 (zelfde paar); 409 `installation_conflict` bij ander geheim, zonder de hash te wijzigen. Logt `support: installation registered ip=%s` met `get_remote_address(request)` (taak 13 controleert daarmee welk adres de container ziet).

- [ ] **Step 1: Falende tests schrijven**

```python
async def test_routes_answer_503_without_hub_key(client, monkeypatch):
    monkeypatch.setattr(settings, "feedback_hub_instance_key", "")
    r = await register(client, IID, SECRET)
    assert r.status_code == 503 and code(r) == "support_unavailable"

async def test_register_installation_is_idempotent(client):
    first, again = await register(client, IID, SECRET), await register(client, IID, SECRET)
    assert (first.status_code, again.status_code) == (201, 200)
    assert again.json() == {"installationId": IID}

async def test_reinstall_with_other_secret_is_409_and_keeps_hash(client):
    await register(client, IID, SECRET)
    r = await register(client, IID, "z" * 43)
    assert r.status_code == 409 and code(r) == "installation_conflict"
    assert (await register(client, IID, SECRET)).status_code == 200
    assert (await register(client, "0b9d8c7e-6f5a-4b3c-9d2e-1f0a9b8c7d6e", "z" * 43)).status_code == 201

async def test_secret_is_stored_as_sha256(client):
    await register(client, IID, SECRET)
    with get_db_session() as db:
        assert db.get(SupportInstallation, IID).secret_hash == hashlib.sha256(SECRET.encode()).hexdigest()

async def test_register_rejects_malformed_input(client):
    assert (await register(client, "abc", SECRET)).status_code == 422
    assert (await register(client, IID, "short")).status_code == 422

async def test_register_limit_is_five_per_hour_per_ip(client):
    for _ in range(5):
        assert (await register(client, str(uuid.uuid4()), SECRET, ip="203.0.113.7")).status_code == 201
    assert (await register(client, str(uuid.uuid4()), SECRET, ip="203.0.113.7")).status_code == 429
    assert (await register(client, str(uuid.uuid4()), SECRET, ip="198.51.100.9")).status_code == 201
```

Schrijf in deze stap ook de fixture `client` en de helpers uit taak 2 (Interfaces en stap 5). `register` stuurt het IP als header `X-Forwarded-For`; `registered` meldt een vers `uuid4` aan met `SECRET` en geeft `(kenmerk, SECRET)`.

- [ ] **Step 2: Draaien en zien falen**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v -k "register or 503 or reinstall or sha256"`
Expected: FAIL, `ModuleNotFoundError: ...routes.support`.

- [ ] **Step 3: Implementeren** volgens Interfaces. Vergelijk hashes met `hmac.compare_digest`.

- [ ] **Step 4: Draaien en zien slagen**

Run: zelfde opdracht als stap 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/insanely_fast_whisper_api/app/routes/support.py src/insanely_fast_whisper_api/app/errors.py tests/test_support_relay.py
git commit -m "feat(support): register installations with hashed secret"
```

---

### Task 4: Identiteitscontrole als dependency

**Files:**
- Modify: `APP/routes/support.py`
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: `SupportInstallation`, `hash_secret` (taak 2 en 3).
- Produces: `def require_installation(x_tv_installation: str = Header("", alias="X-TV-Installation"), x_tv_secret: str = Header("", alias="X-TV-Secret")) -> str`. Geeft het kenmerk terug en zet `last_seen_at`; leeg, onbekend of fout geheim geeft 401 `installation_invalid`. Synchroon (`def`), FastAPI draait hem in de threadpool.

- [ ] **Step 1: Falende tests schrijven**

```python
def _seed_installation():
    init_database()
    with get_db_session() as db:
        db.add(SupportInstallation(id=IID, secret_hash=hash_secret(SECRET)))

def test_require_installation_accepts_registered_pair():
    _seed_installation()
    assert require_installation(x_tv_installation=IID, x_tv_secret=SECRET) == IID
    with get_db_session() as db:
        assert db.get(SupportInstallation, IID).last_seen_at is not None

@pytest.mark.parametrize("iid,secret", [(IID, "z" * 43), ("0b9d8c7e-6f5a-4b3c-9d2e-1f0a9b8c7d6e", SECRET), ("", "")])
def test_require_installation_rejects_wrong_unknown_or_missing(iid, secret):
    _seed_installation()
    with pytest.raises(APIError) as exc:
        require_installation(x_tv_installation=iid, x_tv_secret=secret)
    assert exc.value.status_code == 401
    assert exc.value.detail["error_code"] == "installation_invalid"
```

Deze tests zijn synchroon. De anyio-markering op moduleniveau laat een gewone functie gewoon draaien. De autouse-fixture `clean_db` uit taak 2 ruimt de tabellen op.

- [ ] **Step 2: Draaien en zien falen**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v -k require_installation`
Expected: FAIL, `ImportError: cannot import name 'require_installation'`.

- [ ] **Step 3: Implementeren** volgens Interfaces.

- [ ] **Step 4: Draaien en zien slagen.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/insanely_fast_whisper_api/app/routes/support.py tests/test_support_relay.py
git commit -m "feat(support): check installation id and secret"
```

---

### Task 5: Hubclient

**Files:**
- Create: `APP/services/support_hub.py`
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: `settings` (taak 2), `raise_api_error` en de codes uit taak 3.
- Produces:
  - `HUB_TRANSPORT: httpx.AsyncBaseTransport | None = None` (tests zetten hier een `MockTransport`), `REQUEST_TIMEOUT = 10.0`.
  - `async def call_hub(method: str, path: str, installation_id: str, ticket_scoped: bool = False, **kwargs) -> dict`. Dit is `_call_hub` uit de spec, zonder underscore omdat de router hem importeert. URL `f"{settings.feedback_hub_url.rstrip('/')}/api/widget{path}"`, headers `x-instance-key` en `x-widget-user`, `**kwargs` gaat door naar `client.request` (`params`, `json`, `data`, `files`). Geeft de geparste JSON-body terug. Foutvertaling: `httpx.HTTPError` (ook `TimeoutException`) → 502 `hub_unavailable`; 401 → 502 `hub_unavailable`; 403 met `ticket_scoped` → 404 `not_found`; 429 → 429 `rate_limit_exceeded` met `retry_after` uit de hub-header `Retry-After`, standaard `"3600"`; elke andere status vanaf 400 → dezelfde status met `error_code` `"hub_error"` en de hubtekst uit `body["error"]` als `detail`. Overgenomen uit `ProspectFlow/app/routers/feedback.py` r.155-215, met `async with httpx.AsyncClient(transport=HUB_TRANSPORT, timeout=REQUEST_TIMEOUT)`.
  - `async def create_ticket(installation_id: str, form: dict[str, str]) -> dict`: multipart `POST /tickets` met `files=[(naam, (None, waarde)) for naam, waarde in form.items()]`, geeft `body["data"]`.
  - `async def get_ticket(installation_id: str, ticket_id: str) -> dict | None`: `GET /tickets/{id}`, `ticket_scoped=True`; een 404 (ook uit een vertaalde 403) geeft `None`.
  - `async def post_message(installation_id: str, ticket_id: str, body: str, log: str = "") -> dict`: met log multipart `data={"body": body}` en `files=[("attachments", ("thoughtvault-log.txt", log.encode("utf-8", "replace"), "text/plain"))]`; zonder log `json={"body": body}`. `ticket_scoped=True`.

httpx kiest alleen multipart als er `files` zijn; `(None, waarde)` is de httpx-vorm voor een formulierveld zonder bestand. De test hieronder controleert `Content-Type: multipart/form-data`.

- [ ] **Step 1: Falende tests schrijven**, met eerst de fixture `hub` uit taak 2 stap 5.

```python
async def test_call_hub_sends_instance_key_and_widget_user(hub):
    assert await call_hub("GET", "/unread-count", IID) == {"data": {"count": 3}}
    sent = hub.requests[-1]
    assert str(sent.url) == "http://hub.test/api/widget/unread-count"
    assert sent.headers["x-instance-key"] == "fh_test"
    assert sent.headers["x-widget-user"] == IID

@pytest.mark.parametrize("failure,status,error", [
    (httpx.Response(403, json={"error": "Je hebt geen toegang tot deze melding."}), 404, "not_found"),
    (httpx.Response(401, json={"error": "sleutel"}), 502, "hub_unavailable"),
    (httpx.ConnectError("refused"), 502, "hub_unavailable"),
    (httpx.ReadTimeout("slow"), 502, "hub_unavailable"),
    (httpx.Response(429, json={"error": "Te veel meldingen"}, headers={"Retry-After": "1200"}), 429, "rate_limit_exceeded"),
])
async def test_hub_failures_are_translated(hub, failure, status, error):
    hub.override[("GET", "/api/widget/tickets/t9/messages")] = failure
    with pytest.raises(APIError) as exc:
        await call_hub("GET", "/tickets/t9/messages", IID, ticket_scoped=True)
    assert exc.value.status_code == status and exc.value.detail["error_code"] == error

async def test_create_ticket_is_multipart_with_user_id_in_form(hub):
    data = await create_ticket(IID, {"category": "BUG", "description": "x", "userId": IID, "userName": "Test"})
    assert data["ref"] == "TV-000001"
    sent = hub.requests[-1]
    assert sent.headers["content-type"].startswith("multipart/form-data")
    assert b'name="userId"' in sent.content and IID.encode() in sent.content

async def test_post_message_attaches_log_as_text_file(hub):
    await post_message(IID, "t1", "Logbestand van dit apparaat", "regel 1\n")
    body = hub.requests[-1].content
    assert b'name="attachments"; filename="thoughtvault-log.txt"' in body
    assert b"Content-Type: text/plain" in body and b"regel 1\n" in body

async def test_post_message_replaces_unencodable_log_characters(hub):
    await post_message(IID, "t1", "Logbestand van dit apparaat", "ok \ud800 \x00 end")
    assert b"ok ? \x00 end" in hub.requests[-1].content

async def test_get_ticket_returns_none_for_deleted_ticket(hub):
    assert await get_ticket(IID, "t404") is None
```

- [ ] **Step 2: Draaien en zien falen**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v -k "hub or ticket or message"`
Expected: FAIL, `ModuleNotFoundError: ...services.support_hub`.

- [ ] **Step 3: Implementeren** volgens Interfaces. Log weigeringen zoals de referentie (warning bij 401/403/404, error bij andere statussen), zonder de body of het log in de regel.

- [ ] **Step 4: Draaien en zien slagen.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/insanely_fast_whisper_api/app/services/support_hub.py tests/test_support_relay.py
git commit -m "feat(support): add async feedback hub client"
```

---

### Task 6: `POST /reports`, nieuw ticket met logbestand

**Files:**
- Modify: `APP/routes/support.py`
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: `require_installation` (taak 4), `create_ticket`, `post_message` (taak 5), `installation_key`, `client_ip_key` (taak 3).
- Produces:
  - `MAX_REQUEST_BYTES = 1_572_864`
  - `async def read_limited(request: Request, limit: int) -> bytes`: 413 `payload_too_large` als `Content-Length` groter is dan `limit`; anders `request.stream()` lezen en bij overschrijding tijdens het lezen ook 413. Zo komt een te groot verzoek nooit helemaal in het geheugen.
  - `class ReportIn(BaseModel)` met aliassen in camelCase (`populate_by_name=True`): `kind: Literal["auto", "manual"]`; `category: Literal["BUG", "FEATURE_REQUEST", "QUESTION"]`; `stage: Literal["opnemen", "transcriberen", "notule", "crash", ""] = ""`; `shown_message: str` (min 1, max 5000, alias `shownMessage`); `error_text: str = ""` (max 2000); `fingerprint: str | None` (patroon `^[0-9a-f]{16,64}$`); `click_path: list[str] = []` (max 30 items van max 80 tekens); `app_version`, `os`, `device`, `platform`: `str`, max 100; `name: str` max 200; `email: str` max 320; `occurred_at: str` max 40; `log: str = ""` max 1 048 576 tekens. Een `model_validator(mode="after")`: bij `auto` moeten `category == "BUG"`, `stage` niet leeg en `fingerprint` gezet zijn; bij `manual` zijn `stage` leeg en `fingerprint` `None`.
  - `def ticket_form(report: ReportIn, installation_id: str, count: int) -> dict[str, str]`: `category`; `description` = bij `auto` `f"{shown_message}\n\nStap: {stage}\nFoutmelding: {error_text}"`, bij `manual` `shown_message`, afgekapt op 5000; `userId` = kenmerk; `userName` = `name`; `userEmail` = `email`; `releaseVersion` = `app_version`; `module` = `stage` (weglaten als leeg); `environment` = `"production"`; `browserInfo` = `f"ThoughtVault {platform} {app_version} / {os} / {device}"`; `diagnostics` = `json.dumps` van `{"stage", "errorText", "clickPath", "appVersion", "os", "device", "platform", "occurredAt", "count"}`.
  - `POST /reports` → `async def submit_report(request: Request, installation_id: str = Depends(require_installation)) -> dict`, gedecoreerd met `@limiter.limit("20/hour", key_func=installation_key)` en `@limiter.limit("60/hour", key_func=client_ip_key)`. Body via `read_limited` en `ReportIn.model_validate_json`; een `ValidationError` of ongeldige UTF-8 wordt 422 `validation_error`. Antwoord `{"ticketId": str, "ref": str, "repeated": bool, "count": int}`.

In deze taak alleen het pad zonder bestaande koppeling: `create_ticket` met `count=1`, bij `auto` direct daarna de `SupportIssue`-rij opslaan (`ticket_id`, `count=1`, `first_seen` en `last_seen` nu), en pas dan `post_message(..., "Logbestand van dit apparaat", report.log)`. Is `log` leeg, dan geen logbericht. Een fout in het logbericht gaat als foutstatus naar de app, maar de koppeling blijft staan.

Vaste testpayload `AUTO`: `{"kind": "auto", "category": "BUG", "stage": "transcriberen", "shownMessage": "Transcriberen is mislukt.", "errorText": "modelNotInstalled", "fingerprint": FP, "clickPath": ["Opnemen", "Stop"], "appVersion": "1.0.312", "os": "macOS 26.1", "device": "MacBookPro18,3", "platform": "macos", "name": "Test Gebruiker", "email": "test@example.com", "occurredAt": "2026-11-10T09:15:00Z", "log": "regel 1\n"}`. `MANUAL` is dezelfde payload met `kind` `manual`, `category` `QUESTION`, `stage` `""` en zonder `fingerprint`.

- [ ] **Step 1: Falende tests schrijven**

```python
async def test_auto_report_creates_ticket_then_log_message(client, hub):
    h = auth(*await registered(client))
    r = await client.post(REPORTS, json=AUTO, headers=h)
    assert r.status_code == 200
    assert r.json() == {"ticketId": "t1", "ref": "TV-000001", "repeated": False, "count": 1}
    create, message = hub.requests
    assert (create.method, create.url.path) == ("POST", "/api/widget/tickets")
    for part in (b"Transcriberen is mislukt.", b"Stap: transcriberen", b"Foutmelding: modelNotInstalled",
                 b"ThoughtVault macos 1.0.312 / macOS 26.1 / MacBookPro18,3", b'"count": 1', b"production"):
        assert part in create.content
    assert message.url.path == "/api/widget/tickets/t1/messages"
    assert b"Logbestand van dit apparaat" in message.content and b"thoughtvault-log.txt" in message.content

async def test_manual_reports_are_never_merged(client, hub):
    h = auth(*await registered(client))
    first, second = [(await client.post(REPORTS, json=MANUAL, headers=h)).json() for _ in range(2)]
    assert (first["ticketId"], second["ticketId"]) == ("t1", "t2") and not second["repeated"]

async def test_report_over_one_and_a_half_mb_is_413(client, hub):
    h = auth(*await registered(client))
    r = await client.post(REPORTS, json={**AUTO, "log": "x" * 1_600_000}, headers=h)
    assert r.status_code == 413 and code(r) == "payload_too_large" and hub.requests == []

@pytest.mark.parametrize("change", [
    {"fingerprint": None}, {"category": "QUESTION"}, {"fingerprint": "xyz"},
    {"clickPath": ["a"] * 31}, {"clickPath": ["a" * 81]}, {"errorText": "e" * 2001}, {"shownMessage": ""},
])
async def test_invalid_reports_are_422(client, hub, change):
    h = auth(*await registered(client))
    assert (await client.post(REPORTS, json={**AUTO, **change}, headers=h)).status_code == 422

async def test_invalid_utf8_body_is_422_not_500(client, hub):
    h = auth(*await registered(client))
    body = json.dumps(AUTO).encode().replace(b"regel 1", b"regel \xff")
    r = await client.post(REPORTS, content=body, headers={**h, "Content-Type": "application/json"})
    assert r.status_code == 422

async def test_report_without_identity_is_401(client, hub):
    assert (await client.post(REPORTS, json=AUTO)).status_code == 401

async def test_report_limit_is_twenty_per_hour_per_installation(client, hub):
    h = auth(*await registered(client))
    statuses = [(await client.post(REPORTS, json=MANUAL, headers=h)).status_code for _ in range(21)]
    assert statuses[:20] == [200] * 20 and statuses[20] == 429

async def test_report_limit_is_sixty_per_hour_per_ip(client, hub):
    heads = [auth(*await registered(client, ip=f"198.51.100.{n}")) for n in range(4)]
    ip = {"X-Forwarded-For": "203.0.113.50"}
    statuses = [(await client.post(REPORTS, json=MANUAL, headers={**heads[n % 4], **ip})).status_code for n in range(61)]
    assert statuses[:60] == [200] * 60 and statuses[60] == 429

async def test_log_timeout_after_ticket_keeps_link(client, hub):
    h = auth(*await registered(client))
    hub.override[("POST", "/api/widget/tickets/t1/messages")] = httpx.ReadTimeout("slow")
    assert (await client.post(REPORTS, json=AUTO, headers=h)).status_code == 502
    hub.override.clear()
    again = (await client.post(REPORTS, json=AUTO, headers=h)).json()
    assert again["ticketId"] == "t1" and again["repeated"] is True
    assert [q.url.path for q in hub.requests].count("/api/widget/tickets") == 1
```

`REPORTS = "/tstudio/api/support/reports"`. De laatste test slaagt pas na taak 7; markeer hem in deze taak met `@pytest.mark.xfail(strict=True, reason="dedup in task 7")` en haal de markering in taak 7 weg.

- [ ] **Step 2: Draaien en zien falen**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v -k "report or utf8 or timeout"`
Expected: FAIL met 404 op `/tstudio/api/support/reports`.

- [ ] **Step 3: Implementeren** volgens Interfaces.

- [ ] **Step 4: Draaien en zien slagen.** Expected: PASS, één XFAIL.

- [ ] **Step 5: Commit**

```bash
git add src/insanely_fast_whisper_api/app/routes/support.py tests/test_support_relay.py
git commit -m "feat(support): relay reports to the hub with log attachment"
```

---

### Task 7: Ontdubbelen van automatische meldingen

**Files:**
- Modify: `APP/routes/support.py`
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: `get_ticket`, `post_message` (taak 5), `submit_report` en `SupportIssue` (taak 2 en 6).
- Produces: geen nieuwe namen buiten de module. Intern `_issue_locks: dict[tuple[str, str], asyncio.Lock]` en `def _issue_lock(installation_id: str, fingerprint: str) -> asyncio.Lock`.

Algoritme voor `kind == "auto"`, binnen `async with _issue_lock(kenmerk, fingerprint)`:

```text
issue = SupportIssue(kenmerk, fingerprint) of None
if issue:
    ticket = await get_ticket(kenmerk, issue.ticket_id)
    if ticket and ticket["status"] not in ("RESOLVED", "CLOSED"):
        n = issue.count + 1
        await post_message(kenmerk, issue.ticket_id, f"Opnieuw opgetreden ({n} keer), laatste keer {report.occurred_at}", report.log)
        issue.count, issue.last_seen = n, nu        # pas na een geslaagd bericht
        return {"ticketId": issue.ticket_id, "ref": ticket["ref"], "repeated": True, "count": n}
# geen koppeling, of ticket gesloten, opgelost of verwijderd: pad uit taak 6, koppeling overschrijven met count 1
```

De teller gaat pas omhoog na een geslaagd vervolgbericht, zodat een 429 of 502 gevolgd door een nieuwe poging niet dubbel telt. Een 429 van de hub komt als 429 terug bij de app.

`# ponytail: in-process lock, klopt omdat uvicorn met --workers 1 draait (Dockerfile CMD, start.sh r.3); bij meer workers een rij-lock in de database.` De unieke sleutel op de tabel blijft het vangnet.

- [ ] **Step 1: Falende tests schrijven**

```python
async def test_second_identical_auto_report_is_follow_up_with_count_2(client, hub):
    h = auth(*await registered(client))
    await client.post(REPORTS, json=AUTO, headers=h)
    r = await client.post(REPORTS, json=AUTO, headers=h)
    assert r.json() == {"ticketId": "t1", "ref": "TV-000001", "repeated": True, "count": 2}
    follow_up = hub.requests[-1]
    assert follow_up.url.path == "/api/widget/tickets/t1/messages"
    assert b"Opnieuw opgetreden (2 keer), laatste keer 2026-11-10T09:15:00Z" in follow_up.content
    assert b"thoughtvault-log.txt" in follow_up.content
    assert [q.url.path for q in hub.requests].count("/api/widget/tickets") == 1

@pytest.mark.parametrize("status", ["RESOLVED", "CLOSED"])
async def test_resolved_or_closed_ticket_gets_new_ticket(client, hub, status):
    iid, secret = await registered(client)
    await client.post(REPORTS, json=AUTO, headers=auth(iid, secret))
    hub.tickets["t1"] = status
    r = (await client.post(REPORTS, json=AUTO, headers=auth(iid, secret))).json()
    assert r == {"ticketId": "t2", "ref": "TV-000002", "repeated": False, "count": 1}
    with get_db_session() as db:
        assert db.get(SupportIssue, (iid, FP)).ticket_id == "t2"

async def test_ticket_deleted_in_hub_gets_new_ticket(client, hub):
    h = auth(*await registered(client))
    await client.post(REPORTS, json=AUTO, headers=h)
    del hub.tickets["t1"]
    r = (await client.post(REPORTS, json=AUTO, headers=h)).json()
    assert (r["ticketId"], r["repeated"], r["count"]) == ("t2", False, 1)

async def test_hub_429_is_passed_on_and_nothing_is_stored(client, hub):
    iid, secret = await registered(client)
    hub.override[("POST", "/api/widget/tickets")] = httpx.Response(429, json={"error": "Te veel meldingen"})
    r = await client.post(REPORTS, json=AUTO, headers=auth(iid, secret))
    assert r.status_code == 429 and code(r) == "rate_limit_exceeded"
    with get_db_session() as db:
        assert db.get(SupportIssue, (iid, FP)) is None

async def test_failed_follow_up_does_not_raise_the_count(client, hub):
    h = auth(*await registered(client))
    await client.post(REPORTS, json=AUTO, headers=h)
    hub.override[("POST", "/api/widget/tickets/t1/messages")] = httpx.Response(429, json={"error": "Te veel berichten"})
    assert (await client.post(REPORTS, json=AUTO, headers=h)).status_code == 429
    hub.override.clear()
    assert (await client.post(REPORTS, json=AUTO, headers=h)).json()["count"] == 2

async def test_concurrent_identical_auto_reports_make_one_ticket(client, hub):
    h = auth(*await registered(client))
    hub.delay = 0.05
    first, second = await asyncio.gather(*(client.post(REPORTS, json=AUTO, headers=h) for _ in range(2)))
    assert sorted(r.json()["count"] for r in (first, second)) == [1, 2]
    assert [q.url.path for q in hub.requests].count("/api/widget/tickets") == 1

async def test_other_fingerprint_gets_its_own_ticket(client, hub):
    h = auth(*await registered(client))
    await client.post(REPORTS, json=AUTO, headers=h)
    r = (await client.post(REPORTS, json={**AUTO, "fingerprint": "b" * 16}, headers=h)).json()
    assert (r["ticketId"], r["repeated"]) == ("t2", False)
```

Haal de `xfail`-markering van `test_log_timeout_after_ticket_keeps_link` weg.

- [ ] **Step 2: Draaien en zien falen**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v -k "identical or closed or deleted or 429 or follow_up or fingerprint or timeout"`
Expected: FAIL, tweede melding geeft `"ticketId": "t2"` in plaats van een vervolgbericht.

- [ ] **Step 3: Implementeren** volgens het algoritme.

- [ ] **Step 4: Draaien en zien slagen.** Expected: PASS, geen XFAIL meer.

- [ ] **Step 5: Commit**

```bash
git add src/insanely_fast_whisper_api/app/routes/support.py tests/test_support_relay.py
git commit -m "feat(support): merge repeated auto reports into one ticket"
```

---

### Task 8: Leesroutes en antwoord sturen

**Files:**
- Modify: `APP/routes/support.py`
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: `call_hub` (taak 5), `require_installation` (taak 4), `installation_key` (taak 3).
- Produces:
  - `TicketId = Annotated[str, Path(pattern=r"^[A-Za-z0-9_-]{1,64}$")]` (het id gaat ongewijzigd het hubpad in; zelfde patroon als ProspectFlow r.53).
  - `class MessageIn(BaseModel)`: `body: str`, min 1, max 5000.
  - `GET /tickets` → hub `GET /tickets/mine` met `params={"limit": 50}`; `GET /unread-count` → hub `GET /unread-count`; `GET /tickets/{ticket_id}/messages` → hub idem, `ticket_scoped=True`; `POST /tickets/{ticket_id}/messages` → hub idem met `json={"body": ...}`, `ticket_scoped=True`. Alle vier geven de hubbody ongewijzigd terug en delen `@limiter.shared_limit("120/hour", scope="support-read", key_func=installation_key)`. Elke functie heeft `request: Request` en `installation_id: str = Depends(require_installation)`.

- [ ] **Step 1: Falende tests schrijven**

```python
async def test_ticket_list_asks_hub_for_mine_with_limit_50(client, hub):
    r = await client.get(f"{BASE}/tickets", headers=auth(*await registered(client)))
    assert r.status_code == 200 and r.json() == {"data": [], "pagination": {}}
    assert hub.requests[-1].url.path == "/api/widget/tickets/mine"
    assert hub.requests[-1].url.params["limit"] == "50"

async def test_unread_count_is_forwarded(client, hub):
    r = await client.get(f"{BASE}/unread-count", headers=auth(*await registered(client)))
    assert r.json() == {"data": {"count": 3}}

async def test_someone_elses_ticket_is_404(client, hub):
    h = auth(*await registered(client))
    for method in ("GET", "POST"):
        hub.override[(method, "/api/widget/tickets/t9/messages")] = httpx.Response(403, json={"error": "geen toegang"})
    assert (await client.get(f"{BASE}/tickets/t9/messages", headers=h)).status_code == 404
    assert (await client.post(f"{BASE}/tickets/t9/messages", json={"body": "Hallo"}, headers=h)).status_code == 404

async def test_reply_is_sent_as_json(client, hub):
    r = await client.post(f"{BASE}/tickets/t1/messages", json={"body": "Dank je"}, headers=auth(*await registered(client)))
    assert r.status_code == 200 and json.loads(hub.requests[-1].content) == {"body": "Dank je"}

@pytest.mark.parametrize("body", ["", "x" * 5001])
async def test_reply_length_is_checked(client, hub, body):
    h = auth(*await registered(client))
    assert (await client.post(f"{BASE}/tickets/t1/messages", json={"body": body}, headers=h)).status_code == 422

async def test_ticket_id_must_match_pattern(client, hub):
    assert (await client.get(f"{BASE}/tickets/a.b/messages", headers=auth(*await registered(client)))).status_code == 422

async def test_read_routes_share_120_per_hour(client, hub):
    h = auth(*await registered(client))
    paths = [f"{BASE}/tickets", f"{BASE}/unread-count", f"{BASE}/tickets/t1/messages"]
    statuses = [(await client.get(paths[n % 3], headers=h)).status_code for n in range(121)]
    assert statuses[:120] == [200] * 120 and statuses[120] == 429

async def test_read_routes_need_identity(client, hub):
    assert (await client.get(f"{BASE}/unread-count")).status_code == 401
```

`BASE = "/tstudio/api/support"`.

- [ ] **Step 2: Draaien en zien falen**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v -k "ticket_list or unread or someone or reply or pattern or read_routes"`
Expected: FAIL met 404 op de routes.

- [ ] **Step 3: Implementeren** volgens Interfaces.

- [ ] **Step 4: Draaien en zien slagen, en de regelgrens controleren**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py -v && wc -l src/insanely_fast_whisper_api/app/routes/support.py`
Expected: alles PASS, minder dan 300 regels.

- [ ] **Step 5: Commit**

```bash
git add src/insanely_fast_whisper_api/app/routes/support.py tests/test_support_relay.py
git commit -m "feat(support): forward ticket list, unread count and thread"
```

---

### Task 9: Registratie in `app.py` en `.env.example`

**Files:**
- Modify: `APP/app.py:981` en `APP/app.py:993`
- Modify: `.env.example` (nieuw blok achteraan)
- Test: `tests/test_support_relay.py`

**Interfaces:**
- Consumes: `router` uit `APP/routes/support.py`.
- Produces: `/tstudio/api/support/*` in de draaiende app.

- [ ] **Step 1: Falende tests schrijven** (bronbestanden lezen, zoals `tests/test_profile_choice.py` dat doet, omdat `app.py` niet te importeren is)

```python
def test_app_registers_support_router():
    source = (ROOT / "src/insanely_fast_whisper_api/app/app.py").read_text()
    assert "from .routes.support import router as support_router" in source
    assert "api_router.include_router(support_router)" in source
    assert source.index("api_router.include_router(support_router)") < source.index("app.include_router(api_router)")

def test_env_example_names_hub_settings():
    text = (ROOT / ".env.example").read_text()
    assert "FEEDBACK_HUB_URL=" in text and "FEEDBACK_HUB_INSTANCE_KEY=" in text
```

`ROOT = Path(__file__).resolve().parents[1]`.

- [ ] **Step 2: Draaien en zien falen.** Expected: FAIL op beide asserts.

- [ ] **Step 3: Implementeren**

Import na r.981, `include_router` na r.993, beide vóór `app.include_router(api_router)` (r.994). In `.env.example` een blok `# Feedback-hub (support-relay)` met `FEEDBACK_HUB_URL=https://feedback.yinga.ai` en `FEEDBACK_HUB_INSTANCE_KEY=` (leeg). Als taak 1 het interne adres koos, staat in het commentaar erboven dat de server `http://172.17.0.1:8085` gebruikt.

- [ ] **Step 4: Volledige lokale suite**

Run: `PYTHONPATH=src ~/.venvs/tstudio-support/bin/python -m pytest tests/test_support_relay.py tests/test_profile_choice.py tests/test_note_completion_validation.py -v`
Expected: PASS. Bewaar de uitvoer voor de review.

- [ ] **Step 5: Commit**

```bash
git add src/insanely_fast_whisper_api/app/app.py .env.example tests/test_support_relay.py
git commit -m "feat(support): register support router"
```

Daarna een review van de hele branch (superpowers:requesting-code-review) vóór taak 10.

---

### Task 10: Hub-tool aanmaken en sleutel plaatsen (akkoord van Michel)

**Files:** geen in een repo.

**Interfaces:**
- Consumes: de keuze voor `FEEDBACK_HUB_URL` uit taak 1.
- Produces: tool `thought-vault` met één instance, voorvoegsel `TV`, shadow uit; `FEEDBACK_HUB_URL` en `FEEDBACK_HUB_INSTANCE_KEY` in de server-`.env` van de backend.

- [ ] **Step 1: Beslispunt voorleggen** (vraag akkoord van Michel voor uitvoering)

Slug `thought-vault` (besluit van Michel, 10 november): de hub geeft dan zelf het voorvoegsel `TV`. Controleer na het aanmaken met `list_instances` dat `refPrefix` `TV` is; anders stoppen en melden.

- [ ] **Step 2: Controleren dat de tool nog niet bestaat** (vraag akkoord van Michel voor uitvoering)

MCP `list_tools` en `list_instances`. Verwacht: geen tool `thoughtvault` of `thought-vault`, geen instance met voorvoegsel `TV`. Bestaat er wel een: stoppen en melden.

- [ ] **Step 3: Aanmaken** (vraag akkoord van Michel voor uitvoering)

MCP `connect_tool` met `{"naam": "ThoughtVault", "eigenOpslag": false, "domain": "thoughtvault.yinga.ai", "nieuweTool": {"slug": "thought-vault", "name": "ThoughtVault"}}`. `eigenOpslag: false` zet shadow uit (`feedback-hub/backend/src/services/onboarding.ts` r.119-123).

De sleutel staat in het antwoord van `connect_tool` en komt daarmee in het sessieverslag. Herhaal hem nergens. Michel roteert de sleutel daarna zelf in het hubbeheer (`rotate-key` op de instance) en zet de nieuwe waarde zelf in de server-`.env`, samen met `FEEDBACK_HUB_URL`. Zo staat de werkende sleutel nooit in een verslag.

- [ ] **Step 4: Bewijs** (vraag akkoord van Michel voor uitvoering)

`list_instances`: de instance van ThoughtVault met `refPrefix` `TV`. Op de server, zonder de waarde te tonen: `grep -c '^FEEDBACK_HUB_INSTANCE_KEY=..*' <backend-dir>/.env` geeft `1`.

---

### Task 11: Backend deployen (akkoord van Michel)

**Files:** de zes gewijzigde of nieuwe bestanden onder `APP` uit taak 2 tot en met 9. `tests/` en `.env.example` gaan niet mee.

**Interfaces:**
- Consumes: branch `feat/support-relay` na review, de uitkomst van taak 1 stap 4 en 5, de sleutel uit taak 10.
- Produces: draaiende routes op `http://172.17.0.1:5678/tstudio/api/support/*` met `Host: n8n.prezent.nl`.

- [ ] **Step 1: Deploystappen lezen** uit `/Volumes/SSD/Projects/thoughtvault-native/docs/BACKEND.md` (buiten git) en de sectie Backend in het projectinstructiebestand in de root van de app-repo: bestanden syncen naar de bind-mount, daarna `docker restart n8n_transcript_studio`, geen rebuild.

- [ ] **Step 2: Backup** (vraag akkoord van Michel voor uitvoering)

Op de server een kopie van `app.py`, `config.py`, `database.py` en `errors.py` in een map `support-relay-backup-<YYYYMMDDHHMM>` naast de app-map. Zijn de hashes uit taak 1 stap 5 inmiddels veranderd: stoppen.

- [ ] **Step 3: Servercompose** (vraag akkoord van Michel voor uitvoering)

Alleen als taak 1 stap 4 geen `env_file: .env` vond: onder `environment:` `- FEEDBACK_HUB_URL=${FEEDBACK_HUB_URL}` en `- FEEDBACK_HUB_INSTANCE_KEY=${FEEDBACK_HUB_INSTANCE_KEY}` toevoegen, met kopie van het composebestand vooraf. Een compose-wijziging vraagt `docker compose up -d` in plaats van een restart.

- [ ] **Step 4: Bestanden syncen en herstarten** (vraag akkoord van Michel voor uitvoering), volgens BACKEND.md.

- [ ] **Step 5: Bewijs** (vraag akkoord van Michel voor uitvoering)

```bash
ssh michelk@3.69.205.209 "docker logs n8n_transcript_studio --since 5m 2>&1 | grep -E 'Database initialized|Traceback' | tail -5"
ssh michelk@3.69.205.209 "docker exec -i n8n_postgres psql -U n8n -d transcript_studio -c '\dt support_*'"
ssh michelk@3.69.205.209 "curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: n8n.prezent.nl' http://172.17.0.1:5678/tstudio/api/support/unread-count"
```

Verwacht: `Database initialized (PostgreSQL)` zonder traceback; twee tabellen `support_installations` en `support_issues`; status `401` (sleutel geladen, geen identiteit). Een `503` betekent dat de sleutel niet is geladen.

---

### Task 12: Caddy-route `@support` (akkoord van Michel)

**Files:**
- Modify (app-repo, eigen branch vanaf `origin/main`): `scripts/infra/thoughtvault-releases.caddy:2-9`
- Modify (n8n01): `/home/michelk/yinga/caddy/Caddyfile`, blok `thoughtvault.yinga.ai`

**Interfaces:**
- Consumes: taak 11 (routes draaien), het verschil uit taak 1 stap 1.
- Produces: `https://thoughtvault.yinga.ai/support/*` naar de container.

Het blok, direct onder het `@updater`-blok en boven de `handle`-terugval naar de website, in dezelfde vorm als r.3-9:

```caddy
    @support path /support/*
    handle @support {
        uri replace /support/ /tstudio/api/support/
        reverse_proxy 172.17.0.1:5678 {
            header_up Host n8n.prezent.nl
        }
    }
```

- [ ] **Step 1: Repobestand aanpassen en committen** in de app-repo, op een eigen branch vanaf `origin/main` (niet op de docs-branch): `git commit -m "chore(infra): route /support to the support relay"`.

- [ ] **Step 2: Backup, wijzigen, valideren, herladen** (vraag akkoord van Michel voor uitvoering)

Zoals `scripts/deploy-website.sh` r.44-57: kopie `Caddyfile.thoughtvault-<YYYYMMDDHHMMSS>` naast het live bestand, blok invoegen, dan

```bash
docker exec yinga-caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker exec yinga-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

Faalt `validate`: de kopie terugzetten en niet herladen.

- [ ] **Step 3: Bewijs**

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://thoughtvault.yinga.ai/support/unread-count
curl -sS -o /dev/null -w '%{http_code}\n' https://thoughtvault.yinga.ai/releases/macos/stable.xml
```

Verwacht: `401` voor de supportroute, `200` voor de bestaande updaterfeed.

---

### Task 13: End-to-end-bewijs (akkoord van Michel)

**Files:** een tijdelijke `report.json` in de scratchmap van de sessie, daarna verwijderen.

**Interfaces:**
- Consumes: taak 10, 11 en 12.
- Produces: het bewijs uit spec r.97.

- [ ] **Step 1: Aanmelden** (vraag akkoord van Michel voor uitvoering)

```bash
IID=$(python3 -c 'import uuid; print(uuid.uuid4())')
SECRET=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
curl -sS -w '\n%{http_code}\n' -H 'Content-Type: application/json' \
  -d "{\"installationId\":\"$IID\",\"secret\":\"$SECRET\"}" https://thoughtvault.yinga.ai/support/installations
```

Verwacht: `{"installationId":"<IID>"}` en `201`.

- [ ] **Step 2: IP-sleutel controleren**

`ssh michelk@3.69.205.209 "docker logs n8n_transcript_studio --since 5m 2>&1 | grep 'support: installation registered'"`. Verwacht: het publieke adres van deze Mac, niet een `172.`-adres. Staat er een intern adres, dan deelt iedereen de IP-limiet; melden aan Michel.

- [ ] **Step 3: Twee identieke automatische meldingen** (vraag akkoord van Michel voor uitvoering)

`report.json` = de payload `AUTO` uit taak 6 met `"name": "Michel Knoop"`, `"email": "info@michelknoop.nl"` (de hub stuurt de melder een bevestiging) en een log van een paar regels. Tweemaal:

```bash
curl -sS -H 'Content-Type: application/json' -H "X-TV-Installation: $IID" -H "X-TV-Secret: $SECRET" \
  --data-binary @report.json https://thoughtvault.yinga.ai/support/reports
```

Verwacht: eerst `{"ticketId":"<id>","ref":"TV-000001","repeated":false,"count":1}`, daarna hetzelfde id met `"repeated":true,"count":2`.

- [ ] **Step 4: In de hub controleren**

MCP `list_tickets` met `tool` = `thought-vault`: precies één ticket, `TV-000001`. MCP `get_ticket` op dat id: `diagnostics` met `"stage": "transcriberen"` en `"count": 1`, een bericht "Logbestand van dit apparaat" met bijlage `thoughtvault-log.txt`, en een bericht "Opnieuw opgetreden (2 keer), laatste keer 2026-11-10T09:15:00Z" met bijlage.

- [ ] **Step 5: Opruimen** (vraag akkoord van Michel voor uitvoering)

MCP `set_ticket_status` met `status` `CLOSED` op het testticket. `report.json` verwijderen. De testinstallatie blijft in `support_installations` staan; dat is één rij zonder hubgegevens.

- [ ] **Step 6: Vastleggen**

Uitvoer van stap 1 tot en met 5 (zonder geheim) als bewijs bij de oplevering van fase a. Fase b en c kunnen daarna starten.
