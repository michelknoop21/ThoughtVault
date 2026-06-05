# Requirements — People & Attribution

**Milestone:** People & Attribution (v1.1)
**Scope:** Lokale persoons-/rolcontext (zelf-profilering + mensen-directory) die de notule-generatie voedt en actiepunten betrouwbaar + corrigeerbaar aan personen toewijst. Cross-platform (macOS + Windows), privacy-bewust on-device.
**Out of scope:** Centrale/org-brede profiel-sync, spreker-diarisatie op audio-niveau, Android, afronden van "Parity & Polish".

---

## Active Requirements

### A. Zelf-profilering (onboarding-stappenplan)

| ID | Requirement | Phase |
|----|-------------|-------|
| A-01 | De installerende gebruiker doorloopt bij eerste gebruik een kort, overslaanbaar stappenplan waarin hij zich voorstelt (naam, rol/functie, organisatie, aanspreekvormen/aliassen, typische meeting-types) | Phase 1 |
| A-02 | Het zelf-profiel wordt lokaal on-device bewaard (`PersonProfile`, `isSelf`-vlag) en werkt in local-mode zonder account — macOS én Windows | Phase 1 |
| A-03 | De gebruiker kan zijn profiel later bekijken en bewerken via een Settings-sectie (beide platforms) | Phase 1 |
| A-04 | Een app-upgrade die het nieuwe datamodel introduceert behoudt bestaande transcript-historie (versioned SwiftData-migratie; geen stille data-wipe) | Phase 1 |
| A-05 | `PersonProfile` bevat expertise-/onderwerp-tags (`expertiseTags: [String]`) náást de `rol`-tekst, zodat onderwerp→rol→persoon-inferentie later mogelijk is zonder tweede migratie | Phase 1 |

### B. Mensen-directory (collega's + bekende externen)

| ID | Requirement | Phase |
|----|-------------|-------|
| B-01 | De gebruiker kan personen (collega's en bekende externen) lokaal vastleggen met naam, aliassen, rol, intern/extern-status en organisatie | Phase 2 |
| B-02 | De gebruiker kan personen toevoegen/bewerken/verwijderen via een directory-beheer-UI (beide platforms) | Phase 2 |
| B-03 | De directory kan (semi-)automatisch worden aangevuld vanuit agenda-deelnemers (Microsoft Graph attendees/organizer — nu weggegooid) en/of eerder verwerkte transcripts, met de gebruiker in controle | Phase 2 |
| B-04 | Directory-personen dragen dezelfde `expertiseTags`-velden als het zelf-profiel (gedeeld `PersonProfile`-model), bewerkbaar via de directory-UI | Phase 2 |

### C. Context-injectie in notule-generatie

| ID | Requirement | Phase |
|----|-------------|-------|
| C-01 | Bij notule-generatie wordt relevante mensen-context (zelf-profiel + betrokken personen) als `{{PEOPLE_CONTEXT}}`-placeholder geïnjecteerd in zowel het lokale pad (`LLMService`) als het cloud-pad (n8n-webhook payload + workflow), inclusief het aparte regenerate-pad | Phase 3 |
| C-02 | De geïnjecteerde context is begrensd (deelnemer-gericht, met een maximum) zodat irrelevante personen prompt-kwaliteit en -kosten niet schaden | Phase 3 |
| C-03 | Mensen-context (namen/aliassen uit agenda/directory) wordt gesanitiseerd vóór prompt-injectie, zodat invoer geen prompt-instructies kan kapen | Phase 3 |
| C-04 | De notule-prompt instrueert de LLM expliciet om actiepunt-eigenaars te matchen tegen bekende personen en intern↔extern te onderscheiden | Phase 3 |
| C-05 | De notule-prompt instrueert de LLM om óók op **onderwerp→rol/expertise** te redeneren: een actiepunt over een domein (bv. grafisch ontwerp, marketing, IT) wordt toegewezen aan de persoon wiens `rol`/`expertiseTags` dat domein dekken, ook zonder expliciete naamsvermelding | Phase 3 |

### D. Mapping + bewerkbare toewijzing

| ID | Requirement | Phase |
|----|-------------|-------|
| D-01 | Na generatie worden in de notule genoemde personen gedetecteerd en gekoppeld aan directory-entries (naam/alias-matching + onderwerp→rol-inferentie + intern/extern-heuristiek), client-side zodat persoonsdata lokaal blijft | Phase 4 |
| D-02 | De gebruiker ziet per actiepunt een eigenaar en kan die met één klik bevestigen/wijzigen via een persoon-picker uit de directory | Phase 4 |
| D-03 | Een gewijzigde/bevestigde eigenaar wordt persistent lokaal bewaard bij het transcript (`TranscriptRecord`-uitbreiding + Windows-equivalent) en blijft behouden na sluiten/heropenen | Phase 4 |
| D-04 | De eigenaar-toewijzing werkt consistent in beide notule-weergaven via een gedeelde component (lost de twee-viewer-divergentie FND-008 op) | Phase 4 |
| D-05 | Elke toewijzing draagt herkomst + zekerheid (`AttributionEntry.source`: `manual`/`name-match`/`topic-inference`, `confidence`: laag/midden/hoog), persistent opgeslagen; UI-indicator mag later (v1.x) | Phase 4 |
| D-06 | **Leerlus**: bevestigt/wijzigt de gebruiker een eigenaar voor een actiepunt met een herkenbaar onderwerp, dan worden de onderwerp-keywords toegevoegd aan de `expertiseTags` van die persoon (deduped, geen ML) — de directory leert mensen kennen over meetings heen | Phase 4 |

---

## Future (deferred)

| Item | Reason |
|------|--------|
| Org-brede auto-sync van profielen tussen gebruikers | Vereist backend; lokaal-first kiest hier tegen. Toekomst. |
| Vrijwillige peer-profiel-uitwisseling (export/QR/AirDrop, geen centrale backend) | Emergent org-context zonder server; pas overwegen ná v1.1-validatie van local-first attributie |
| Spreker-diarisatie op audio-niveau (stem-ID) | **Spike uitgevoerd 2026-06-05**: backend (`whisper_neuron.py:133-140`) levert één samengevoegd segment, géén speaker-labels/timestamps; macOS lokaal-pad idem. Eigen diarisatie (pyannote) bouwen valt buiten v1.1. Attributie werkt op tekst + context, niet op wie-spreekt-wanneer |
| Confidence-/onzekerheid-**indicator in de UI** (gestreepte chip e.d.) | Data wordt al opgeslagen (D-05); visuele indicator pas na validatie stabiele inferentie |

---

## Out of Scope

| Item | Reason |
|------|--------|
| Centrale/org-brede profiel-sync | Backend-feature; buiten privacy/local-first scope |
| Spreker-diarisatie (audio) | Andere techniek; niet nodig voor tekst+context-attributie |
| Android | Aparte milestone |
| Afronden "Parity & Polish" (Windows local-first, UX-fixes) | On hold; eigen milestone bij hervatten |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| A-01 | Phase 1 | Complete |
| A-02 | Phase 1 | Complete |
| A-03 | Phase 1 | Complete |
| A-04 | Phase 1 | Complete |
| A-05 | Phase 1 | Complete |
| B-01 | Phase 2 | Pending |
| B-02 | Phase 2 | Pending |
| B-03 | Phase 2 | Pending |
| B-04 | Phase 2 | Pending |
| C-01 | Phase 3 | Pending |
| C-02 | Phase 3 | Pending |
| C-03 | Phase 3 | Pending |
| C-04 | Phase 3 | Pending |
| C-05 | Phase 3 | Pending |
| D-01 | Phase 4 | Pending |
| D-02 | Phase 4 | Pending |
| D-03 | Phase 4 | Pending |
| D-04 | Phase 4 | Pending |
| D-05 | Phase 4 | Pending |
| D-06 | Phase 4 | Pending |
