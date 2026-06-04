# Roadmap: TranscriptStudio — Parity & Polish

## Overview

Starting from v1.0.134, this milestone closes the macOS ↔ Windows asymmetry on three fronts: (1) quick wins — known bugs and cross-platform parity-fixes that unblock everything else; (2) a UX-review pass that produces a prioritised fix list to drive UI work; (3) full Windows local-first capability (STT + LLM + local storage + auth-bypass + settings UI); and (4) executing the UX fix list across both platforms. The milestone ends when both desktop platforms run fully offline and are UX-consistent.

## Phases

- [x] **Phase 1: Quick Fixes** - Known bugs + critical parity-fixes (Windows SSE, HTTPS, offline-queue, audio-mix, timer-threading)
- [ ] **Phase 2: UX Review** - Heuristische review van beide platforms → geprioriteerde bevindingenlijst
- [ ] **Phase 3: Windows Local-First** - Volledig offline pad op Windows (STT + LLM + opslag + auth-bypass + instellingen + video-call detectie)
- [ ] **Phase 4: UX Fixes** - Uitvoeren geprioriteerde UX-fixes, consistentie, toegankelijkheid op beide platforms

## Phase Details

### Phase 1: Quick Fixes

**Goal**: Gedocumenteerde bugs zijn verholpen en kritieke parity-gaps gedicht voordat de grotere Windows local-first sprint begint
**Depends on**: Nothing (brownfield — existing codebase v1.0.134)
**Requirements**: C-01, C-02, C-03, D-01, D-02
**Success Criteria** (what must be TRUE):

  1. Windows-opname die een netwerk-hik overleeft toont voortgang opnieuw (geen onterechte "failed" status)
  2. Windows accepteert geen custom server-URL met `http://` — validatie identiek aan macOS
  3. macOS offline-queue verwijdert/herkent items correct na een Swift-versie-update (id-gebaseerd, geen JSON-vergelijking); retry-limiet is gelijk op beide platforms
  4. macOS gecombineerde opname (mic + systeemgeluid) levert het maximale volume van beide bronnen, niet het gemiddelde
  5. macOS `SystemAudioCapture` timer gebruikt `MainActor.assumeIsolated` — geen Swift 6 concurrency-waarschuwingen tijdens opname

**Plans**: 3 plans (2 waves)

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Windows SSE-reconnect met exponential backoff (`sse.ts` + `http.rs`) [C-01]
- [x] 01-02-PLAN.md — Windows HTTPS-afdwinging (`api.ts`) + macOS offline-queue id-identiteit + retry-limiet alignment [C-02, C-03]

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 01-03-PLAN.md — macOS audio-mix fix (element-wise max) + SystemAudioCapture timer-threading fix [D-01, D-02]

### Phase 2: UX Review

**Goal**: Een gedocumenteerde, geprioriteerde lijst van UX-gaps en inconsistenties op macOS en Windows die Phase 4 aanstuurt
**Depends on**: Phase 1
**Requirements**: B-01
**Success Criteria** (what must be TRUE):

  1. Alle kernflows op macOS zijn doorlopen (opname start/stop, transcript-lijst, notule-weergave, instellingen, auth) en bevindingen zijn vastgelegd
  2. Alle kernflows op Windows zijn doorlopen (zelfde set) en bevindingen zijn vastgelegd
  3. Bevindingenlijst is geprioriteerd (P1/P2/P3) en klaar als input voor Phase 4
  4. Inconsistenties tussen macOS en Windows in terminologie, lege/laad/foutstaten en navigatie zijn geidentificeerd

**Plans**: TBD (verwacht 2 plans)
**UI hint**: yes

Plans:

- [ ] 02-01: UX-review macOS kernflows — bevindingen vastleggen
- [ ] 02-02: UX-review Windows kernflows — bevindingen vastleggen en crossreferentie prioritering

### Phase 3: Windows Local-First

**Goal**: Windows draait volledig cloud-onafhankelijk — lokale STT, lokale LLM-notulen, lokale opslag, auth-bypass in local-mode, instellingen-UI en video-call detectie
**Depends on**: Phase 1
**Requirements**: A-01, A-02, A-03, A-04, A-05, C-04
**Success Criteria** (what must be TRUE):

  1. Gebruiker kan op Windows een opname transcriberen zonder internet — whisper.cpp verwerkt audio lokaal, resultaat verschijnt in de app
  2. Gebruiker kan op Windows notulen genereren zonder internet — Ollama of LM Studio genereert de notule lokaal
  3. Transcripties worden lokaal opgeslagen op Windows en blijven beschikbaar na herstart zonder backend-sync
  4. In local-mode op Windows is geen login vereist — app start direct en slaat transcripties op zonder cloud-contact
  5. Gebruiker kan in Windows-instellingen de lokale STT-engine en het Whisper-model kiezen en downloaden
  6. Windows detecteert actieve video-calls (Zoom/Teams/Meet) en start opname-suggestie automatisch

**Plans**: TBD (verwacht 5-6 plans)
**UI hint**: yes

Plans:

- [ ] 03-01: Onderzoek + keuze Windows STT-engine (whisper.cpp Rust-binding vs. alternatief) — spike
- [ ] 03-02: Whisper.cpp Rust-integratie + model-download-management (Tauri commands)
- [ ] 03-03: Lokale transcript-opslag Windows (SQLite via Tauri plugin of filesystem-store)
- [ ] 03-04: Lokale LLM-integratie Windows (Ollama/LM Studio — cross-platform HTTP, hergebruik macOS logica)
- [ ] 03-05: Local-mode auth-bypass + offline flow Windows (parity met macOS `ProcessingMode`)
- [ ] 03-06: Instellingen-UI Windows voor lokale verwerking + video-call auto-detectie Windows

### Phase 4: UX Fixes

**Goal**: Geprioriteerde UX-bevindingen uit Phase 2 zijn uitgevoerd — beide platforms zijn consistent in navigatie, foutstaten, terminologie en toegankelijkheid
**Depends on**: Phase 2, Phase 3
**Requirements**: B-02, B-03, B-04
**Success Criteria** (what must be TRUE):

  1. Alle P1-bevindingen uit de UX-review zijn opgelost op het betreffende platform
  2. Lege/laad/foutstaten gebruiken dezelfde terminologie en visuele patronen op macOS en Windows
  3. Keyboard-navigatie werkt door alle kernflows op Windows; focus-states zijn zichtbaar
  4. Foutmeldingen zijn leesbaar en actionable (geen technische stack-traces zichtbaar voor gebruiker)

**Plans**: TBD (afhankelijk van Phase 2 uitkomst, verwacht 3-5 plans)
**UI hint**: yes

Plans:

- [ ] 04-01: P1 UX-fixes macOS (uit Phase 2 bevindingenlijst)
- [ ] 04-02: P1 UX-fixes Windows (uit Phase 2 bevindingenlijst)
- [ ] 04-03: Consistentie-pass: terminologie, lege/foutstaten, keyboard/focus beide platforms

## Progress

**Execution Order:** 1 → 2 → 3 → 4 (Phase 2 en 3 kunnen parallel starten na Phase 1)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Quick Fixes | 2/3 | In Progress|  |
| 2. UX Review | 0/2 | Not started | - |
| 3. Windows Local-First | 0/6 | Not started | - |
| 4. UX Fixes | 0/3 | Not started | - |

---

## Coverage Validation

Every Active requirement maps to exactly one phase:

| Requirement | Description | Phase |
|-------------|-------------|-------|
| A-01 | Windows STT whisper.cpp + model-download | Phase 3 |
| A-02 | Windows lokale LLM (Ollama/LM Studio) | Phase 3 |
| A-03 | Windows lokale transcript-opslag | Phase 3 |
| A-04 | Windows local-mode auth-bypass + offline flow | Phase 3 |
| A-05 | Windows instellingen-UI lokale verwerking | Phase 3 |
| B-01 | Heuristische UX-review beide platforms | Phase 2 |
| B-02 | UI-consistentie macOS ↔ Windows | Phase 4 |
| B-03 | Toegankelijkheid keyboard/focus/leesbaarheid | Phase 4 |
| B-04 | Uitvoeren geprioriteerde UX-fixes | Phase 4 |
| C-01 | Windows SSE-reconnect backoff | Phase 1 |
| C-02 | HTTPS afdwingen Windows | Phase 1 |
| C-03 | Offline-queue id-identiteit + retry-limiet | Phase 1 |
| C-04 | Video-call detectie Windows | Phase 3 |
| C-05 | macOS local-mode init (backend-profiel-load) | DONE — v1.0.133 |
| D-01 | macOS audio-mix average → element-wise max | Phase 1 |
| D-02 | macOS SystemAudioCapture timer-threading | Phase 1 |

**Coverage: 15/15 Active requirements mapped (1 already done, 14 pending) ✓**

---

## Already Shipped (Pre-Roadmap)

| Version | Delivery | Requirement |
|---------|----------|-------------|
| v1.0.133 | macOS local-mode volledig afgeschermd: alle AWS-backend calls geblokkeerd in local-mode via `ProcessingMode.isLocalMode` SSOT + APIService vangnet-guard; SwiftData eigen store-URL + migratie-fix | C-05 (volledig) |
| v1.0.134 | Zakelijk-notule profiel herontwerp (brand-accent, besluitenlijst/actiepunten met eigenaar+deadline), gecentreerde notule-layout alle render-paden, `{{DATE}}`-injectie on-device | B-04 (gedeeltelijk) |
