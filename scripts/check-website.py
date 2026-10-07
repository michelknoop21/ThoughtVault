#!/usr/bin/env python3
"""Live deployment check; reads the private capability from SSH without logging it."""
import json
import os
import subprocess
import urllib.error
import urllib.request

base = os.environ.get('SITE_URL', 'https://thoughtvault.yinga.ai')
server = os.environ.get('SITE_SERVER', 'n8n01')
secret = subprocess.check_output(['ssh', '-o', 'BatchMode=yes', server,
    "sed -n 's/^DOWNLOAD_TOKEN=//p' /home/michelk/thoughtvault-website/.env"], text=True).strip()
assert len(secret) == 64 and all(c in '0123456789abcdef' for c in secret)

def get(path, headers=None):
    request = urllib.request.Request(base + path, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, response.headers, response.read(200_000)
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read(200_000)

for path in ['/', '/robots.txt', '/sitemap.xml', '/llms.txt', '/llm.txt']:
    status, headers, body = get(path)
    assert status == 200, (path, status)
    assert secret.encode() not in body, 'Private capability leaked into public content'
    assert 'noindex' not in headers.get('X-Robots-Tag', ''), path
status, headers, public = get('/')
assert b'content="index,follow"' in public
assert b'rel="canonical" href="https://thoughtvault.yinga.ai/"' in public
assert b'private' not in get('/sitemap.xml')[2]
for path in ['/download/', '/releases/', '/releases/releases.json', '/releases.json', '/d-'+'0'*64+'/']:
    assert get(path)[0] == 404, 'Unexpected public download route: ' + path
private = '/d-' + secret + '/'
status, headers, body = get(private)
assert status == 200 and 'text/html' in headers.get('Content-Type','')
assert 'noindex' in headers.get('X-Robots-Tag','')
assert 'no-store' in headers.get('Cache-Control','')
assert headers.get('Referrer-Policy') == 'no-referrer'
assert b'noindex,nofollow,noarchive,nosnippet' in body
status, headers, body = get(private+'releases.json')
assert status == 200 and 'noindex' in headers.get('X-Robots-Tag','')
manifest = json.loads(body)
for key in ['macos', 'windows_x64', 'windows_arm64']:
    entry = manifest.get(key)
    if not entry:
        continue
    filename = entry['filename']
    status, headers, data = get(private+filename, {'Range':'bytes=0-31'})
    assert status == 206 and len(data) == 32, key
    assert 'noindex' in headers.get('X-Robots-Tag',''), key
    assert get('/'+filename)[0] == 404, key
    print('PASS private installer:', key, entry['version'])
assert get(private+'../releases.json')[0] == 404
print('PASS public SEO, private page/files, noindex, range downloads, and unlisted routes')
