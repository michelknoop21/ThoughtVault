# Requirements — Parity & Polish

**Milestone:** Parity & Polish (v1.0.13x)
**Scope:** Cross-platform parity (macOS + Windows), UX gap-closure, known bug fixes.
**Out of scope:** Android, code-signing, multi-instance backend, YouTube/Google-OAuth Windows, server-side pagination.

---

## Active Requirements

### A. Windows Local-First Parity

| ID | Requirement | Phase |
|----|-------------|-------|
| A-01 | Lokale STT op Windows via whisper.cpp/Rust-binding met model-download-management | Phase 3 |
| A-02 | Lokale LLM-notulen op Windows via Ollama/LM Studio (cross-platform) | Phase 3 |
| A-03 | Lokale transcript-opslag op Windows (parity met macOS SwiftData-rol) | Phase 3 |
| A-04 | Local-mode op Windows: auth-bypass + volledig offline flow gelijk aan macOS | Phase 3 |
| A-05 | Instellingen-UI op Windows voor lokale verwerking (engine/model-keuze) | Phase 3 |

### B. UX-Review-Gedreven Gap-Closure

| ID | Requirement | Phase |
|----|-------------|-------|
| B-01 | Heuristische UX-review van alle kernflows op macOS en Windows → geprioriteerde bevindingenlijst | Phase 2 |
| B-02 | UI-consistentie macOS ↔ Windows (navigatie, lege/laad/foutstaten, terminologie) | Phase 4 |
| B-03 | Toegankelijkheid: keyboard/focus-navigatie, foutmeldingen, leesbaarheid | Phase 4 |
| B-04 | Uitvoeren van geprioriteerde UX-fixes uit de review | Phase 4 |

### C. Cross-Platform Parity-Fixes

| ID | Requirement | Phase | Notes |
|----|-------------|-------|-------|
| C-01 | Windows SSE-reconnect met exponential backoff (parity met macOS) | Phase 1 | |
| C-02 | HTTPS afdwingen op Windows (zoals macOS `validatedBaseURL()`) | Phase 1 | |
| C-03 | Offline-queue: gedeelde retry-limiet + id-gebaseerde item-identiteit (beide platforms) | Phase 1 | |
| C-04 | Video-call auto-detectie op Windows | Phase 3 | Grouped with Windows local-first work |
| C-05 | macOS local-mode: geen onnodige backend-profiel-load bij init | DONE | Shipped in v1.0.133 |

### D. Bekende Bugs

| ID | Requirement | Phase | Notes |
|----|-------------|-------|-------|
| D-01 | macOS combined-audio: average → element-wise max (`mixAudioFiles`) | Phase 1 | |
| D-02 | macOS `SystemAudioCapture` timer: `MainActor.assumeIsolated` i.p.v. `Task{}` | Phase 1 | |

---

## Validated (Already Shipped)

| ID | Requirement | Shipped |
|----|-------------|---------|
| C-05 | macOS local-mode: geen onnodige backend-profiel-load bij init | v1.0.133 — volledig afgedekt via `ProcessingMode.isLocalMode` SSOT + APIService guard |
| B-04 (partial) | UX-fixes macOS notule-weergave (zakelijk-notule profiel herontwerp, gecentreerde layout, {{DATE}}-injectie) | v1.0.134 — gedeeltelijke B-progress, niet volledige B |

---

## Out of Scope

| Item | Reason |
|------|--------|
| Android (Kotlin/Compose) | Aparte milestone na macOS+Windows pariteit |
| Code signing / notarisatie | Eigen roadmap `docs/ROADMAP-CODE-SIGNING.md` |
| Multi-instance backend | `docs/PLAN-MULTI-INSTANCE.md`, los traject |
| YouTube/Google-OAuth Windows | Niet kern van local-first; alleen meenemen als het triviaal uit B/C volgt |
| Server-side pagination | Pas relevant >500 transcripts/gebruiker (DEC-045) |
| Backend-feature-uitbreiding | Client-side milestone; backend alleen waar parity strikt vereist |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| A-01 | Phase 3 | Pending |
| A-02 | Phase 3 | Pending |
| A-03 | Phase 3 | Pending |
| A-04 | Phase 3 | Pending |
| A-05 | Phase 3 | Pending |
| B-01 | Phase 2 | Pending |
| B-02 | Phase 4 | Pending |
| B-03 | Phase 4 | Pending |
| B-04 | Phase 4 | Pending |
| C-01 | Phase 1 | Complete |
| C-02 | Phase 1 | Complete |
| C-03 | Phase 1 | Complete |
| C-04 | Phase 3 | Pending |
| C-05 | — | Done (v1.0.133) |
| D-01 | Phase 1 | Pending |
| D-02 | Phase 1 | Pending |
