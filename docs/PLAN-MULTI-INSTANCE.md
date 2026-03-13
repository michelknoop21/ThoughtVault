# TranscriptStudio — Multi-Instance Deployment Plan

**Status:** Plan (nog niet geïmplementeerd)
**Datum:** 2026-03-13
**Doel:** Meerdere klanten bedienen met dezelfde codebase, elk met een eigen geïsoleerde backend-instantie.

---

## Inhoudsopgave

- [Waarom multi-instance](#waarom-multi-instance-niet-multi-tenant)
- [Waarom geen fork](#waarom-geen-fork)
- [Huidige architectuur](#huidige-architectuur-single-instance)
- [Doelarchitectuur](#doelarchitectuur-multi-instance)
- [Repo-structuur](#repo-structuur)
- [Implementatieplan](#implementatieplan)
  - [Fase 1: Deployment tooling](#fase-1-deployment-tooling-fundament)
  - [Fase 2: Backend aanpassingen](#fase-2-backend-aanpassingen)
  - [Fase 3: n8n flow](#fase-3-n8n-flow-gedeeld-niet-per-klant)
  - [Fase 4: Nginx](#fase-4-nginx-configuratie)
  - [Fase 5: Client aanpassingen](#fase-5-client-aanpassingen)
  - [Fase 6: Monitoring](#fase-6-monitoring--beheer)
- [Database provisioning](#database-provisioning-volledig-automatisch)
- [GPU & Whisper model](#gpu--whisper-model-gedeeld-geheugen)
- [File storage & isolatie](#file-storage--isolatie)
- [Klantmaatwerk](#klantmaatwerk-zonder-fork)
- [Beveiligingsoverwegingen](#beveiligingsoverwegingen)
- [Stappenplan](#stappenplan-volgorde-van-implementatie)
- [Kostenschatting](#kostenschatting-per-klant)
- [Toekomstige uitbreidingen](#toekomstige-uitbreidingen)

---

## Waarom multi-instance (niet multi-tenant)?

| Criterium | Multi-tenant (1 backend) | Multi-instance (N backends) |
|-----------|------------------------|-----------------------------|
| Codewijzigingen | 3-4 weken (org-laag door hele stack) | Minimaal (alleen deployment tooling) |
| Data-isolatie | Complex (RLS, org-scoped queries) | Gratis (aparte database per klant) |
| Security risico | Hoog (1 bug = data leak cross-tenant) | Laag (volledige isolatie) |
| Operationele overhead | Laag per klant | Medium per klant (mitigeren met tooling) |
| Schaalmoment | >10 klanten | 1-10 klanten |

**Conclusie:** Multi-instance is de juiste keuze voor de eerste 5-10 klanten. De operationele overhead mitigeren we met gestandaardiseerde deployment tooling.

---

## Waarom geen fork?

Elke klant draait **dezelfde codebase**. Een fork per klant zou betekenen:
- Bugfixes cherry-picken naar N repositories
- Divergerende code die steeds moeilijker te mergen is
- Onduidelijkheid over welke versie welke klant draait

**In plaats daarvan:** 1 backend repo → 1 Docker image → N containers met verschillende configuratie (env vars). Klantmaatwerk via feature flags, configuratie en webhooks — zie [Klantmaatwerk](#klantmaatwerk-zonder-fork).

---

## Huidige architectuur (single instance)

```
                    ┌─────────────────────────────────────────────┐
                    │  AWS EC2 GPU Instance (3.69.205.209)        │
                    │                                             │
  Clients ──────── │  nginx (/tstudio/api/) ──► transcript_studio │
                    │    │                        (FastAPI :5000)  │
                    │    │                             │           │
                    │    │                      ┌──────┴──────┐   │
                    │    │                      │  PostgreSQL  │   │
                    │    │                      │  Redis       │   │
                    │    │                      │  Whisper GPU │   │
                    │    │                      └──────────────┘   │
                    │    │                             │           │
                    │    │                        n8n flow         │
                    │    │                      (Ollama LLM)      │
                    │    │                             │           │
                    │    │◄────── callback ────────────┘           │
                    │    │                                         │
                    │    ├── /tstudio/download/ (static releases)  │
                    └─────────────────────────────────────────────┘
```

**Gedeelde resources (n8n-prezent stack):**
- `n8n_postgres` — PostgreSQL 15 (1 database, alle tabellen)
- `n8n_redis` — Redis (queue management)
- `n8n_nginx` — Reverse proxy
- Docker network: `n8n-prezent_n8n_internal`

**Per-klant specifiek (nu hardcoded):**
- Backend container: `n8n_transcript_studio`
- Database: alle tabellen in dezelfde DB
- n8n flow: 1 flow met vaste callback URL
- Whisper model: geladen in backend container (~3.2GB GPU geheugen voor "medium")
- Admin credentials en invite codes
- File storage: gedeeld volume `/app/data`

---

## Doelarchitectuur (multi-instance)

```
                    ┌──────────────────────────────────────────────────────┐
                    │  AWS EC2 GPU Instance                                │
                    │                                                      │
                    │  nginx                                               │
                    │    ├── /tstudio/api/         ──► tstudio_prezent     │
                    │    ├── /tstudio/download/         (FastAPI :5000)    │
                    │    │                                    │            │
                    │    ├── /klantx/api/          ──► tstudio_klantx     │
                    │    ├── /klantx/download/          (FastAPI :5001)    │
                    │    │                                    │            │
                    │    └── /klanty/api/          ──► tstudio_klanty     │
                    │         /klanty/download/         (FastAPI :5002)    │
                    │                                                      │
                    │  Gedeelde services:                                   │
                    │    ├── PostgreSQL (1 database per klant)             │
                    │    ├── Redis (1 DB-index per klant)                  │
                    │    ├── Ollama (gedeeld LLM endpoint)                │
                    │    └── whisper-server (gedeeld GPU model)           │
                    │                                                      │
                    │  n8n: 1 universele flow                              │
                    │    callback_url uit payload → juiste tenant backend  │
                    └──────────────────────────────────────────────────────┘
```

### Isolatie per klant

| Component | Strategie | Isolatie |
|-----------|-----------|---------|
| Docker container | Eigen container per klant | Volledig |
| PostgreSQL | Eigen database per klant (zelfde server) | Volledig |
| Redis | Eigen DB-index per klant (0, 1, 2, ...) | Volledig |
| File storage | Eigen Docker volume per klant | Volledig |
| Logs | Eigen log directory per volume | Volledig |
| n8n flow | Gedeeld — callback URL dynamisch uit payload | Logisch gescheiden |
| Whisper GPU | Gedeeld model, sequentieel per request | Gedeeld (zie [GPU sectie](#gpu--whisper-model-gedeeld-geheugen)) |
| Ollama LLM | Gedeeld endpoint | Gedeeld |
| Nginx | Eigen location block per klant | Volledig |
| SSL/TLS | Gedeeld certificaat (of per klant bij eigen domein) | N.v.t. |

---

## Repo-structuur

De tenant-tooling komt in een **aparte repository**, gescheiden van de applicatiecode:

```
Bestaand:
├── transcript-studio-native/      # Clients (macOS/Windows) — deze repo
├── transcript-studio-backend/     # Backend code (FastAPI)

Nieuw:
├── transcript-studio-ops/         # Deployment & tenant management
│   ├── tenants/                   #   Klant configs (.env bestanden)
│   │   ├── _template.env          #   Template voor nieuwe klanten
│   │   └── prezent.env            #   Eerste klant (retroactief)
│   ├── templates/                 #   Gegenereerde config templates
│   │   ├── docker-compose.yml.j2  #   Per-tenant Docker Compose
│   │   ├── nginx-location.conf.j2 #   Per-tenant nginx block
│   │   └── n8n-flow.json          #   Universele n8n flow
│   ├── scripts/
│   │   ├── manage-tenant.sh       #   Hoofd management script
│   │   ├── build-image.sh         #   Docker image bouwen & taggen
│   │   ├── update-all.sh          #   Alle tenants updaten naar nieuwe versie
│   │   └── backup-all.sh          #   Alle tenant databases backuppen
│   └── docker-compose.base.yml    #   Gedeelde services (postgres, redis, nginx)
```

**Waarom apart?**
- Backend-repo blijft puur applicatiecode — geen klantspecifieke config
- Ops-repo bevat credentials (env files met admin keys) — hoort niet in app repo
- Ops-repo kan private blijven, zelfs als app-code ooit gedeeld wordt
- Duidelijke scheiding: developers werken in backend/native, ops in ops

---

## Implementatieplan

### Fase 1: Deployment tooling (fundament)

**Doel:** Eén command om een nieuwe klant-instantie op te zetten.

#### 1.1 Klant-configuratiebestand

**`tenants/_template.env`:**
```bash
# === Klant identiteit ===
TENANT_ID=klant-slug               # URL-safe identifier (lowercase, geen spaties)
TENANT_NAME="Klantnaam B.V."       # Display naam

# === Netwerk ===
TENANT_PORT=5001                   # Unieke poort per klant (5000=prezent, 5001+)
TENANT_PATH_PREFIX=/klant          # URL prefix (zonder /api)
TENANT_DOMAIN=n8n.prezent.nl       # Kan per klant verschillen (eigen domein)

# === Database ===
TENANT_DB_NAME=tstudio_klant       # PostgreSQL database naam
# Hergebruikt gedeelde PG_USER/PG_PASSWORD uit base config

# === Redis ===
TENANT_REDIS_DB=1                  # Redis DB index (0=prezent, 1+)

# === Auth ===
TENANT_ADMIN_KEY=                  # Unieke admin API key (auto-generated bij create)
TENANT_ADMIN_EMAIL=admin@klant.nl  # Initieel admin account
TENANT_ADMIN_PASSWORD=             # Initieel admin wachtwoord (auto-generated bij create)

# === Whisper ===
TENANT_WHISPER_MODEL=medium        # small/medium/large — of "remote" voor shared service

# === n8n ===
TENANT_N8N_WEBHOOK_URL=            # n8n webhook URL (gedeelde flow)
TENANT_CALLBACK_HOST=n8n.prezent.nl
TENANT_CALLBACK_PROTOCOL=https

# === Notificaties ===
TENANT_NOTIFICATION_EMAIL=admin@klant.nl

# === Microsoft 365 (optioneel) ===
TENANT_MS365_CLIENT_ID=            # Klant's eigen Azure app registration
TENANT_MS365_TENANT_ID=            # Klant's Azure tenant

# === CORS ===
TENANT_CORS_ORIGINS=https://n8n.prezent.nl,https://tauri.localhost,http://localhost:1420

# === Feature flags (optioneel) ===
FEATURE_SSO_ENABLED=false
FEATURE_CUSTOM_LLM_ENDPOINT=      # Leeg = gebruik gedeelde Ollama

# === Branding (optioneel, voor toekomstig gebruik) ===
TENANT_APP_NAME="TranscriptStudio"
TENANT_ACCENT_COLOR="#007AFF"
```

#### 1.2 Docker Compose per klant (gegenereerd)

```yaml
# Auto-generated by: scripts/manage-tenant.sh
# Tenant: ${TENANT_ID} (${TENANT_NAME})
services:
  tstudio_${TENANT_ID}:
    image: tstudio-backend:latest
    container_name: tstudio_${TENANT_ID}
    restart: unless-stopped
    runtime: nvidia
    ports:
      - "${TENANT_PORT}:5000"
    volumes:
      - tstudio_data_${TENANT_ID}:/app/data    # EIGEN volume per klant
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
      - ADMIN_KEY=${TENANT_ADMIN_KEY}
      - DATABASE_URL=postgresql://${PG_USER}:${PG_PASSWORD}@n8n_postgres:5432/${TENANT_DB_NAME}
      - REDIS_URL=redis://:${REDIS_PASSWORD}@n8n_redis:6379/${TENANT_REDIS_DB}
      - CORS_ORIGINS=${TENANT_CORS_ORIGINS}
      - WHISPER_MODEL=${TENANT_WHISPER_MODEL}
      - API_ROOT_PATH=${TENANT_PATH_PREFIX}/api
      - CALLBACK_PATH_PREFIX=${TENANT_PATH_PREFIX}/api
      - TRANSCRIPT_HOST=${TENANT_CALLBACK_HOST}
      - TRANSCRIPT_PROTOCOL=${TENANT_CALLBACK_PROTOCOL}
      - N8N_NOTIFICATION_WEBHOOK_URL=${TENANT_N8N_WEBHOOK_URL}
      - NOTIFICATION_EMAIL=${TENANT_NOTIFICATION_EMAIL}
      - PYTHONUNBUFFERED=1
      - PYTHONPATH=/app
    networks:
      - n8n-prezent_n8n_internal
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  tstudio_data_${TENANT_ID}:

networks:
  n8n-prezent_n8n_internal:
    external: true
```

**Belangrijk:** Elk tenant volume (`tstudio_data_${TENANT_ID}`) is volledig geïsoleerd — audio uploads, logs, en eventuele SQLite fallback staan elk in hun eigen volume.

#### 1.3 Tenant management script

```bash
#!/bin/bash
# Usage:
#   ./scripts/manage-tenant.sh create klantx      # Nieuwe klant opzetten
#   ./scripts/manage-tenant.sh update klantx       # Config bijwerken & herstarten
#   ./scripts/manage-tenant.sh remove klantx       # Klant verwijderen (met bevestiging)
#   ./scripts/manage-tenant.sh list                # Alle klanten tonen
#   ./scripts/manage-tenant.sh status              # Status van alle containers
#   ./scripts/manage-tenant.sh logs klantx         # Logs bekijken
#   ./scripts/manage-tenant.sh backup klantx       # Database backup
#   ./scripts/manage-tenant.sh backup-all          # Alle databases backuppen
#   ./scripts/manage-tenant.sh update-all          # Alle containers naar nieuw image
```

**`create` actie doet (volledig geautomatiseerd):**
1. Kopieert `_template.env` → `tenants/{tenant}.env`
2. Genereert unieke `TENANT_ADMIN_KEY` via `openssl rand -hex 32`
3. Genereert initieel `TENANT_ADMIN_PASSWORD` via `openssl rand -base64 16`
4. Wijst volgende vrije poort toe (scan bestaande .env bestanden)
5. Wijst volgende vrije Redis DB index toe
6. Maakt PostgreSQL database aan: `CREATE DATABASE tstudio_{tenant}`
7. Start container → `Base.metadata.create_all()` maakt automatisch alle tabellen
8. Wacht tot container healthy is (health check endpoint)
9. Maakt admin user aan via API call: `POST /{tenant}/api/admin/users`
10. Configureert n8n webhook URL via API: `POST /{tenant}/api/admin/settings`
11. Genereert nginx location block → append naar tenant-includes config
12. Herlaadt nginx: `docker exec n8n_nginx nginx -s reload`
13. Maakt download directory aan: `/home/michelk/tstudio-releases-{tenant}/`
14. Print samenvatting: URL, admin credentials, test commands

---

### Fase 2: Backend aanpassingen

Alle aanpassingen zijn backward-compatible — de huidige Prezent-instantie blijft werken met standaard env vars.

#### 2.1 Docker image bouwen (i.p.v. bind-mount)

Huidige situatie: code is bind-mounted (`.:/app`), handig voor development maar niet schaalbaar.

**Aanpassing Dockerfile:**
```dockerfile
# Toevoegen aan bestaande Dockerfile:
COPY src/ /app/src/
COPY start.sh /app/
COPY requirements.txt /app/
```

**Build & deploy flow:**
```bash
# Bij elke backend release:
cd transcript-studio-backend
docker build -t tstudio-backend:latest -t tstudio-backend:1.0.50 .

# Op de server — alle tenants updaten:
./scripts/update-all.sh
# Intern: voor elke tenant → docker compose pull + up -d
```

#### 2.2 Configureerbaar pad-prefix

**In `app.py`:**
```python
# Huidig:
app = FastAPI(root_path="/tstudio/api")

# Nieuw:
ROOT_PATH = os.getenv("API_ROOT_PATH", "/tstudio/api")
app = FastAPI(root_path=ROOT_PATH)
```

#### 2.3 Callback URL per tenant

De n8n callback URL moet per tenant correct zijn. `TRANSCRIPT_HOST` en `TRANSCRIPT_PROTOCOL` zijn al configureerbaar, maar het pad moet ook mee.

**Toevoegen aan `config.py`:**
```python
CALLBACK_PATH_PREFIX: str = os.getenv("CALLBACK_PATH_PREFIX", "/tstudio/api")
```

**In `queue_manager.py` — webhook payload uitbreiden:**
```python
webhook_payload = {
    "task_id": task_id,
    "transcription": transcription,
    "system_prompt": system_prompt,
    "notule_prompt": notule_prompt,
    "output_template": output_template,
    "callback_url": f"{protocol}://{host}{config.CALLBACK_PATH_PREFIX}/callback/notule",
    "admin_key": config.ADMIN_KEY,    # n8n heeft dit nodig voor callback auth
    "user_email": user_email,
}
```

#### 2.4 Rate limiting keys

Rate limiting gebruikt al per-user tokens als key (niet IP), dus dit werkt correct cross-tenant. Geen aanpassing nodig, maar verifiëren bij implementatie.

---

### Fase 3: n8n flow (gedeeld, niet per klant)

#### 3.1 Waarom één gedeelde flow?

Aparte n8n flows per klant = onderhoudsnachtmerrie. Bij elke verbetering moet je N flows updaten. In plaats daarvan: **1 universele flow** die de callback URL dynamisch uit de webhook payload haalt.

#### 3.2 Aanpassingen aan de universele flow

**Huidige flow (`n8n/flow.json`):**
1. Webhook trigger → ontvangt task_id + transcriptie
2. LLM call → Ollama (ministral-3:8b)
3. Guardrail check → content safety
4. Callback → POST naar **hardcoded** `/tstudio/api/callback/notule`

**Nieuwe flow:**
1. Webhook trigger → ontvangt task_id + transcriptie + **callback_url** + **admin_key**
2. LLM call → Ollama (gedeeld) — of `{{ $json.custom_llm_endpoint }}` als klant eigen LLM heeft
3. Guardrail check → content safety
4. Callback → POST naar `{{ $json.callback_url }}` met header `X-Admin-API-Key: {{ $json.admin_key }}`

**Voordeel:** Eén flow, alle klanten. Nieuwe klant = geen n8n werk.

#### 3.3 Wanneer wél een aparte flow?

Alleen als een klant een **fundamenteel andere verwerkingspipeline** nodig heeft:
- Extra stappen (bijv. CRM-integratie, compliance check, vertaling)
- Compleet ander LLM model of provider (Azure OpenAI i.p.v. Ollama)
- Custom post-processing

Dit is niveau 3 maatwerk (zie [Klantmaatwerk](#klantmaatwerk-zonder-fork)). Het management script kan een flow klonen:
```bash
./scripts/manage-tenant.sh create-flow klantx --base-flow templates/n8n-flow.json
```

---

### Fase 4: Nginx configuratie

#### 4.1 Location blocks per klant

**Template (`templates/nginx-location.conf.j2`):**
```nginx
# Tenant: ${TENANT_ID} (${TENANT_NAME})
# Auto-generated — do not edit manually

# API proxy
location /${TENANT_ID}/api/ {
    proxy_pass http://tstudio_${TENANT_ID}:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # SSE support (voor real-time task status)
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 300s;

    # File upload limit (audio bestanden)
    client_max_body_size 500M;
}

# Static downloads (releases, update check)
location /${TENANT_ID}/download/ {
    alias /srv/tstudio-releases-${TENANT_ID}/;
    autoindex off;
    add_header Cache-Control "public, max-age=3600";
}
```

#### 4.2 Nginx include structuur

In de hoofd nginx config:
```nginx
# /etc/nginx/conf.d/default.conf
include /etc/nginx/tenant-includes/*.conf;
```

Elke tenant krijgt een bestand in `tenant-includes/`. Het management script voegt toe en herlaadt nginx.

#### 4.3 Eigen domein per klant (optioneel)

Als een klant een eigen domein wil (bijv. `notulen.klantx.nl`):
1. DNS: CNAME `notulen.klantx.nl` → `n8n.prezent.nl`
2. SSL: Certbot `--expand` om domein toe te voegen
3. Nginx: apart `server_name` block dat proxied naar dezelfde container
4. Client config: server URL wordt `https://notulen.klantx.nl` (geen prefix nodig)

---

### Fase 5: Client aanpassingen

#### 5.1 Configureerbare API prefix

Beide clients hebben al een configureerbare "Server URL" in Settings. Het path-prefix (`/tstudio`) is nu hardcoded en moet configureerbaar worden.

**macOS (`APIService.swift`) — huidig:**
```swift
private var baseURL: String {
    let server = UserDefaults.standard.string(forKey: "serverURL") ?? "https://n8n.prezent.nl"
    return "\(server)/tstudio/api"
}
```

**macOS — nieuw:**
```swift
private var baseURL: String {
    let server = UserDefaults.standard.string(forKey: "serverURL") ?? "https://n8n.prezent.nl"
    let prefix = UserDefaults.standard.string(forKey: "apiPrefix") ?? "/tstudio"
    return "\(server)\(prefix)/api"
}
```

**Windows (`api.ts`):** Zelfde aanpassing.

**Settings UI:** Eén extra veld "API prefix" in het instellingenscherm, met default `/tstudio`. Voor klanten met eigen domein kan dit leeg zijn.

#### 5.2 Update check URL

De update check is nu hardcoded naar `https://n8n.prezent.nl/tstudio/download/releases.json`.

**Aanpassing:** URL afleiden uit de geconfigureerde server + prefix:
```swift
// Huidig (hardcoded):
let url = "https://n8n.prezent.nl/tstudio/download/releases.json"

// Nieuw (afgeleid):
let url = "\(server)\(prefix)/download/releases.json"
```

Elke klant krijgt een eigen `releases.json` in hun download directory. Bij gedeelde builds (alle klanten dezelfde app versie) kan dit hetzelfde bestand zijn.

#### 5.3 Branded builds (toekomst, niet voor MVP)

Clients ondersteunen al build-time overrides:
- macOS: `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER` via build.sh
- Windows: `TAURI_CONFIG` override via tauri.conf.json

Dit maakt het mogelijk om per klant een eigen app-naam en icoon te bouwen, maar is niet nodig voor de eerste klanten.

---

### Fase 6: Monitoring & beheer

#### 6.1 Centraal status overzicht

```bash
./scripts/manage-tenant.sh status
# Output:
# TENANT        CONTAINER              STATUS    PORT   DB               UPTIME    GPU MEM
# prezent       tstudio_prezent        running   5000   tstudio_prezent   14d      3.2GB
# klantx        tstudio_klantx         running   5001   tstudio_klantx    3d      3.2GB
# klanty        tstudio_klanty         stopped   5002   tstudio_klanty    -        0MB
```

#### 6.2 Health check

Elke container exposeert `/health`:
```json
{
  "status": "ok",
  "timestamp": "2026-03-13T...",
  "model": "openai/whisper-medium",
  "device": "cuda"
}
```

Het management script kan periodiek alle tenants pingen:
```bash
./scripts/manage-tenant.sh health
# → Groen/rood per tenant
```

#### 6.3 Backup strategie

```bash
# Per-tenant database backup
./scripts/manage-tenant.sh backup klantx
# → pg_dump tstudio_klantx > backups/klantx-2026-03-13.sql.gz

# Alle tenants
./scripts/manage-tenant.sh backup-all
# → Loop over alle .env files, dump elke database

# Data volume backup (audio + logs)
./scripts/manage-tenant.sh backup-data klantx
# → tar van Docker volume
```

**Automatiseren:** Cron job voor dagelijkse backups van alle tenant databases.

#### 6.4 Logging

Logs zijn per container geïsoleerd (eigen Docker volume). Centraal bekijken:
```bash
# Eén tenant
./scripts/manage-tenant.sh logs klantx --tail 100

# Alle tenants tegelijk (voor debugging)
./scripts/manage-tenant.sh logs-all --tail 20
```

Database error logs (in `error_logs` tabel) zijn per tenant geïsoleerd door aparte databases.

---

## Database provisioning (volledig automatisch)

De backend gebruikt `Base.metadata.create_all()` bij startup. Dit betekent:

1. **`manage-tenant.sh create`** maakt een lege PostgreSQL database aan
2. **Container start** → SQLAlchemy detecteert lege database → maakt alle tabellen automatisch aan
3. **Default profielen** worden automatisch geseed (`seed_default_profiles()` in `profile_repo.py`)
4. **Admin user** wordt aangemaakt via API call na container startup

**Geen migratie-scripts nodig.** Het volledige schema wordt bij eerste boot aangemaakt:
- Users, Tasks, Notes, NoteVersions
- Profiles (+ 3 default profielen: zakelijk, informeel, technisch)
- UserSettings, Settings (admin config)
- InviteCodes, ErrorLog, ActivityLog, Feedback
- PasswordResetToken

**Bij schema updates** (nieuwe kolommen, tabellen): `create_all()` voegt nieuwe tabellen toe maar wijzigt bestaande niet. Voor destructieve schema changes moet een migratiescript geschreven worden dat op alle tenant databases gedraaid wordt:
```bash
./scripts/manage-tenant.sh migrate-all --script migrations/add_column_x.sql
```

---

## GPU & Whisper model (gedeeld geheugen)

### Het probleem

Elke backend container laadt het Whisper model in GPU geheugen bij startup:
- `small` model: ~1.5GB
- `medium` model: ~3.2GB
- `large` model: ~6.4GB

Bij N containers × 3.2GB (medium) op een 16GB GPU:
- 1 klant: 3.2GB ✅
- 3 klanten: 9.6GB ✅
- 5 klanten: 16GB ⚠️ vol

### Oplossingen (in volgorde van complexiteit)

**Optie A: Accepteren (1-3 klanten)**
Gewoon meerdere copies laden. Bij een T4 (16GB) past dit tot ~4 medium models. Transcriptie requests zijn kort (5-30 sec) en worden sequentieel verwerkt.

**Optie B: Kleiner model voor kleine klanten**
```bash
# Grote klant
TENANT_WHISPER_MODEL=medium  # 3.2GB

# Kleine klant
TENANT_WHISPER_MODEL=small   # 1.5GB
```

**Optie C: Whisper als gedeelde microservice (>3 klanten, aanbevolen)**
Eén Whisper container, alle backends sturen audio daar naartoe:

```
tenant backends ──HTTP POST──► whisper-server (1x GPU, 1x model) ──► terug
```

Backend aanpassing:
```python
# Nieuw env var:
WHISPER_MODE = os.getenv("WHISPER_MODE", "local")  # "local" of "remote"
WHISPER_API_URL = os.getenv("WHISPER_API_URL", "")  # bv. http://whisper-server:8001

# In transcription route:
if config.WHISPER_MODE == "remote":
    result = await httpx.post(config.WHISPER_API_URL + "/transcribe", files={"audio": file})
else:
    result = local_whisper_model.transcribe(file)
```

Dit is de meest schaalbare oplossing en bespaart ~3.2GB GPU geheugen per extra klant.

---

## File storage & isolatie

### Huidige situatie

- Audio uploads: tijdelijk in `/tmp/whisper_uploads/`, daarna verwerkt
- Persistente data: `/app/data/` (database, logs, eventuele exports)
- Volume: `n8n_transcript_data:/app/data` (gedeeld, extern)

### Multi-instance aanpak

**Elk tenant container krijgt een eigen Docker volume:**
```yaml
volumes:
  - tstudio_data_${TENANT_ID}:/app/data
```

Dit isoleert automatisch:
- `/app/data/logs/` — log bestanden
- `/app/data/tasks.db` — SQLite fallback (als PostgreSQL niet beschikbaar)
- `/tmp/whisper_uploads/` — tijdelijke audio (container-lokaal, niet persistent)

**Geen code-aanpassingen nodig** — de paden zijn al relatief aan `/app/data/`.

---

## Klantmaatwerk (zonder fork)

### Niveau 1: Configuratie (90% van de gevallen)

Puur via env vars en database-instellingen. Geen codewijzigingen.

| Maatwerk | Hoe | Voorbeeld |
|----------|-----|-----------|
| Andere taal | Env var | `WHISPER_LANGUAGE=en` |
| Ander Whisper model | Env var | `WHISPER_MODEL=large` |
| Uploadlimiet | Env var | `MAX_UPLOAD_SIZE=1000M` |
| Eigen prompts/profielen | Database (via admin API) | Custom systeem-prompts |
| Eigen MS365 integratie | Database + env vars | Klant's Azure app registration |
| Notificatie-email | Env var | `NOTIFICATION_EMAIL=admin@klant.nl` |

### Niveau 2: Feature flags (8% van de gevallen)

Features die niet elke klant heeft. Code zit in dezelfde backend, achter een `if`.

```bash
# In tenant .env:
FEATURE_SSO_ENABLED=true
FEATURE_SSO_PROVIDER=azure-ad
FEATURE_CUSTOM_LLM_ENDPOINT=https://klant.openai.azure.com
FEATURE_EXPORT_FORMATS=html,docx,pdf,xlsx
```

```python
# In backend code:
if settings.FEATURE_SSO_ENABLED:
    app.include_router(sso_router)
```

Alle klanten draaien dezelfde image — alleen klanten met de flag zien de feature.

### Niveau 3: Webhooks & custom pipelines (2% van de gevallen)

Klant wil eigen logica (CRM integratie, compliance check, vertaling).

**Optie A: Webhooks**
```bash
HOOK_POST_NOTULE=https://klant.nl/api/webhook/notule-ready
HOOK_POST_TRANSCRIPTION=https://klant.nl/api/webhook/transcript-ready
```

Backend stuurt POST naar de webhook na voltooiing. Klant bouwt eigen ontvanger.

**Optie B: Eigen n8n flow**
Kloon de universele flow, voeg extra stappen toe. n8n is hiervoor gemaakt.

**Optie C: Plugin directory (toekomst)**
```python
# Laad tenant-specifieke post-processing
if os.path.exists(f"/plugins/{tenant_id}/pipeline.py"):
    plugin = importlib.import_module(f"plugins.{tenant_id}.pipeline")
    result = plugin.process(notule_html)
```

### Wanneer is het een apart product?

Als >30% van de code anders moet zijn. Dan is het geen variant meer maar een nieuw product. Dit komt in de praktijk bijna nooit voor.

---

## Beveiligingsoverwegingen

### Data-isolatie

| Risico | Mitigatie |
|--------|----------|
| Cross-tenant data access | Aparte database per klant (niet dezelfde DB met tenant_id filtering) |
| Gedeelde Redis keys | Aparte Redis DB index per klant |
| File system cross-access | Aparte Docker volumes per klant |
| Log leakage | Logs in eigen volume, niet gedeeld |

### Auth-isolatie

| Risico | Mitigatie |
|--------|----------|
| Token geldig bij andere tenant | Tokens zitten in aparte databases — cross-tenant auth is onmogelijk |
| Admin API key hergebruik | Unieke `ADMIN_KEY` per tenant (auto-generated) |
| n8n callback spoofing | Elke tenant heeft eigen admin key, n8n stuurt de juiste key mee |

### Netwerk-isolatie

| Risico | Mitigatie |
|--------|----------|
| Container-to-container access | Alle containers op zelfde Docker network — acceptabel risico bij vertrouwde workloads |
| Port scanning | Tenant ports niet extern exposed (alleen via nginx reverse proxy) |

### CSRF

De backend heeft CSRF middleware die `Origin`/`Referer` headers valideert. Per-tenant CORS config (`CORS_ORIGINS` env var) voorkomt cross-origin requests van andere tenant domeinen.

---

## Stappenplan (volgorde van implementatie)

### Stap 1 — Backend voorbereiden (1-2 dagen)
- [ ] Configureerbaar `API_ROOT_PATH` env var in `app.py`
- [ ] Configureerbaar `CALLBACK_PATH_PREFIX` in `config.py` + `queue_manager.py`
- [ ] Callback URL + admin key meesturen in webhook payload naar n8n
- [ ] Optioneel: `WHISPER_MODE=remote` + `WHISPER_API_URL` voor gedeelde Whisper service
- [ ] Dockerfile aanpassen: code COPY i.p.v. bind-mount
- [ ] Docker image build & tag flow opzetten
- [ ] Verifiëren: huidige Prezent-instantie blijft werken met standaard env vars

### Stap 2 — n8n flow aanpassen (halve dag)
- [ ] Callback URL dynamisch maken (`{{ $json.callback_url }}`)
- [ ] Admin key dynamisch maken (`{{ $json.admin_key }}`)
- [ ] Optioneel: LLM endpoint dynamisch (`{{ $json.custom_llm_endpoint || default_ollama }}`)
- [ ] Testen met huidige Prezent-instantie

### Stap 3 — Ops repo & tenant tooling bouwen (1-2 dagen)
- [ ] `transcript-studio-ops/` repo aanmaken
- [ ] `tenants/_template.env` met alle configuratie-opties
- [ ] `tenants/prezent.env` voor huidige klant (retroactief)
- [ ] `manage-tenant.sh` script: create, update, remove, list, status, logs, backup, health
- [ ] Docker Compose template (per-tenant)
- [ ] Nginx location block template
- [ ] `update-all.sh` — alle tenants naar nieuw Docker image
- [ ] `backup-all.sh` — alle databases backuppen

### Stap 4 — Client aanpassen (halve dag)
- [ ] macOS: configureerbaar API path-prefix in Settings + APIService.swift
- [ ] Windows: idem in api.ts + Settings page
- [ ] Update check URL afleiden uit server + prefix (niet hardcoded)
- [ ] Download URL afleiden uit server + prefix

### Stap 5 — Migratie huidige setup (halve dag)
- [ ] Huidige Prezent-instantie omzetten naar tenant-model
- [ ] `prezent.env` vullen met huidige waarden
- [ ] Docker Compose genereren voor Prezent tenant
- [ ] Bind-mount vervangen door Docker image
- [ ] Nginx config migreren naar include-structuur
- [ ] End-to-end test: opname → transcriptie → notulen → export

### Stap 6 — Eerste nieuwe klant onboarden (test)
- [ ] `manage-tenant.sh create testklant` draaien
- [ ] Verifiëren: eigen database met alle tabellen + default profielen
- [ ] Verifiëren: eigen container op eigen poort
- [ ] Verifiëren: eigen nginx route
- [ ] Verifiëren: eigen Docker volume (file isolatie)
- [ ] Client configureren met nieuwe URL + prefix
- [ ] End-to-end test: registratie → opname → transcriptie → notulen
- [ ] Verifiëren: Prezent data niet zichtbaar vanuit testklant

---

## Kostenschatting per klant

| Resource | Impact | Kosten |
|----------|--------|--------|
| Docker container | ~500MB RAM idle, ~2GB bij transcriptie | Marginaal op huidige EC2 |
| PostgreSQL database | ~100MB per 1000 transcripties | Marginaal |
| Redis DB index | <1MB | Verwaarloosbaar |
| Disk (audio + data volume) | ~1GB per 100 uur audio | ~€0.10/maand (EBS) |
| GPU geheugen (Whisper model) | 3.2GB per container (medium) | Bottleneck bij >4 klanten |
| n8n | 1 gedeelde flow | Geen extra kosten |
| Nginx | 1 location block | Verwaarloosbaar |
| **Totaal extra per klant** | | **~€5-10/maand** |

### GPU bottleneck-grenzen

| Klanten | GPU geheugen (medium model) | Status |
|---------|----------------------------|--------|
| 1 | 3.2GB / 16GB | Ruim |
| 3 | 9.6GB / 16GB | OK |
| 4 | 12.8GB / 16GB | Krap |
| 5+ | >16GB | Gedeelde Whisper service nodig |

---

## Toekomstige uitbreidingen

### Whisper als shared microservice (bij >3 klanten)
Eén GPU container met het Whisper model, alle tenant backends sturen audio via HTTP. Bespaart ~3.2GB GPU geheugen per extra klant.

### Private Docker registry (bij >3 klanten)
```bash
docker push registry.prezent.nl/tstudio-backend:1.0.50
# Alle tenants pullen automatisch bij update
```

### Email notificaties
Huidige situatie: password reset codes worden gelogd, niet gemaild. Implementeer SMTP of n8n-based email per tenant.

### Automated provisioning dashboard
Web UI voor tenant management (in plaats van CLI). Nuttig bij >5 klanten.

### Terraform/Pulumi (bij >10 klanten)
Infrastructure-as-code voor volledige automatisering van provisioning.

### Echte multi-tenancy (bij >20 klanten)
Overweeg alsnog de org-laag in de backend te bouwen om operationele overhead te verlagen. Op dat punt is de operationele kost van N containers hoger dan de eenmalige development kost van een multi-tenant refactor.
