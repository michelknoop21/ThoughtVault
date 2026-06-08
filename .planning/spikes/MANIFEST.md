# Spikes — TranscriptStudio

Experiential/recon spikes that de-risk milestone work before planning.

## Idea

v1.1 **People & Attribution** — voeg persoons-/rolcontext toe aan de notule-pipeline. Phase 3 (Context Injection) en Phase 4 (Attribution Mapping) raken meerdere codebases (macOS Swift, backend FastAPI, n8n) en vroegen om recon vóór planning.

## Spikes

| # | Spike | Type | Verdict | Output |
|---|-------|------|---------|--------|
| 01 | Phase 3 `{{PEOPLE_CONTEXT}}` injection map | recon | ✅ VALIDATED | `01-phase3-injection-map/README.md` |

## Open follow-ups

- **n8n workflow `Iq3AAf8Vk8eQ9dcZ`** → ✅ gemapt via de n8n REST API (MCP gaf geen toegang, REST API met `N8N_API_KEY` uit `.env` wel). Eén injectiepunt (`Build Prompts`), via `PUT /api/v1/workflows/{id}` te updaten in Phase 3-executie. Geen open recon meer.
- **Phase 4** spike (notule-HTML-structuur + FND-008 + AttributionEntry-schema) nog niet uitgevoerd — vereist vóór Phase 4-planning.
