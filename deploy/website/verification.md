# Live verification, 7 October 2026

- `scripts/deploy-website.sh`: Docker build and Compose health check succeeded; Caddy configuration validated and reloaded.
- https://thoughtvault.yinga.ai/ : HTTP 200 with verified TLS, canonical and index/follow metadata. Browser interaction check at 1440px passed; no browser console errors.
- Public robots, sitemap, llms.txt and llm.txt: HTTP 200 and no private capability embedded.
- Private page: HTTP 200 HTML with noindex meta, noindex response header, no-store cache policy and no-referrer policy.
- Anonymous guessed download routes and old `/releases/` alias on this domain: HTTP 404.
- Private installer range requests: HTTP 206 with noindex headers. macOS 1.0.242, Windows x64 1.0.124 and ARM64 1.0.42 are the existing available releases on the server. No claim that these are rebuilt with the new icon.
- Browser private-page check: all three installer links stay under the capability route; manifest loads successfully; no console errors.
- Live-mount positive control: uploaded a temporary file to the release directory, retrieved identical contents through the private route without rebuilding, then removed the test file.
- `bash -n scripts/deploy-website.sh`, Python syntax check and `python3 scripts/check-website.py`: passed.

Installer publication remains driven by existing upload scripts/CI. Native binaries were not rebuilt as part of the website deployment. Existing update URLs on n8n.prezent.nl remain outside this container.
