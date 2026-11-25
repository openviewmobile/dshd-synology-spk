#!/usr/bin/env python3
"""Generate architecture-specific Package Center source JSON from release SPKs."""
import argparse
import hashlib
import json
import os
import re
import tarfile
from pathlib import Path

def info_fields(path):
    with tarfile.open(path, "r") as tf:
        member = next((m for m in tf.getmembers() if m.name == "INFO"), None)
        if member is None:
            raise SystemExit(f"INFO not found in {path}")
        text = tf.extractfile(member).read().decode("utf-8", "replace")
    fields = {}
    for line in text.splitlines():
        m = re.match(r'^([A-Za-z0-9_]+)="?(.*?)"?$', line)
        if m:
            fields[m.group(1)] = m.group(2)
    return fields

def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--repo", default="openviewmobile/dshd-synology-spk")
    args = ap.parse_args()
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    spks = sorted(Path(args.dir).glob("*.spk"))
    if len(spks) != 2:
        raise SystemExit(f"expected 2 SPKs, found {len(spks)}")
    for spk in spks:
        info = info_fields(spk)
        arch = "armv8" if "armv8" in spk.name or info.get("arch") == "armv8" else "x86_64"
        version = info.get("version", "0.4.0")
        pkg = info.get("package", "dshd")
        desc = info.get("description", "DeepSeek Harness (dsh) AI agent workspace running natively on Synology DSM.")
        item = {
            "changelog": f"DeepSeek Harness {version} native DSM package.",
            "conflictpkgs": None,
            "deppkgs": None,
            "desc": desc,
            "distributor": "OpenView Mobile",
            "distributor_url": f"https://github.com/{args.repo}",
            "dname": info.get("displayname", "DeepSeek Harness"),
            "download_count": 0,
            "link": f"https://github.com/{args.repo}/releases/download/{args.tag}/{spk.name}",
            "maintainer": "OpenView Mobile",
            "maintainer_url": "https://github.com/openviewmobile",
            "md5": md5(spk),
            "package": pkg,
            "qinst": True,
            "qstart": True,
            "qupgrade": True,
            "recent_download_count": 0,
            "size": spk.stat().st_size,
            "snapshot": [],
            "startable": "yes",
            "thumbnail": [
                "https://raw.githubusercontent.com/openviewmobile/dshd-synology-spk/main/spk-native/PACKAGE_ICON.PNG",
                "https://raw.githubusercontent.com/openviewmobile/dshd-synology-spk/main/spk-native/PACKAGE_ICON_256.PNG",
            ],
            "thumbnail_retina": [
                "https://raw.githubusercontent.com/openviewmobile/dshd-synology-spk/main/spk-native/PACKAGE_ICON_256.PNG",
                "https://raw.githubusercontent.com/openviewmobile/dshd-synology-spk/main/spk-native/PACKAGE_ICON_256.PNG",
            ],
            "version": version,
        }
        target = outdir / ("armv8.json" if arch == "armv8" else "x86_64.json")
        target.write_text(json.dumps({"packages": [item]}, indent=2) + "\n")
        print(f"{target}: {pkg} {version} {arch} md5={item['md5']} size={item['size']}")

if __name__ == "__main__":
    main()
