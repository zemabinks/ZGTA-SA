#!/usr/bin/env python3
"""Verify every locally archived file against the private manifest."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))


from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[2] / "local-only"
manifest = root / "manifest.json"
if not manifest.is_file():
    sys.exit("No local archive manifest; run python3 tools/archive/archive_site.py first")

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
