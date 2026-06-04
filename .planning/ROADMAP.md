# Roadmap: People & Attribution (v1.1)

## Overview

Vier opeenvolgende fasen die persoons-/rolcontext toevoegen aan TranscriptStudio: eerst het datamodel + zelf-profilering, dan de mensen-directory met agenda-seed, daarna context-injectie in de notule-generatie (lokaal + cloud), en tot slot detectie + bewerkbare toewijzing van actiepunt-eigenaars. Elke fase is een harde afhankelijkheid voor de volgende. Cross-platform (macOS Swift 6 + Windows Tauri 2), privacy-bewust on-device.

## Already Shipped / Context

> **"Parity & Polish" (v1.0.134) staat on hold** — Phase 1 (quick-fixes) geshipt; Phase 2 (UX-review macOS-deel) klaar maar niet afgerond. Volledig bewaard in `.planning/paused/parity-and-polish/RESUME.md`. De huidige milestone People & Attribution werkt hier los van.

## Milestones

- 🚧 **v1.1 People & Attribution** — Phases 1–4 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): geplande milestone-werk
- Decimale fasen (bijv. 2.1): urgente tussenvoegingen (gemarkeerd INSERTED)

- [ ] **Phase 1: Self-Profile Foundation** - `PersonProfile`-datamodel + versioned SwiftData-migratie + onboarding-stap + Settings-bewerkscherm (macOS + Windows)
- [ ] **Phase 2: People Directory** - Lokale directory-CRUD + agenda-deelnemer-seed (macOS + Windows)
- [ ] **Phase 3: Context Injection** - `{{PEOPLE_CONTEXT}}`-injectie in lokaal LLM-pad + cloud n8n-pad + regenerate-pad (SPIKE REQUIRED)
- [ ] **Phase 4: Attribution Mapping** - Post-generatie persoons-detectie + bewerkbare eigenaar-toewijzing in beide viewers (SPIKE REQUIRED)

## Phase Details

### Phase 1: Self-Profile Foundation
**Goal**: De gebruiker kan zichzelf bij eerste gebruik voorstellen via een kort overslaanbaar stappenplan; het zelf-profiel wordt on-device opgeslagen in een stabiel `PersonProfile`-datamodel met versioned migratie zodat bestaande transcript-data nooit verloren gaat.
**Depends on**: Nothing (first phase)
**Requirements**: A-01, A-02, A-03, A-04
**Success Criteria** (what must be TRUE):
  1. Een nieuwe installatie toont het zelf-profileringsscherm tijdens onboarding; de gebruiker kan het overslaan zonder verlies van functionaliteit.
  2. Een ingevuld profiel (naam, rol, organisatie, aliassen, meeting-types) is na app-herstart nog aanwezig op zowel macOS als Windows.
  3. De gebruiker kan het profiel later openen en bewerken via Settings op beide platforms.
  4. Een app-upgrade op een apparaat met bestaande transcripts laat alle transcripts intact — geen data-wipe, geen crash.
  5. `grep -r "PersonProfile"` toont geen naambotsing met het bestaande `Profile`-type (notule-stijl); collision-warning aanwezig in `Models.swift`.
**Plans**: TBD
**UI hint**: yes

### Phase 2: People Directory
**Goal**: De gebruiker beschikt over een lokale directory van collega's en bekende externen die hij handmatig kan beheren en (semi-)automatisch kan aanvullen vanuit agenda-deelnemers.
**Depends on**: Phase 1
**Requirements**: B-01, B-02, B-03
**Success Criteria** (what must be TRUE):
  1. De gebruiker kan een persoon toevoegen (naam, aliassen, rol, intern/extern/onbekend, organisatie), bewerken en verwijderen via de directory-UI op macOS én Windows.
  2. Na een vergadering met agenda-deelnemers verschijnt een prompt "Voeg deelnemers toe aan directory?" — de gebruiker bevestigt handmatig per persoon (geen auto-commit).
  3. Nieuw toegevoegde personen via agenda-seed krijgen standaard `intern/extern = onbekend`; de gebruiker kan dit corrigeren.
  4. `PersonDirectoryService` bevat geen `URLSession`-referenties — persoonsdata blijft on-device (verifieerbaar via grep).
**Plans**: TBD
**UI hint**: yes

### Phase 3: Context Injection
**Goal**: Bij elke notule-generatie (lokaal én cloud, inclusief het aparte regenerate-pad) ontvangt de LLM een begrensd, gesanitiseerd blok mensen-context zodat actiepunt-eigenaars op basis van bekende namen worden geresolved.

> **SPIKE REQUIRED vóór planning:**
> - Inspecteer n8n workflow `Iq3AAf8Vk8eQ9dcZ` in de n8n UI — breng alle node-posities in kaart vóór code-aanpassingen.
> - Enumereer alle vier backend-payload-locaties (`transcription_service.py`, `transcription.py` ×2, `transcripts.py`) + bevestig of het `handleiding` Claude-proxy pad (DEC-057) via dezelfde of een afwijkende payload-buildcode loopt.
> - Bevestig de aparte `regenerateNotule`-endpoint (`APIService.swift:656`) — dit pad is het meest over het hoofd gezien.
> - Alle vier locaties in één commit aanpassen om partiële deployment te voorkomen.

**Depends on**: Phase 2
**Requirements**: C-01, C-02, C-03, C-04
**Success Criteria** (what must be TRUE):
  1. Een lokaal gegenereerde notule bevat actiepunt-eigenaars die overeenkomen met bekende namen uit de directory (aantoonbaar verschil t.o.v. geen context).
  2. Een cloud-gegenereerde notule ontvangt `people_context` in de n8n-workflow — zichtbaar in n8n execution-log.
  3. Het `regenerateNotule`-pad (cloud) levert dezelfde context mee als het primaire generatie-pad.
  4. Prompt-injectie is geblokkeerd: namen/aliassen met newlines of `{{...}}`-sequenties worden gesanitiseerd; context staat gewrapped in `<people_context>...</people_context>`.
  5. Notule-profielen zonder `{{PEOPLE_CONTEXT}}`-placeholder blijven werken (fallback-prepend, geen crash).
**Plans**: TBD

### Phase 4: Attribution Mapping
**Goal**: Na notule-generatie worden genoemde personen gedetecteerd en gekoppeld aan directory-entries; de gebruiker ziet per actiepunt een eigenaar-chip die hij met één klik kan bevestigen of wijzigen, consistent in beide notule-viewers.

> **SPIKE REQUIRED vóór planning:**
> - Inspecteer 3–5 echte notule-HTML-outputs om de tag/class-structuur van actiepunten te bevestigen vóór `AttributionMapper` wordt geschreven.
> - Verificeer de actuele staat van FND-008 (twee-viewer-divergentie): is dit deels of volledig open na Parity & Polish Phase 1?
> - Leg het cross-platform `AttributionEntry` JSON-schema vast in `.planning/` vóór Windows-implementatie start.
> - Beslissing vastzetten: `attributionsData: Data?` (macOS) vs `attributionJson: String?` — aanbeveling is `attributionsData: Data?` met computed `attributions: [AttributionEntry]`.

**Depends on**: Phase 3
**Requirements**: D-01, D-02, D-03, D-04
**Success Criteria** (what must be TRUE):
  1. Na het genereren van een notule worden actiepunten getoond met een eigenaar-chip; herkende personen zijn automatisch gekoppeld aan een directory-entry.
  2. De gebruiker kan per actiepunt de eigenaar wijzigen via een persoon-picker (één klik) en de keuze wordt persistent opgeslagen.
  3. Een toewijzing gemaakt in `NotuleResultView` is na sluiten en heropenen vanuit de geschiedenis zichtbaar in `TranscriptDetailView` — identiek.
  4. De toewijzing is na app-herstart nog aanwezig (persistent in `TranscriptRecord`/Windows-equivalent).
  5. `AttributionEditorView`/`AttributionEditor.tsx` is één gedeelde component — geen duplicaat code per viewer (lost FND-008 op).
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution order:** 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Self-Profile Foundation | 0/? | Not started | - |
| 2. People Directory | 0/? | Not started | - |
| 3. Context Injection | 0/? | Not started | - |
| 4. Attribution Mapping | 0/? | Not started | - |

## Coverage Validation

All 15 v1.1 requirements mapped. No orphans.

| Requirement | Description | Phase |
|-------------|-------------|-------|
| A-01 | Onboarding-stappenplan zelf-profilering | Phase 1 |
| A-02 | `PersonProfile` lokaal on-device (macOS + Windows) | Phase 1 |
| A-03 | Profiel bewerkbaar via Settings | Phase 1 |
| A-04 | Versioned SwiftData-migratie; geen data-wipe bij upgrade | Phase 1 |
| B-01 | Directory: personen vastleggen met velden | Phase 2 |
| B-02 | Directory-beheer-UI toevoegen/bewerken/verwijderen | Phase 2 |
| B-03 | Semi-automatische aanvulling uit agenda-deelnemers | Phase 2 |
| C-01 | `{{PEOPLE_CONTEXT}}` injectie lokaal + cloud + regenerate | Phase 3 |
| C-02 | Begrensde context (deelnemer-gericht, max) | Phase 3 |
| C-03 | Sanitisatie vóór prompt-injectie | Phase 3 |
| C-04 | Prompt instrueert LLM op eigenaar-matching + intern/extern | Phase 3 |
| D-01 | Post-generatie persoons-detectie + koppeling directory | Phase 4 |
| D-02 | Bewerkbare eigenaar-toewijzing via persoon-picker | Phase 4 |
| D-03 | Persistente attributie in `TranscriptRecord` + Windows | Phase 4 |
| D-04 | Consistente toewijzing in beide viewers (FND-008 oplossen) | Phase 4 |

**Coverage: 15/15 ✓**
