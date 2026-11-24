#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Test all three native model and placement installation stages using owner-local PC media."""
import argparse
from pathlib import Path
import subprocess
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", type=Path)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    iso, archive = args.iso.resolve(strict=True), args.archive.resolve(strict=True)
    subprocess.run(["python3", "build_installer_bridge.py", "--platform", "host"], cwd=ROOT, check=True)
    out = ROOT / "local-only/research/iso-model-install"
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out, prefix="region-") as temporary:
        binary = Path(temporary) / "check"
        command = ["xcrun", "swiftc", "-parse-as-library", "-D", "ZGTA_ISO_SUITE", "-whole-module-optimization", "-j", "1", "-num-threads", "1",
                   "-module-cache-path", str(out / "modules"), "-I", "native-installer/include"]
        sources = [f"native-installer/swift/{name}.swift" for name in ["NativeISOExtraction", "NativeRawResourceSelection", "NativeVER2Archive", "NativeWorldPlacement"]]
        sources += [f"ios/App/{name}.swift" for name in ["NativeResourceManifest", "NativeResourceStore", "NativeRawResourceLease", "NativeRenderWareDFF", "NativeRenderWareTXD",
                                                         "NativeRenderWareCollision", "NativeRenderWareModel", "NativeISOModelInstallation", "NativeISOArchiveModel", "NativeISORegionInstallation"]]
        sources += [f"tests/resources/smoke_native_iso_{name}.swift" for name in ["model_install", "archive_model", "region"]]
        snapshot = [shutil.copyfile(ROOT / path, Path(temporary) / Path(path).name) for path in sources]
        command += snapshot + ["local-only/native-installer/host/libzgtasa_installer.a", "-lz", "-o", str(binary)]
        subprocess.run(command, cwd=ROOT, check=True)
        subprocess.run([str(binary), str(iso), str(archive)], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
