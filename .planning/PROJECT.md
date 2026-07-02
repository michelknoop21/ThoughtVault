# ThoughtVault — People & Attribution

## What This Is

ThoughtVault is een cross-platform app (native macOS/iOS in Swift 6/SwiftUI, Windows in Tauri 2/React) die audio opneemt, transcribeert en notulen genereert — via een FastAPI-cloudbackend óf volledig lokaal op het apparaat. Doelgroep: professionals die snel, betrouwbaar en privacy-bewust notulen willen.

Deze milestone (**"People & Attribution"**, v1.1) voegt **persoons-/rolcontext** toe: de installerende gebruiker stelt zich bij eerste gebruik voor via een kort stappenplan, bouwt lokaal een directory van collega's/bekende externen op, en die context voedt de notule-generatie zodat **actiepunten betrouwbaar aan de juiste persoon worden toegewezen** — met een door de gebruiker corrigeerbare toewijzing. Alles privacy-bewust en on-device.

> De vorige milestone **"Parity & Polish" (v1.0.134) staat on hold** — zie `.planning/paused/parity-and-polish/RESUME.md` (Phase 1 geshipt; Phase 2 UX-review macOS-deel klaar; hervatbaar).

## Core Value

Notulen herkennen wie-wie is en wijzen actiepunten betrouwbaar toe aan de juiste persoon, op basis van lokaal opgebouwde persoons-/rolcontext — met behoud van privacy (on-device). De toewijzing is door de gebruiker te corrigeren en blijft bewaard. De onderliggende opname→transcriptie→notulen-flow blijft betrouwbaar werken, óók zonder cloudverbinding.

## Requirements

### Validated

<!-- Shipped en in productie. -->

- ✓ Audio-opname (microfoon + systeemgeluid, gecombineerd) op macOS — existing
- ✓ Cloud- én lokale transcriptie + notulen-generatie (FastAPI/n8n/Whisper/Claude; WhisperKit/Apple Speech + Ollama/LM Studio/Apple Intelligence) — existing
- ✓ macOS local-mode: auth-bypass, volledig offline transcriberen + notuleren (SwiftData-opslag) — existing
- ✓ Auth met token (Keychain/Credential Manager), 2FA, biometrisch, "onthoud mij" — existing
- ✓ Transcript-historie: lokaal + cloud merge, zoeken/filteren — existing
- ✓ Notulen-profielen (notule-stíjl: system/notule prompt, template) — existing
- ✓ Onboarding-flow voor permissies + agenda (macOS/iOS) — existing
- ✓ Microsoft 365 / Apple agenda-integratie (vergaderdetectie) — existing
- ✓ Windows cloud-app: feature-pariteit op cloud-pad — existing
- ✓ Cross-platform parity-fixes Phase 1 (SSE-reconnect, HTTPS, offline-queue id, audio-mix, timer) — v1.0.x (Parity & Polish Phase 1)

### Active

<!-- Scope van deze milestone (People & Attribution). Hypotheses tot geshipt + gevalideerd. -->

**A. Zelf-profilering (onboarding-stappenplan)**
- [ ] Gericht onboarding-stappenplan: gebruiker stelt zich voor (naam, rol/functie, organisatie, aanspreekvormen/aliassen, typische meeting-types). Kort, overslaanbaar, later bewerkbaar.
- [ ] Lokaal `PersonProfile`-model (SwiftData macOS + Windows-equivalent), on-device, werkt in local-mode zonder account.
- [ ] Profiel bewerkbaar via Settings-sectie; integreert met bestaande onboarding (beide platforms).

**B. Mensen-directory (collega's + bekende externen)**
- [ ] Lokale directory: personen met naam, aliassen, rol, intern/extern, organisatie.
- [ ] Seed/aanvulling uit agenda-deelnemers (Microsoft Graph attendees/organizer — nu opgehaald maar weggegooid) en/of eerdere transcripts.
- [ ] Directory-beheer-UI (toevoegen/bewerken/verwijderen), beide platforms.

**C. Context-injectie in notule-generatie**
- [ ] Injecteer self-profile + relevante mensen-context als placeholder (`{{PEOPLE_CONTEXT}}`) in beide paden: lokaal (`LLMService`) en cloud (n8n-webhook payload + workflow).
- [ ] Prompt instrueert de LLM om actiepunt-eigenaars te matchen tegen bekende mensen + intern↔extern te onderscheiden.

**D. Mapping + bewerkbare toewijzing**
- [ ] Detecteer genoemde personen in de notule en koppel aan directory-entries (naam/alias-matching, intern/extern-heuristiek).
- [ ] Bewerkbare "eigenaar"-toewijzing in de notule-weergave (klik om te wijzigen/bevestigen), persistent — beide platforms (let op de twee notule-viewers).
- [ ] Attributie-velden in lokale opslag (`TranscriptRecord`-uitbreiding + Windows-equivalent).

### Out of Scope

<!-- Expliciete grenzen + reden. -->

- Centrale/org-brede auto-sync van profielen tussen gebruikers — vereist backend; lokaal-first kiest hier tegen. Toekomst.
- Spreker-diarisatie op audio-niveau (stem-ID) — attributie werkt op transcripttekst + context, niet op wie-spreekt-wanneer.
- Android (Kotlin/Compose) — aparte milestone.
- Afronden van "Parity & Polish" (Windows local-first, UX-fixes) — on hold, eigen milestone bij hervatten.

## Context

- **Bestaande, volwassen codebase** (v1.0.13x). Native macOS/iOS (Swift 6, SwiftUI, `@Observable`, actors), Windows (Tauri 2 + React 19 + Zustand + Tailwind, Rust-shell), FastAPI-backend (apart repo `../transcript-studio-backend`). Codebase-map in `.planning/codebase/`.
- **"Profiel" is dubbelzinnig:** bestaande `Profile` = notule-stíjl-template (`Models.swift:219-302`). Het nieuwe concept = persoon/rol → aparte term (`PersonProfile`). Nooit hergebruik van `Profile`.
- **Actiepunt-eigenaar wordt nu door de LLM uit transcripttekst gegokt** — geen gestructureerde mensen-context in de prompt (`LLMService.swift:53-76`; backend `transcription.py:450-468` stuurt enkel `profile_id`/`requested_by`).
- **Agenda-deelnemers worden al opgehaald maar weggegooid** (Microsoft Graph `attendees`/`organizer`) — gratis seed-bron voor de directory.
- **Twee notule-viewers** (`NotuleResultView` + `TranscriptDetailView`) met afwijkende acties — relevant voor de toewijzing-UI (FND-008 uit de paused UX-review).
- **Raakt bewust het backend n8n-pad** (prompt-context), wat Parity & Polish nog vermeed.

## Constraints

- **Tech stack**: macOS = Swift 6 strict concurrency, SwiftUI, `@Observable` (geen ObservableObject/Combine), actors voor services. Windows = Tauri 2 + React + Zustand + Rust-commands. Geen platform-vreemde patronen.
- **Lokalisatie**: UI-strings Nederlands (`Localizable.strings` / Windows i18n), code/comments Engels.
- **Design tokens**: macOS via `TS.Spacing/Font/Radius` + `Color.brand*`; Windows via Tailwind + Fluent-icons. Bestaande tokens respecteren.
- **Privacy/Security**: persoons-/mensen-data **lokaal on-device**; geen stiekeme backend-calls; HTTPS afdwingen waar tokens/persoonsdata reizen (cloud-pad).
- **Verificatie (CLAUDE.md/Karpathy)**: geen "klaar" zonder bewijs (BUILD SUCCEEDED, draaiende app, test-output). Chirurgische wijzigingen, simpelste oplossing.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Onboarding = zelf-profilering van de installerende gebruiker | Org-brede herkenning ontstaat emergent doordat elke installatie eigen context opbouwt | — Pending |
| Persoons-/mensen-data lokaal on-device (geen centrale sync) | Privacy/local-first; werkt ook in local-mode zonder account | — Pending |
| Attributie = gestructureerde naam→persoon-mapping + bewerkbare toewijzing (niet alleen prompt-injectie) | Betrouwbare, corrigeerbare eigenaar i.p.v. pure LLM-gok | — Pending |
| Attributie draait óók op **onderwerp→rol/expertise→persoon**, niet alleen naam-matching | Kern van de productvisie: actiepunt over een domein → persoon wiens rol/expertise dat dekt, ook zonder naamsvermelding | — Pending (C-05, D-01) |
| `expertiseTags: [String]` in `PersonProfile` vanaf Phase 1 | Onderwerp-inferentie vereist per-persoon expertise; versioned-migratie-discipline → nu landen voorkomt 2e migratie | — Pending (A-05) |
| **Leerlus**: bevestigde toewijzing verrijkt `expertiseTags` van de persoon (deduped, geen ML) | "De app leert mensen kennen" over meetings heen; goedkoop, hoog visie-fit | — Pending (D-06) |
| `AttributionEntry` draagt `source` + `confidence` (data nu, UI-indicator later) | Onderwerp-inferentie is fuzzy; herkomst/zekerheid moet vastgelegd, visuele indicator is v1.x | — Pending (D-05) |
| Spreker-diarisatie géén v1.1-dependency | Spike 2026-06-05: pipeline levert geen speaker-labels (`whisper_neuron.py:133-140`, één samengevoegd segment); eigen pyannote-diarisatie buiten scope | — Decided |
| Org-context emergent via lokale profielen; org-sync/peer-uitwisseling expliciet future | Local-first/privacy; vrijwillige export/QR/AirDrop pas overwegen ná v1.1-validatie | — Pending |
| Nieuw concept heet `PersonProfile`, nooit hergebruik van `Profile` | `Profile` = notule-stijl; verwarring voorkomen | — Pending |
| Parity & Polish on hold i.p.v. afgerond | Deze capability eerst; P&P volledig bewaard in `.planning/paused/` | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-04 — Milestone v1.1 "People & Attribution" gestart; "Parity & Polish" (v1.0.134) on hold.*
