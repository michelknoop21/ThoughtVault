# Phase 2: UX Review - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 levert **één gedocumenteerde, geprioriteerde UX-bevindingenlijst** (`FINDINGS.md`) op die de macOS- en Windows-versies van TranscriptStudio toetst over de vijf kernflows. Het is een **expert UX-review** — geen code-werk, geen user testing. De uitkomst is de directe input voor Phase 4 (UX Fixes).

**Kernflows (per platform doorlopen):**
1. Opname start/stop
2. Transcript-lijst
3. Notule-weergave
4. Instellingen
5. Auth

**Wat dit NIET is:** implementeren van fixes (Phase 4), effort-inschatting (Phase 4), nieuwe features, user testing, of backend-werk.

</domain>

<decisions>
## Implementation Decisions

### Review-uitvoering — gestructureerde live expert review per flow, per platform
- **D-01:** **Volledig live.** Beide apps draaien echt en worden doorgeklikt. Windows draait via **CrossOver op de Mac** met de **CI-gebouwde MSI** (GitLab pipeline via `scripts/deploy-dev.sh` → echte gepackagede Windows-build, gedownload van de download-server), zodat de Windows-UI representatief beoordeeld kan worden — **niet** `tauri dev`. (`tauri dev` is hooguit fallback voor logica-inspectie, niet voor de definitieve visuele/parity-beoordeling.)
- **D-02:** Loop de 5 kernflows **apart door op macOS én Windows** (10 doorlopen totaal).
- **D-03:** Per flow drie checks:
  - **Task completion** — kan de gebruiker de taak zonder blokkade afronden?
  - **Heuristische check** — waar ontstaat frictie, onduidelijkheid, foutkans of feedbackprobleem?
  - **Platform parity check** — wijkt macOS of Windows onnodig af van platformconventies of van elkaar?
- **D-04:** Geen user testing in deze fase. Expert review die een scherpe inputlijst voor Phase 4 oplevert.

### Heuristiek-kader — Nielsen + HIG/Fluent
- **D-05:** **Nielsen's 10 usability heuristics** als gemeenschappelijke basis voor álle bevindingen.
- **D-06:** Aangevuld met **Apple HIG** voor macOS-conventies en **Microsoft Fluent 2** voor Windows-conventies — specifiek voor de platform-parity-checks.

### Prioritering-rubriek — severity × frequentie + parity-boost (lichte triage, géén scorematrix)
- **D-07:** **Basisprioriteit** op taakimpact:
  - **P1 — Kritiek:** blokkeert of ondermijnt een kernflow (opname onduidelijk/faalt stil, opnamestatus niet betrouwbaar zichtbaar, auth blokkeert zonder herstelroute, transcript/notule niet vindbaar na opname, data-verlies of valse opslag/opname-perceptie).
  - **P2 — Belangrijk:** taak lukt, maar met duidelijke frictie/onzekerheid/workaround (ambigue labels, late feedback, gok-knoppen, slecht scanbare lijst, onlogisch gegroepeerde instellingen, verwarrend macOS↔Windows-verschil).
  - **P3 — Verbetering/polish:** kleine usability-, copy-, visuele of conventieproblemen zonder wezenlijke hinder (spacing, alignment, microcopy, lichte icoon-inconsistentie, secundaire affordances).
- **D-08:** **Frequentie-regel:** verhoog de prioriteit met **één niveau** bij een hoogfrequente/centrale handeling (bv. opname start/stop); verlaag met één niveau bij pure edge cases of zelden gebruikte instellingen.
- **D-09:** **Parity-boost:** verhoog met **één niveau** bij een macOS↔Windows-verschil dat het milestone-doel raakt — in gedrag, statusfeedback, terminologie, navigatie, flow-volgorde, herstelmogelijkheden of vindbaarheid van dezelfde functie. **Niet** boosten voor puur visuele/cosmetische, platform-eigen verschillen (andere spacing → meestal P3; "Minutes" vs "Notes" → P2; stop-knop voelt/werkt anders → P1/P2).
- **D-10:** **Géén numerieke scorematrix** — gebruik het als lichte triage-regel. Noteer per finding kort wáárom iets P1/P2/P3 is. **Effort telt niet mee in Phase 2** (hoort thuis in Phase 4).

### Bevindingen-format — één `FINDINGS.md` met stabiele FND-IDs (source of truth)
- **D-11:** **Eén markdown-tabel** is de source of truth. Bestandsnaam binnen de phase-directory: `FINDINGS.md`.
- **D-12:** Stabiele IDs `FND-001`, `FND-002`, … — **niet hernummeren** zodra toegekend.
- **D-13:** Vaste kolommen: `ID | Prio | Platform | Flow | Titel | Heuristiek / richtlijn | Severity | Frequentie | Parity | Impact | Fix-hint | Evidence`.
- **D-14:** Gestandaardiseerde kolomwaarden:
  - **Prio:** P1 / P2 / P3
  - **Platform:** macOS / Windows / Beide
  - **Flow:** Opname start/stop / Transcript-lijst / Notule-weergave / Instellingen / Auth
  - **Severity:** Blokkerend / Hinderend / Cosmetisch
  - **Frequentie:** Hoog / Middel / Laag
  - **Parity:** Ja / Nee / N.v.t.
- **D-15:** **Optionele detailsectie** onder de tabel — alleen voor complexe P1/P2-items een kort uitgewerkt blok (observatie, impact, aanbeveling, evidence).
- **D-16:** **Eén gezamenlijke lijst over beide platforms** (géén per-platform bestanden als primair format) — dat is precies de Phase 2-output. Phase 4-plannen (02-01 macOS, 02-02 Windows) **verwijzen naar FND-IDs** i.p.v. findings te dupliceren.

### FINDINGS.md header (vast)
```
# Phase 2 UX Review Findings
Scope:
- Platforms: macOS, Windows
- Flows: opname start/stop, transcript-lijst, notule-weergave, instellingen, auth
- Framework: Nielsen + Apple HIG / Microsoft Fluent
- Prioritering: severity × frequentie + parity-boost
```

### Claude's Discretion
- Concrete bewoording van losse bevindingen en welke heuristiek het beste past per item.
- Exacte invulling van de optionele detailsecties (D-15).
- Evidence-vorm (screenshot-referentie / scherm-aanduiding / timestamp) per finding.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase-scope & requirements
- `.planning/ROADMAP.md` §"Phase 2: UX Review" — goal, success criteria, verwachte 2 plans (02-01 macOS, 02-02 Windows).
- `.planning/REQUIREMENTS.md` — requirement **B-01** (heuristische UX-review beide platforms).
- `.planning/PROJECT.md` §Constraints — design tokens & lokalisatie die de review-bevindingen moeten respecteren.

### Bedoelde flows (referentiegedrag voor de review)
- `docs/HANDLEIDING.md` — eindgebruikershandleiding; beschrijft hoe de kernflows hóren te werken (referentie voor "task completion").
- `docs/ARCHITECTURE.md` — flow-architectuur opname→transcriptie→notulen.

### Codebase-oriëntatie (waar de schermen leven)
- `.planning/codebase/STRUCTURE.md` — view/scherm-locaties per platform.
- `.planning/codebase/CONVENTIONS.md` — bestaande UI-patronen & design-token-conventies.
- `.planning/codebase/CONCERNS.md` — bekende fragiele plekken (kunnen UX-symptomen verklaren).

### Platform-richtlijnen (extern kader voor parity-checks)
- Apple Human Interface Guidelines (macOS) — extern, voor D-06 macOS-conventies.
- Microsoft Fluent 2 Design System (Windows) — extern, voor D-06 Windows-conventies.
- Nielsen Norman Group — 10 Usability Heuristics — extern, basis-kader D-05.

</canonical_refs>

<code_context>
## Existing Code Insights

### Te reviewen schermen (per flow, per platform)

| Flow | macOS | Windows |
|------|-------|---------|
| Opname start/stop | `macos/Views/RecordingView.swift`, `macos/Views/Components/RecordingWidgetView.swift`, `macos/Views/Components/WaveformView.swift` | `windows/src/pages/RecordingPage.tsx`, `windows/src/components/recording/RecordingWidget.tsx`, `windows/src/components/recording/WaveformVisualizer.tsx` |
| Transcript-lijst | `macos/Views/TranscriptsView.swift`, `macos/Views/Components/TranscriptCard.swift` | `windows/src/pages/TranscriptsPage.tsx`, `windows/src/components/transcripts/TranscriptsList.tsx` |
| Notule-weergave | `macos/Views/NotuleResultView.swift` (+ `Components/EditableHTMLWebView.swift`) | `windows/src/components/transcripts/TranscriptDetail.tsx` |
| Instellingen | `macos/Views/SettingsView.swift` | `windows/src/pages/SettingsPage.tsx`, `windows/src/stores/settingsStore.ts` |
| Auth | `macos/Views/LoginView.swift`, `macos/ViewModels/AuthViewModel.swift` | `windows/src/pages/LoginPage.tsx`, `windows/src/stores/authStore.ts` |

### Established Patterns
- macOS: SwiftUI + `@Observable`, design tokens `TS.Spacing/Font/Radius`, `Color.brand*`/`Color.label*`. Bevindingen over consistentie moeten naar deze tokens verwijzen, niet naar losse waarden.
- Windows: Tauri 2 + React 19 + Zustand + Tailwind + Fluent-icons. Per-store state (`recordingStore`, `transcriptsStore`, `settingsStore`, `authStore`).
- Lokalisatie: NL UI-strings (macOS `Localizable.strings`, Windows i18n) — terminologie-inconsistenties (bv. "Minutes" vs "Notes") zijn parity-bevindingen.

### Integration Points
- Geen code-wijziging in Phase 2. Output `FINDINGS.md` is de hand-off naar Phase 4-plannen (02-01 macOS / 02-02 Windows), die via FND-IDs terugverwijzen.
- Niet-kernflow-schermen bestaan ook (`OnboardingView`, `TasksView`, `ProcessingView`, `AccountView`, `SavedRecordings`) — buiten de 5 kernflows; alleen noteren als ze een kernflow direct raken.

</code_context>

<specifics>
## Specific Ideas

- **Voorbeeld-finding (door gebruiker aangeleverd als format-anker):**
  - `FND-001 | P1 | Beide | Opname start/stop | Opnamestatus is onvoldoende expliciet na starten | Visibility of system status | Blokkerend | Hoog | Nee | Gebruiker weet niet zeker of opname actief is | Maak actieve opname persistent zichtbaar met label + indicator + duidelijke stop-actie | screenshot/schermref`
- De "opnamestatus-duidelijkheid"-bevinding wordt expliciet als waarschijnlijke P1 genoemd — meeneemkandidaat, mits live geverifieerd.
- Windows draait via **CrossOver** met de **CI-gebouwde MSI** — agents die de review uitvoeren bouwen de MSI via de GitLab pipeline (`scripts/deploy-dev.sh`), downloaden hem van de download-server en installeren hem onder CrossOver op de Mac (niet de Tauri dev-server).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. Geen scope creep; alle vier besproken gebieden raken puur de HOE van de review, niet de WAT.

</deferred>

---

*Phase: 2-UX Review*
*Context gathered: 2026-06-04*
