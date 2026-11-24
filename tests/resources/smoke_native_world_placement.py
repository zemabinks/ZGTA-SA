#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Check text and streamed world placement with independently authored fixtures on a Mac."""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def main():
    subprocess.run(["python3", "build_installer_bridge.py", "--platform", "host"], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix="zgta-world-placement-") as temporary:
        binary = Path(temporary) / "placements"
        sources = [f"native-installer/swift/{name}.swift" for name in (
            "NativeISOExtraction", "NativeRawResourceSelection", "NativeVER2Archive",
            "NativeWorldPlacement", "NativeWorldStreamIPL",
        )]
        subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-j", "1", "-num-threads", "1",
            "-D", "ZGTA_PLACEMENT_SUITE", "-I", "native-installer/include", *sources,
            "tests/resources/smoke_native_world_stream_ipl.swift",
            "tests/resources/smoke_native_world_placement.swift",
            "local-only/native-installer/host/libzgtasa_installer.a", "-lz", "-o", str(binary),
        ], cwd=ROOT, check=True)
        subprocess.run([str(binary)], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
