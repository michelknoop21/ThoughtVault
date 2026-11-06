# Vaste inhoudsproef voor kandidaat 1.0.300

Status: alleen voorbereid, geen echte modelresponses en geen inhoudelijke PASS.
Broncommit `fef23dd1d8d5df093b1eb17bd7c511e34662b22d`.
De vier requestbestanden bevatten fictieve proefinhoud, geen gebruikersaudio,
providerheaders of keys. De interne voorbereidingsfouten in PREPARATION.json
zijn verwacht; ze zijn geen modelafwijzingen.

Volg de bestaande [prepare/replay-instructie](../../../../windows/src/services/__tests__/qa-short-quality/README.md).
Behoud ieder antwoord eenmaal onder de exacte requestnaam met `.response.txt`
in plaats van `.request.json`. Geen retry, prompt-/modelwissel of nieuwe keyroute.
Een transportfout afzonderlijk rapporteren. Replay vanaf `windows/` met
`TV_AUDIT_MODE=replay` en `TV_AUDIT_DIR` naar deze map.
