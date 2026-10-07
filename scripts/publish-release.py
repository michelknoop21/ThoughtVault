#!/usr/bin/env python3
"""Publish already signed artifacts; called on the release server by every uploader."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from datetime import datetime, timezone
import xml.etree.ElementTree as ET

BASE = "https://thoughtvault.yinga.ai/releases/"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def atomic_write(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def publish(directory, staging, version, channel):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version): raise ValueError("Invalid version")
    if channel not in ("production", "dev"): raise ValueError("Invalid channel")
    prefix = "ThoughtVault" if channel == "production" else "ThoughtVault-Dev"
    key_prefix = "" if channel == "production" else "dev_"
    feed_name = "stable" if channel == "production" else "dev"
    entries = []
    # Validate the entire batch before making anything visible.
    for platform, name in (("windows_x64", f"{prefix}_{version}_x64.msi"),
                           ("windows_arm64", f"{prefix}_{version}_arm64.msi"),
                           ("macos", f"{prefix}-{version}.dmg"),
                           ("android", f"{prefix}-{version}.apk")):
        artifact = staging / name
        if not artifact.is_file(): continue
        if artifact.stat().st_size == 0: raise ValueError("Empty artifact")
        metadata = None
        if platform.startswith("windows"):
            metadata = artifact.with_suffix(".msi.sig").read_text().strip()
            if not base64.b64decode(metadata, validate=True): raise ValueError("Invalid MSI signature")
        elif platform == "macos":
            metadata = json.loads(Path(str(artifact) + ".sparkle.json").read_text())
            if metadata.get("notarized") is not True: raise ValueError("macOS release must be notarized")
            if len(base64.b64decode(metadata["signature"], validate=True)) != 64: raise ValueError("Invalid Sparkle signature")
            if not str(metadata["build_number"]).isdigit(): raise ValueError("Invalid build number")
        entries.append((platform, artifact, metadata))
    if not entries: raise ValueError("No current-version artifacts")
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".publish.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        manifest_path = directory / "releases.json"
        data = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        windows_path = directory / "windows" / f"{feed_name}.json"
        windows = json.loads(windows_path.read_text()) if windows_path.exists() else {}
        for platform, artifact, metadata in entries:
            old = data.get(key_prefix + platform, {}).get("version", "0.0.0")
            if tuple(map(int, old.split('.'))) > tuple(map(int, version.split('.'))):
                raise ValueError("Refusing to publish an older release")
            dest = directory / artifact.name
            if dest.exists() and hashlib.sha256(dest.read_bytes()).digest() != hashlib.sha256(artifact.read_bytes()).digest():
                raise ValueError("Release filenames are immutable")
        for platform, artifact, metadata in entries:
            atomic_write(directory / artifact.name, artifact.read_bytes())
            entry = {"version": version, "filename": artifact.name,
                     "url": "/tstudio/download/" + artifact.name,
                     "download_url": BASE + artifact.name,
                     "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}
            data[key_prefix + platform] = entry
            if platform.startswith("windows"):
                if windows.get("version") != version: windows = {"platforms": {}}
                windows.update(version=version, notes=f"ThoughtVault {version}", pub_date=datetime.now(timezone.utc).isoformat())
                target = "windows-x86_64" if platform == "windows_x64" else "windows-aarch64"
                windows["platforms"][target] = {"url": entry["download_url"], "signature": metadata}
                atomic_write(directory / (artifact.name + ".sig"), (metadata + "\n").encode())
                if platform == "windows_x64": data[key_prefix + "windows"] = entry
            elif platform == "macos":
                rss = ET.Element("rss", version="2.0")
                chan = ET.SubElement(rss, "channel")
                ET.SubElement(chan, "title").text = "ThoughtVault"
                item = ET.SubElement(chan, "item")
                ET.SubElement(item, "title").text = f"ThoughtVault {version}"
                ET.SubElement(item, "enclosure", {"url": entry["download_url"], "length": str(artifact.stat().st_size),
                    "type": "application/octet-stream", f"{{{SPARKLE}}}version": str(metadata["build_number"]),
                    f"{{{SPARKLE}}}shortVersionString": version, f"{{{SPARKLE}}}edSignature": metadata["signature"]})
                atomic_write(directory / "macos" / f"{feed_name}.xml", ET.tostring(rss, encoding="utf-8", xml_declaration=True))
                # Legacy Macs read this global field: it must track the macOS artifact.
                data[key_prefix + "latest_version"] = version
        if any(p.startswith("windows") for p, _, _ in entries):
            atomic_write(windows_path, (json.dumps(windows, indent=2) + "\n").encode())
        atomic_write(manifest_path, (json.dumps(data, indent=2) + "\n").encode())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--staging", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--channel", choices=["production", "dev"], required=True)
    args = parser.parse_args()
    publish(args.directory, args.staging, args.version, args.channel)
