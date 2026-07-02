#!/usr/bin/env python3
"""Create a GitLab Release via the API. Called from .gitlab-ci.yml deploy job."""
import json, os, sys, urllib.request

with open("/tmp/release-notes.txt") as f:
    description = f.read().strip()

tag = os.environ["CI_COMMIT_TAG"]
version = os.environ["VERSION"]
channel = os.environ["CHANNEL"]
dmg = os.environ.get("DMG_NAME", "")
msi = os.environ.get("MSI_X64_NAME", "")
apk = os.environ.get("APK_NAME", "")
api_url = os.environ["CI_API_V4_URL"]
project_id = os.environ["CI_PROJECT_ID"]
job_token = os.environ["CI_JOB_TOKEN"]

title = f"ThoughtVault Dev v{version}" if channel == "dev" else f"ThoughtVault v{version}"

base = "https://n8n.prezent.nl/tstudio/download"
links = []
if dmg:
    links.append({"name": f"macOS — {dmg}", "url": f"{base}/{dmg}", "link_type": "other"})
if msi:
    links.append({"name": f"Windows — {msi}", "url": f"{base}/{msi}", "link_type": "other"})
if apk:
    links.append({"name": f"Android — {apk}", "url": f"{base}/{apk}", "link_type": "other"})

data = {
    "tag_name": tag,
    "name": title,
    "description": description,
    "assets": {"links": links}
}

req = urllib.request.Request(
    f"{api_url}/projects/{project_id}/releases",
    data=json.dumps(data).encode(),
    headers={"JOB-TOKEN": job_token, "Content-Type": "application/json"},
    method="POST"
)
try:
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
        print(f"GitLab Release created: {result.get('name', tag)}")
except Exception as e:
    print(f"Release creation failed: {e}")
    print("Check CI_JOB_TOKEN permissions or add a project access token")
    sys.exit(1)
