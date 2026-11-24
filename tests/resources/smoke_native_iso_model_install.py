#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Verify a user-supplied PC San Andreas installation ISO in an isolated store."""
import argparse
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", type=pathlib.Path)
    args = parser.parse_args()
    source = args.iso.resolve(strict=True)
    if not source.is_file():
        parser.error("Choose the ISO file.")
    subprocess.run(["python3", "build_installer_bridge.py", "--platform", "host"], cwd=ROOT, check=True)
    work = ROOT / "local-only" / "research" / "iso-model-install"
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work, prefix="build-") as temporary:
        binary = pathlib.Path(temporary) / "check"
        command = ["xcrun", "swiftc", "-parse-as-library", "-j", "1", "-num-threads", "1",
                   "-module-cache-path", str(work / "modules"), "-I", "native-installer/include",
                   "native-installer/swift/NativeISOExtraction.swift", "native-installer/swift/NativeRawResourceSelection.swift"]
        command += [f"ios/App/{name}.swift" for name in ["NativeResourceManifest", "NativeResourceStore", "NativeRenderWareDFF",
                                                          "NativeRenderWareTXD", "NativeRenderWareModel", "NativeISOModelInstallation"]]
        command += ["tests/resources/smoke_native_iso_model_install.swift", "local-only/native-installer/host/libzgtasa_installer.a",
                    "-lz", "-o", str(binary)]
        subprocess.run(command, cwd=ROOT, check=True)
        subprocess.run([str(binary), str(source)], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
