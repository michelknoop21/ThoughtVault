# Spike 01 — Phase 3 `{{PEOPLE_CONTEXT}}` Injection Map

**Verdict:** ✅ VALIDATED (recon) — alle injectiepunten gelokaliseerd en geverifieerd: macOS-code, 4 backend-sites, én de n8n-workflow (via REST API). Geen open onbekenden meer.
**Date:** 2026-06-08
**Goal:** Vóór Phase 3-planning exact vaststellen WÁÁR `{{PEOPLE_CONTEXT}}` geïnjecteerd moet worden over de drie generatie-paden (lokaal LLM, cloud n8n, regenerate), en of het `handleiding`/Claude-proxy pad (DEC-057) afwijkt.
**Tags:** phase-3, context-injection, backend, n8n, llm, recon

---

## TL;DR — De injectie-architectuur

Er zijn **drie codebases** met injectiepunten, niet één:

1. **macOS lokaal pad** — één chokepoint (`buildNotuleUserContent`). App heeft de directory lokaal → bouwt context zelf.
2. **Backend cloud pad** — **4 payload-bouw-sites** die `people_context` als passthrough-veld naar n8n moeten doorgeven. De backend kan de context NIET zelf bouwen (directory is on-device only, Phase 2 B-04). **Dus de app moet `people_context` meesturen.**
3. **n8n workflow** — substitueert `{{PEOPLE_CONTEXT}}` in **één node** (`Build Prompts`). Beide LLM-branches (Claude-proxy én Ollama) erven die prompt, want de `Route Profile`-split (DEC-057) zit downstream → **géén per-branch edit**. Gemapt via de n8n REST API; via dezelfde API te updaten (geen handmatige UI nodig).

**Kritieke bevinding:** het cloud-pad stuurt vanaf de app géén prompts mee — de backend leest `system_prompt`/`notule_prompt` uit zijn eigen profiel-DB. De **directory is echter on-device only**, dus de backend kan de mensen-context niet samenstellen. Conclusie: **de app stuurt een nieuw `people_context`-veld** in elk cloud-request; de 4 backend-sites geven het door; n8n injecteert het. Geen prompt-bouw verschuift naar de backend.

---

## Injectiepunt-kaart

### A. macOS lokaal LLM-pad (Ollama / LM Studio / Apple Intelligence)

| # | Locatie | Rol |
|---|---------|-----|
| L1 | `macos/Services/LLMService.swift:59` `buildNotuleUserContent(notulePrompt:transcription:outputTemplate:)` | **DÉ chokepoint.** Verwerkt al `{{TRANSCRIPTION}}`/`{{OUTPUT_TEMPLATE}}`-placeholders. Voeg `{{PEOPLE_CONTEXT}}`-substitutie hier toe (+ fallback-prepend voor profielen zonder placeholder). |
| L1-callers | `RecordingViewModel.swift:752` (primaire lokale generatie) + `:796` (`regenerateNotuleLocally`) | Beide lopen via `generateNotulen` → `buildNotuleUserContent`. **Eén fix dekt lokaal-genereren én lokaal-regenereren.** |
| L2 | `systemPrompt`-argument van `generateNotulen` (zelfde call-sites) | Optioneel tweede injectie-vector (context in system i.p.v. user-content). Aanbeveling: context in user-content (L1), system blijft persona. |

**Sanitisatie (C-03):** moet in de Swift-laag gebeuren vóór substitutie — namen/aliassen met newlines of `{{...}}` strippen, wrappen in `<people_context>…</people_context>`. De bestaande code substitueert transcription bewust LAATST om placeholder-swaps te voorkomen; people_context moet net als output_template VÓÓR transcription gesubstitueerd worden (trusted-first volgorde behouden).

### B. Backend cloud n8n-pad — 4 payload-bouw-sites (passthrough)

Alle vier bouwen een `queue_item["payload"]` dict met `transcription` + `profile_id` + `system_prompt` + `notule_prompt` + `output_template`. Voeg overal `"people_context": <from request>` toe. **In één commit** (partiële deploy = inconsistente notulen).

| # | Bestand | Site | Pad |
|---|---------|------|-----|
| B1 | `app/services/transcription_service.py` | `:680-697` (queue-processor `payload`) | **Primair audio-pad** (na transcriptie, async). `transcribe_audio` (`routes/transcription.py:312`) enqueuet alléén — payload wordt hier gebouwd. |
| B2 | `app/routes/transcription.py` | `:453-469` (`transcribe_text` `payload`) | Tekst → notule (upload van bestaande transcriptie). |
| B3 | `app/routes/transcription.py` | `:624-640` (`transcribe_youtube` `payload`) | YouTube → notule. |
| B4 | `app/routes/transcripts.py` | `:308-322` (`regenerate` `queue_item.payload`) | **Cloud regenerate** — meest over het hoofd gezien. |

Elk request-model moet een optioneel `people_context: str` veld krijgen (`TranscribeTextRequest`, `YouTubeTranscribeRequest`, regenerate-request, en de multipart-form voor `transcribe_audio`).

### C. macOS app — request-payloads die `people_context` moeten meesturen

| # | Locatie | Request |
|---|---------|---------|
| C1 | `APIService.swift` `regenerateNotule` `:689-698` | Stuurt nu enkel `transcript_id`/`profile_id`/`use_premium` → voeg `people_context` toe. |
| C2 | `transcribe_text`/audio-upload/youtube call-sites in `APIService.swift` | Idem — context-veld toevoegen aan elk cloud-generatie-request. |
| C0 | **Nieuwe** `PeopleContextBuilder` (Swift) | Bouwt het gesanitiseerde blok uit `PersonDirectoryService` + de aan de opname gekoppelde `CalendarEvent`-attendees (Phase 2 plumbing). Gedeeld door lokaal (L1) én cloud (C1/C2). |

### D. n8n workflow `Iq3AAf8Vk8eQ9dcZ` — ✅ GEMAPT (via n8n REST API, niet MCP)

> MCP gaf "Workflow is not available in MCP", maar de **n8n REST API** (`GET {N8N_URL}/api/v1/workflows/{id}` met `X-N8N-API-KEY`, key in `.env`) werkt wél. Workflow opgehaald + 17 nodes geparset.

**Naam:** "Notule Generator - Compleet Met Guardrails" · 17 nodes · active. Flow:

```
Webhook → Extract JSON Data → Build Prompts → Guardrails1 → Route Profile (if profileId=="handleiding")
                                                              ├─ true  → Claude: Genereer Handleiding (httpRequest → n8n_claude_code:3100)
                                                              └─ false → Prepare for AI Agent → AI Agent (Ollama Chat Model)
            → Guardrails → Cleanup LLM Output → Convert to HTML → Extract Title → HTTP Request (callback)
```

**Doorslaggevende bevinding — ÉÉN injectiepunt, géén branch-divergentie:**
De `Build Prompts` [code]-node assembleert de prompt en doet al placeholder-substitutie:
`notulePrompt.replace(/\{\{TRANSCRIPTION\}\}/…).replace(/\{\{OUTPUT_TEMPLATE\}\}/…).replace(/\{\{DATE\}\}/…)`.
Het geeft `{ systemPrompt, userPrompt: notulePrompt, … }` terug.
**Beide** LLM-branches lezen díé output:
- Claude-tak: `jsonBody` = `$("Build Prompts").item.json.systemPrompt` (system message).
- Ollama-tak: `Prepare for AI Agent` herstelt `userPrompt`/`systemPrompt` uit `$('Build Prompts').item.json`.

De `Route Profile`-split (DEC-057, `profileId=="handleiding"` → Claude, anders Ollama) zit **downstream** van Build Prompts. Dus de context is al in de prompt gebakken vóór de split → **geen per-branch edit nodig.**

**n8n-wijziging (2 code-nodes):**
| Node | Wijziging |
|------|-----------|
| `Extract JSON Data` | `const peopleContext = json.people_context \|\| '';` + `peopleContext` in de return-json. |
| `Build Prompts` | lees `data.peopleContext`; voeg `.replace(/\{\{PEOPLE_CONTEXT\}\}/g, peopleContext)` toe aan `notulePrompt` (+ evt. `systemPrompt`); fallback-prepend wanneer placeholder ontbreekt. |

**Automatiseerbaar:** de workflow is via de REST API te updaten (`PUT /api/v1/workflows/{id}` met de aangepaste `nodes`) — n8n-stap hoeft in Phase 3-executie dus **niet** handmatig (wel apart verifiëren via een test-execution; niet door GitLab CI gedekt).

---

## Antwoorden op de spike-vragen (uit ROADMAP Phase 3)

1. **n8n node-structuur** → ✅ gemapt via REST API (17 nodes). Eén injectiepunt: `Build Prompts` (+ `Extract JSON Data` passthrough). Beide LLM-branches erven het.
2. **4 backend payload-locaties** → ✅ geverifieerd: B1 `transcription_service.py:680`, B2 `transcription.py:453`, B3 `transcription.py:624`, B4 `transcripts.py:308`. Allen identieke payload-shape → uniforme `people_context`-passthrough.
3. **`handleiding` Claude-proxy (DEC-057) shares of diverges?** → **Backend: shares** (zelfde 4 sites, profiel-agnostisch). **n8n: ook effectief shares** — de routing (`Route Profile`) zit downstream van `Build Prompts`, waar de context al in de prompt is gebakken. Eén injectie dekt beide branches; geen divergentie voor onze wijziging.
4. **`regenerateNotule` (APIService.swift:689)** → ✅ bevestigd. Cloud-regenerate stuurt nu géén prompts/context (alleen ids). Lokaal-regenerate (`RecordingViewModel.swift:796`) loopt via dezelfde `buildNotuleUserContent`-chokepoint als primaire generatie.

---

## Aanbevolen Phase 3 plan-vorm (input voor planning)

- **Wave A — gedeelde Swift builder + sanitisatie:** `PeopleContextBuilder` + unit-tests (sanitisatie, begrenzing C-02, wrapping C-03).
- **Wave B — lokaal pad:** `buildNotuleUserContent` placeholder + fallback-prepend (dekt L1 + beide callers). Testcase C-05 (onderwerp→rol-toewijzing).
- **Wave C — cloud passthrough (één commit):** 4 backend sites (B1-B4) + request-modellen + macOS request-payloads (C1/C2). Zichtbaar in n8n execution-log (success-criterium 2).
- **Wave D — n8n (via REST API):** `Extract JSON Data` passthrough + `Build Prompts` `{{PEOPLE_CONTEXT}}`-substitutie (één node, dekt beide branches). Update via `PUT /api/v1/workflows/{id}`; verifieer met een test-execution (niet door GitLab CI gedekt).
- **Windows-pariteit:** Tauri heeft een eigen lokaal-pad + cloud-requests — spiegelen (buiten deze macOS-recon; opnemen in plan-scope).

**Risico's:** (1) partiële backend-deploy → 1 commit verplicht; (2) n8n-update via REST API → niet door GitLab CI gedekt, los verifiëren met test-execution (+ workflow-backup vóór `PUT`); (3) placeholder-volgorde (trusted-first: people_context/template vóór transcription) niet breken; (4) profielen zonder placeholder → fallback-prepend, geen crash (success-criterium 5).
