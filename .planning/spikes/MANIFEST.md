# Spikes — TranscriptStudio

Experiential/recon spikes that de-risk milestone work before planning.

## Idea

v1.1 **People & Attribution** — voeg persoons-/rolcontext toe aan de notule-pipeline. Phase 3 (Context Injection) en Phase 4 (Attribution Mapping) raken meerdere codebases (macOS Swift, backend FastAPI, n8n) en vroegen om recon vóór planning.

## Spikes

| # | Spike | Type | Verdict | Output |
|---|-------|------|---------|--------|
| 01 | Phase 3 `{{PEOPLE_CONTEXT}}` injection map | recon | ✅ VALIDATED | `01-phase3-injection-map/README.md` |

## Open follow-ups

- **n8n workflow `Iq3AAf8Vk8eQ9dcZ`** node-structuur kon niet via MCP worden gemapt (MCP-access uit in workflow-settings). Handmatige UI-inspectie door Michel vereist vóór de n8n-deelstap van Phase 3. Beide LLM-branches (Claude-proxy + Ollama, DEC-057).
- **Phase 4** spike (notule-HTML-structuur + FND-008 + AttributionEntry-schema) nog niet uitgevoerd — vereist vóór Phase 4-planning.
