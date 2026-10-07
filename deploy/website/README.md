# Website deployment

Public URL: https://thoughtvault.yinga.ai/ . Separate container `thoughtvault-website` on n8n01, routed by the existing `yinga-caddy` on `yinga-network`. No public container port. HTTPS is terminated by Caddy.

```sh
scripts/deploy-website.sh
python3 scripts/check-website.py
```

Deployment packages only the approved landingpage, four used image assets, SEO files and private download UI. Prototype HTML, screenshots of previous designs, test scripts and repository files are not served. Build health is checked before updating the existing Caddy host block. The script retains the prior image as `thoughtvault-website:previous` and backs up the Caddyfile before changes.

## Private downloads

The server-only `.env` contains a stable random 256-bit capability. The download page and all files on this domain are available only under `/d-<capability>/`. Anyone with that link can access them. It is not an account-based permission system. No secret is committed or baked into public HTML/JS; page access logs are disabled and private responses use `Referrer-Policy: no-referrer`, `Cache-Control: private, no-store` and `X-Robots-Tag: noindex, nofollow, noarchive, nosnippet`. The page also has a noindex meta tag. Robots excludes all `/d-` routes; the sitemap and both LLM files contain only public URLs.

The private URL is provided to the owner separately. Back up the server's `.env` securely; replacing the token invalidates old download links.

## Automatic installers

`/home/michelk/tstudio-releases` is mounted read-only at `/srv/releases`. Existing GitLab CI, GitHub Windows fallback and `scripts/upload.sh` / `scripts/upload.ps1` already upload installers and update `releases.json` in this same directory. No second copy or cron job is needed. The private page fetches the manifest without caching and builds links inside its private route. Production macOS, Windows x64 and Windows ARM64 appear per platform; a platform not built keeps its last available version. Native releases continue using their established manifest and endpoints for compatibility.

The old `n8n.prezent.nl/tstudio/download/` endpoint is outside this website container and remains available for existing native update clients. No public `/releases/` alias remains on `thoughtvault.yinga.ai`. If legacy downloads must also become private, native update authentication must first be migrated.

## SEO

Public landingpage: `index,follow`, canonical URL and Open Graph metadata. `robots.txt` allows the public site, and `sitemap.xml` contains the public landingpage. `llms.txt` is the conventional LLM description; `llm.txt` is also provided as explicitly requested. Indexing eligibility is configured; search engines decide when to index.
