#!/bin/bash
# Deploy the public website and private downloads independently of native releases.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SITE_SERVER="${SITE_SERVER:-n8n01}"
SITE_DIR="/home/michelk/thoughtvault-website"
SITE_STAGE=$(mktemp -d)
trap 'rm -rf "$SITE_STAGE"' EXIT
mkdir -p "$SITE_STAGE/docs/design/high-end-yinga/assets" "$SITE_STAGE/deploy"
cp -R "$ROOT_DIR/deploy/website" "$SITE_STAGE/deploy/website"
cp "$ROOT_DIR/deploy/website/compose.yaml" "$SITE_STAGE/compose.yaml"
for file in index.html landing.css landing.js; do
    cp "$ROOT_DIR/docs/design/high-end-yinga/$file" "$SITE_STAGE/docs/design/high-end-yinga/"
done
for file in thoughtvault-mark.png yinga-logo.svg macos-recording.png macos-processing.png; do
    cp "$ROOT_DIR/docs/design/high-end-yinga/assets/$file" "$SITE_STAGE/docs/design/high-end-yinga/assets/"
done
cat > "$SITE_STAGE/.dockerignore" <<'IGNORE'
.env
*.tar.gz
IGNORE
tar -czf "$SITE_STAGE/site.tar.gz" -C "$SITE_STAGE" .dockerignore compose.yaml deploy docs
ssh -o BatchMode=yes "$SITE_SERVER" "mkdir -p $SITE_DIR"
scp "$SITE_STAGE/site.tar.gz" "$SITE_SERVER:$SITE_DIR/site.tar.gz"
ssh -o BatchMode=yes "$SITE_SERVER" 'bash -s' <<'REMOTE'
set -euo pipefail
cd /home/michelk/thoughtvault-website
if [ ! -f .env ]; then
    umask 077
    printf 'DOWNLOAD_TOKEN=%s\n' "$(openssl rand -hex 32)" > .env
fi
chmod 600 .env
tar -xzf site.tar.gz
rm site.tar.gz
if docker image inspect thoughtvault-website:local >/dev/null 2>&1; then
    docker tag thoughtvault-website:local thoughtvault-website:previous
fi
docker compose build --pull
docker compose up -d --wait
# Change only this site's existing virtual host. Preserve all other host blocks.
python3 - <<'PY'
from pathlib import Path
from datetime import datetime
p=Path('/home/michelk/yinga/caddy/Caddyfile')
s=p.read_text()
marker='thoughtvault.yinga.ai {'
block='thoughtvault.yinga.ai {\n    reverse_proxy thoughtvault-website:80\n}\n'
if marker in s:
    start=s.index(marker)
    depth=0
    for i in range(s.index('{',start),len(s)):
        depth += (s[i]=='{') - (s[i]=='}')
        if depth==0:
            end=i+1
            break
    else:
        raise RuntimeError('Unbalanced Caddyfile')
    updated=s[:start]+block.rstrip()+s[end:]
else:
    updated=s+'\n'+block
if updated!=s:
    backup=p.with_name('Caddyfile.thoughtvault-'+datetime.now().strftime('%Y%m%d%H%M%S'))
    backup.write_text(s)
    p.write_text(updated)
PY
docker exec yinga-caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker exec yinga-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
printf 'Website deployed: https://thoughtvault.yinga.ai/\n'
REMOTE
