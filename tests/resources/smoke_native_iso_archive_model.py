#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Resolve original placement models and binary IPLs from a private PC GTA3.IMG."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve(strict=True)
    subprocess.run(["python3", "build_installer_bridge.py", "--platform", "host"], cwd=ROOT, check=True)
    out = ROOT / "local-only/research/iso-model-install"
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out, prefix="archive-") as temporary:
        binary = Path(temporary) / "check"
        command = ["xcrun", "swiftc", "-parse-as-library", "-j", "1", "-num-threads", "1", "-module-cache-path", str(out / "modules"),
                   "-I", "native-installer/include"]
        command += [f"native-installer/swift/{name}.swift" for name in ["NativeISOExtraction", "NativeRawResourceSelection", "NativeVER2Archive"]]
        command += [f"ios/App/{name}.swift" for name in ["NativeRawResourceLease", "NativeRenderWareDFF", "NativeRenderWareTXD", "NativeRenderWareModel", "NativeISOArchiveModel"]]
        command += ["tests/resources/smoke_native_iso_archive_model.swift", "local-only/native-installer/host/libzgtasa_installer.a", "-lz", "-o", str(binary)]
        subprocess.run(command, cwd=ROOT, check=True)
        subprocess.run([str(binary), str(archive)], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
