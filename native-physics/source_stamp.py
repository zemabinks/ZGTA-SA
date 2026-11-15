#!/usr/bin/env python3
"""Detect a native library built for older bridge sources after a git pull."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def source_hash():
    digest = hashlib.sha256()
    paths = [ROOT / "Cargo.toml", ROOT / "Cargo.lock"]
    paths += sorted((ROOT / "src").glob("**/*.rs"))
    paths += sorted(p for p in (ROOT / "include").glob("*") if p.is_file())
    for path in paths:
        digest.update(str(path.relative_to(ROOT)).encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["check", "write"])
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    stamp = args.directory / "source-stamp.json"
    if args.mode == "write":
        args.directory.mkdir(parents=True, exist_ok=True)
        stamp.write_text(json.dumps({"sourceSHA256": source_hash(), "rust": "1.100.0"}) + "\n")
    else:
        try:
            current = json.loads(stamp.read_text())["sourceSHA256"] == source_hash()
            current = current and (args.directory / "libzgtasa_native_physics.a").is_file()
        except (OSError, ValueError, KeyError):
            current = False
        raise SystemExit(0 if current else 1)
