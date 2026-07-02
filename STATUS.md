# STATUS — ThoughtVault

_Laatste update: 2026-05-06_

## Waar was ik

Bas's hardnekkige Windows 422 upload-bug afgevangen via een brede client-side hardening. Hypothese dat python-multipart 0.0.17 de schuldige was is empirisch weerlegd (100 MB reqwest-multipart parseert correct op de productiebackend). De fix sluit nu meerdere mogelijke oorzaken tegelijk: copy-to-temp vóór upload, in-memory `Part::bytes` voor files ≤200 MB, gehard reqwest-config (UA, tcp_nodelay, no_proxy, http1_only, fresh connectie per upload), WAV magic-byte check, SHA-256 prefix als `X-Upload-Sha256` voor client↔server log-correlatie. Eerste pipeline (v1.0.123) faalde op een latente YAML-syntax-bug uit commit `be88f63`; opgelost door PowerShell heredoc te vervangen door array+join. v1.0.124 is de daadwerkelijke productie-tag.

## Volgende stap

Wachten op productie pipeline #19652+ voor v1.0.124. Als groen: Bas laten upgraden naar 1.0.124 (auto-update of handmatig via `https://n8n.prezent.nl/tstudio/download/`) en de eerste echte 90+ MB combined recording laten testen. Bij eventuele volgende failure direct `docker logs n8n_transcript_studio | grep VALIDATION-422` op `michelk@3.69.205.209` checken — `sha=` veld levert nu definitief bewijs of de body intact aankwam.

## Open blockers

- Geen blockers; afwachten op CI groen voor v1.0.124.

## Recente sessies

- **2026-05-06** — Upload pipeline hardening v1.0.124, YAML CI fix, backend `[VALIDATION-422]` log uitgebreid met `sha=`/`client=`. Backend deployed op 3.69.205.209.
- **2026-04-03** — macOS notule detail-pagina aligned met Windows: inline titel editing, compacte unified toolbar, oude tab bar verwijderd.
- **2026-04-02** — Admin task monitoring username display, macOS detail header parity met Windows, zakelijk profiel CSS upgrade.
- **2026-03-20** — Screen capture permission flow vereenvoudigd (DEC-051); upload retry refactor naar reprocess pattern (DEC-052).
- **2026-03-17** — Never-auto-logout na auth (DEC-048), upload queue progress banner, gestructureerde error codes (DEC-049).
