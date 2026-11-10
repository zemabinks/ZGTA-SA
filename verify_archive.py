#!/usr/bin/env python3
"""Verify every locally archived file against the private manifest."""

from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parent / "local-only"
manifest = root / "manifest.json"
if not manifest.is_file():
    sys.exit("No local archive manifest; run python3 archive_site.py first")

rows = json.loads(manifest.read_text()).get("files", {})
ok = missing = mismatch = unavailable = total = 0
for url, row in rows.items():
    if row.get("status") != "ok":
        unavailable += 1
        continue
    path = root / row["path"]
    if not path.is_file():
        print("Missing:", path)
        missing += 1
        continue
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            digest.update(chunk)
            size += len(chunk)
    if size != row["bytes"] or digest.hexdigest() != row["sha256"]:
        print("Mismatch:", url)
        mismatch += 1
    else:
        ok += 1
        total += size
print(f"Verified {ok} files ({total} bytes); {unavailable} unavailable at source; {missing} missing; {mismatch} mismatched")
sys.exit(1 if missing or mismatch else 0)
