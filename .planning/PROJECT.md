# TranscriptStudio — Parity & Polish

## What This Is

TranscriptStudio is een cross-platform app (native macOS/iOS in Swift 6/SwiftUI, Windows in Tauri 2/React) die audio opneemt, transcribeert en notulen genereert. Gebruikers nemen vergaderingen/gesprekken op (microfoon + systeemgeluid), waarna transcriptie en notulen-generatie volgen — via een FastAPI-cloudbackend óf volledig lokaal op het apparaat. Doelgroep: professionals die snel, betrouwbaar en privacy-bewust notulen willen.

Deze milestone ("Parity & Polish") richt zich op twee dingen: (1) beide desktop-platforms volledig cloud-onafhankelijk kunnen laten draaien, en (2) een UX-review-gedreven gelijktrekking van UI/UX-gaps en bekende bugs tussen macOS en Windows.

## Core Value

De opname→transcriptie→notulen-flow werkt betrouwbaar en consistent op zowel macOS als Windows — óók zonder cloudverbinding. Als alles faalt, moet dit blijven werken.

## Requirements

### Validated

<!-- Shipped en in productie (v1.0.131). Afgeleid uit de codebase-map. -->

- ✓ Audio-opname (microfoon + systeemgeluid, gecombineerd) op macOS — existing
- ✓ Cloud-transcriptie + notulen-generatie via FastAPI/n8n/Whisper/Claude — existing
- ✓ Live taakvoortgang via SSE (macOS met reconnect, Windows zonder) — existing
- ✓ macOS local-first pad: WhisperKit/Apple Speech (STT) + Ollama/LM Studio/Apple Intelligence (LLM) + SwiftData opslag — existing
- ✓ macOS local-mode: auth-bypass, volledig offline transcriberen + notuleren — existing
- ✓ Offline-queue voor mislukte uploads (beide platforms, asymmetrische retry-limieten) — existing
- ✓ Auth met token (Keychain/Credential Manager), 2FA, "onthoud mij" — existing
- ✓ Transcript-historie: lokaal + cloud merge, zoeken/filteren — existing
- ✓ YouTube-captions pipeline (macOS Google-OAuth fallback) — existing
- ✓ Video-call auto-detectie (macOS-only) — existing
- ✓ Windows cloud-app: volledige feature-pariteit op cloud-pad (Zustand + Tauri Rust) — existing
- ✓ Profielen voor notulen-generatie (system/notule prompt, template) — existing

### Active

<!-- Scope van deze milestone. Hypotheses tot geshipt + gevalideerd. -->

**A. Windows local-first parity (cloud-onafhankelijk draaien)**
- [ ] Lokale STT op Windows (whisper.cpp / Rust-binding) met model-download-management
- [ ] Lokale LLM-notulen op Windows (Ollama / LM Studio, cross-platform)
- [ ] Lokale transcript-opslag op Windows (parity met macOS SwiftData-rol)
- [ ] Local-mode op Windows: auth-bypass + volledig offline flow gelijk aan macOS
- [ ] Instellingen-UI op Windows voor lokale verwerking (engine/model-keuze)

**B. UX-review-gedreven gap-closure (beide platforms)**
- [ ] Heuristische UX-review van alle kernflows op macOS én Windows → geprioriteerde bevindingenlijst
- [ ] UI-consistentie macOS ↔ Windows (navigatie, lege/laad/foutstaten, terminologie)
- [ ] Toegankelijkheid: keyboard/focus-navigatie, foutmeldingen, leesbaarheid
- [ ] Uitvoeren van geprioriteerde UX-fixes uit de review

**C. Cross-platform parity-fixes**
- [ ] Windows SSE-reconnect met backoff (parity met macOS, geen "failed" bij netwerk-hik)
- [ ] HTTPS afdwingen op Windows (zoals macOS `validatedBaseURL()`)
- [ ] Offline-queue gelijktrekken: gedeelde retry-limiet + id-gebaseerde item-identiteit
- [ ] Video-call auto-detectie op Windows
- [ ] macOS local-mode: geen onnodige backend-profiel-load bij init

**D. Bekende bugs**
- [ ] macOS combined-audio mixing: average → element-wise max (CLAUDE.md-gotcha naleven)
- [ ] macOS `SystemAudioCapture` timer-threading: `MainActor.assumeIsolated` i.p.v. `Task{}` (DEC-042)

### Out of Scope

<!-- Expliciete grenzen + reden. -->

- Android (Kotlin/Compose) — niet in deze milestone; macOS+Windows eerst gelijktrekken, Android volgt apart
- Code signing / notarization (macOS Developer ID, Windows OV-cert) — eigen roadmap (`docs/ROADMAP-CODE-SIGNING.md`), aparte milestone
- Multi-instance backend-deployment / horizontale schaling — `docs/PLAN-MULTI-INSTANCE.md`, los traject
- YouTube/Google-OAuth-fallback op Windows — geen kern van local-first; alleen meenemen als het triviaal uit B/C volgt
- Server-side pagination voor transcripts — pas relevant >500 transcripts/gebruiker (DEC-045)
- Backend-feature-uitbreiding (FastAPI/n8n) — deze milestone is client-side; backend alleen waar parity het strikt vereist

## Context

- **Bestaande, volwassen codebase** op v1.0.131. Native macOS/iOS (Swift 6, SwiftUI, `@Observable`, actors), Windows (Tauri 2.2 + React 19 + Zustand + Tailwind, Rust-shell), FastAPI-backend (apart repo). Volledige codebase-map in `.planning/codebase/`.
- **Asymmetrie macOS ↔ Windows is de kern van het probleem.** macOS heeft een volledig local-first pad; Windows is cloud-only. Veel gaps (SSE-reconnect, HTTPS, video-call, local-mode) bestaan alleen aan Windows-kant.
- **Lokale engines verschillen per platform.** macOS: WhisperKit (CoreML) + Apple Intelligence + Apple Speech. Windows heeft geen Swift-equivalent → STT via whisper.cpp/Rust; LLM via Ollama/LM Studio (cross-platform, draait al op macOS). Te onderzoeken keuze in research/plan-fase.
- **Bekende fragiele plekken** (uit `CONCERNS.md`): Windows SSE zonder reconnect, offline-queue JSON-identiteitsvergelijking, `try!`-crashes (LocalTranscriptStore, extractStyles), audio-mix average-bug, timer-threading. n8n Claude-proxy is single point of failure voor `handleiding`-profiel (backend, buiten scope).
- **Build/CI**: GitLab CI (Mac shell-runner + self-hosted Windows-PC), VERSION als single source of truth, auto patch-bump per commit op `main`.

## Constraints

- **Tech stack**: macOS = Swift 6 strict concurrency, SwiftUI, `@Observable` (geen ObservableObject/Combine), actors voor services. Windows = Tauri 2 + React + Zustand + Rust-commands. Geen platform-vreemde patronen introduceren.
- **Lokalisatie**: UI-strings Nederlands (`Localizable.strings` / Windows i18n), code/comments Engels.
- **Design tokens**: macOS via `TS.Spacing/Font/Radius` (Theme.swift) + `Color.brand*`; Windows via Tailwind + Fluent-icons. UX-werk moet bestaande tokens respecteren, niet vervangen.
- **Privacy/Security**: local-first moet écht offline kunnen (geen stiekeme backend-calls); HTTPS afdwingen waar tokens reizen.
- **Verificatie (CLAUDE.md/Karpathy)**: geen "klaar" zonder bewijs (BUILD SUCCEEDED, draaiende app, test-output). Chirurgische wijzigingen, simpelste oplossing.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Milestone = macOS + Windows, Android buiten scope | Desktop-pariteit eerst; Android is grotere aparte lift | — Pending |
| Windows krijgt volledige local-first parity (STT + LLM + opslag) | Beide platforms moeten cloud-onafhankelijk draaien | — Pending |
| UX-review stuurt prioritering; local-first is vereiste capability | "Primair UI/UX" met volledige UX-review als rode draad | — Pending |
| Bekende bugs + parity-fixes meegenomen in scope | Gap-closure is incompleet zonder de gedocumenteerde fixes | — Pending |
| Lokale STT-engine Windows nog te kiezen (whisper.cpp kandidaat) | Geen WhisperKit op Windows; research in plan-fase | — Pending |

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
*Last updated: 2026-06-03 after initialization*
