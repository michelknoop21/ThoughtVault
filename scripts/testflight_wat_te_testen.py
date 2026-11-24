#!/usr/bin/env python3
"""Set the Dutch TestFlight "What to Test" text on the iOS and macOS builds of a version.

Usage: scripts/testflight_wat_te_testen.py <version> [ios|macos|all] [--wait-minutes N]

The text comes from docs/testflight-wat-te-testen.txt. Its first line must be
"versie: <version>", so a text written for an older release is never posted.
Waits until App Store Connect has the requested builds (they appear a few minutes after upload).
"""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

import jwt

LOCALE = "nl-NL"
BUNDLE_ID = "com.buildmind.ThoughtVault"
TEXT_FILE = Path(__file__).resolve().parent.parent / "docs" / "testflight-wat-te-testen.txt"


def load_text(version):
    header, _, body = TEXT_FILE.read_text(encoding="utf-8").partition("\n")
    if header.strip() != f"versie: {version}":
        sys.exit(f"{TEXT_FILE.name} is voor '{header.strip()}', niet voor {version}: werk de tekst eerst bij.")
    body = body.strip()
    if not body or len(body) > 4000:
        sys.exit(f"{TEXT_FILE.name}: tekst is leeg of langer dan 4000 tekens.")
    return body


def client():
    cfg = json.load(open(os.path.expanduser("~/.appstoreconnect/config.json")))
    key = os.path.expanduser(cfg.get("key_path") or f"~/.appstoreconnect/private_keys/AuthKey_{cfg['api_key_id']}.p8")
    token = jwt.encode({"iss": cfg["api_issuer_id"], "exp": int(time.time()) + 1100, "aud": "appstoreconnect-v1"},
                       open(key).read(), algorithm="ES256", headers={"kid": cfg["api_key_id"], "typ": "JWT"})

    def call(method, path, body=None, **params):
        url = "https://api.appstoreconnect.apple.com" + path + ("?" + urllib.parse.urlencode(params) if params else "")
        req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            sys.exit(f"HTTP {e.code} {method} {path}: {e.read()[:400].decode(errors='replace')}")
    return call


def builds(call, app, build_number):
    res = call("GET", "/v1/builds", **{"filter[app]": app, "filter[version]": build_number, "include": "preReleaseVersion"})
    platform = {i["id"]: i["attributes"]["platform"] for i in res.get("included", [])}
    return {platform[b["relationships"]["preReleaseVersion"]["data"]["id"]]: b["id"] for b in res["data"]}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    version = sys.argv[1]
    wait = int(sys.argv[sys.argv.index("--wait-minutes") + 1]) if "--wait-minutes" in sys.argv else 30
    target = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else "all"
    wanted = {"ios": {"IOS"}, "macos": {"MAC_OS"}, "all": {"IOS", "MAC_OS"}}[target]
    text = load_text(version)
    call = client()
    app = call("GET", "/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"][0]["id"]
    deadline = time.time() + wait * 60
    while not wanted <= (found := builds(call, app, version.split(".")[-1])).keys() and time.time() < deadline:
        time.sleep(30)
    if not found:
        sys.exit(f"Geen builds {version} gevonden in App Store Connect na {wait} minuten.")
    for platform, build_id in sorted(found.items()):
        if platform not in wanted:
            continue
        locs = call("GET", f"/v1/builds/{build_id}/betaBuildLocalizations")["data"]
        existing = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
        if existing:
            call("PATCH", f"/v1/betaBuildLocalizations/{existing['id']}",
                 {"data": {"type": "betaBuildLocalizations", "id": existing["id"], "attributes": {"whatsNew": text}}})
        else:
            call("POST", "/v1/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations",
                 "attributes": {"locale": LOCALE, "whatsNew": text},
                 "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        print(f"{platform} {version}: Wat te testen ({LOCALE}) ingesteld")
    missing = wanted - found.keys()
    if missing:
        sys.exit(f"Nog niet in App Store Connect: {', '.join(sorted(missing))}. Draai dit later opnieuw.")


if __name__ == "__main__":
    main()
