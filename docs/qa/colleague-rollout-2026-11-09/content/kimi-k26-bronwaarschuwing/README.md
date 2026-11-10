# Kimi K2.6, broncontrole als waarschuwing

Opname van 10 november 2026 voor feat/bronwaarschuwing: de broncontrole (`auditSource`) wijst niet meer af maar geeft een waarschuwing, en `auditNotule` blijft de poort.

- `prepare` met `TV_AUDIT_MODEL=kimi-k2.6` schreef de twaalf requests. Alle twaalf zijn bytegelijk aan `../alternate-kimi-k26/`.
- Elf antwoorden zijn daarom ongewijzigd overgenomen uit `../alternate-kimi-k26/` (zelfde request, eerdere echte waarneming).
- Eén antwoord is nieuw: `opname10_ambigue_bron_numerieke_invulling.response.txt`, de inhoudsaudit van Opname10. Die call bestond eerder niet, omdat de broncontrole daar stopte. Verzonden als exacte requestbody naar Ollama Cloud, één keer, zonder retry; zie `opname10-transport.json`.
- `replay` met dezelfde map en hetzelfde model: 6 van 6 geslaagd. Opname10 wordt nu door de inhoudsaudit afgewezen ("De inhoudscontrole is onzeker").
