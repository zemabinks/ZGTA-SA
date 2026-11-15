#!/usr/bin/env python3
"""Actual fixed motor/core, Renderer handoffs and local animation cadence gate."""
from pathlib import Path
import hashlib
import platform
import subprocess
import tempfile
from smoke_native_climb_runtime import function

ROOT = Path(__file__).resolve().parent


def main():
    renderer = (ROOT / "ios/App/NativeWorldRenderer.swift").read_text()
    start = renderer.index("        if !driving, let character {\n            lastFootVelocity =")
    publish = renderer[start:renderer.index("\n        if let characterOutput", start)]
    start = renderer.index("motion: { [self] step,state,intended in")
    boundary = renderer[renderer.index("\n", start):renderer.index("                    if let held=climbingMotion", start)]
    methods = "\n".join(function(renderer, marker) for marker in
                        ["private func swimmingMotion(", "private func personalFlightMotion(",
                         "private var personalFlightAnimationInput:", "func cancelGameplayInput("])
    skeletal = (ROOT / "ios/App/NativeSkeletalActor.swift").read_text()
    source = skeletal[:skeletal.index("struct NativeSkinVertex")].replace("import Metal", "")
    source += "\nfinal class NativeSkeletalActor {\n" + skeletal[skeletal.index("    struct OriginalAim {"):skeletal.index("    struct Pose {")] + "}\n"
    for name in ["NativeGunAnimation", "NativeSwimAnimation", "NativeFlightAnimation", "NativeFootAnimation",
                 "NativePersonalFlightController", "NativeFootLocomotion", "NativeHeadingContinuity",
                 "NativeSprintController", "NativeSwimController", "NativeMelee"]:
        source += "\n" + (ROOT / "ios/App" / (name + ".swift")).read_text()
    source += (ROOT / "smoke_native_fixed_velocity.swift").read_text().replace(
        "// ACTUAL_PUBLISH", publish).replace("// ACTUAL_MOTION_BOUNDARY", boundary).replace("// ACTUAL_HANDOFFS", methods)
    output = ROOT / "local-only/research/fixed-velocity"
    output.mkdir(parents=True, exist_ok=True)
    (output / "runtime-source.swift").write_text(source)
    (output / "renderer-methods.sha256").write_text(hashlib.sha256((publish + boundary + methods).encode()).hexdigest() + "\n")
    with tempfile.TemporaryDirectory(prefix="fixed-velocity-", dir=output) as directory:
        work = Path(directory)
        (work / "main.swift").write_text(source)
        sources = [ROOT / "ios/App" / (name + ".swift") for name in
                   ["SwiftRapierWorld", "NativeCharacterMotor", "NativeRapierCharacterQueries",
                    "NativeCharacterController", "NativeGameInput"]]
        subprocess.run(["swiftc", "-parse-as-library", "-whole-module-optimization", "-Onone", "-module-cache-path",
                        "/private/tmp/zgtasa-core-swift-modules", "-I", str(ROOT / "native-physics/include"),
                        *map(str, sources), str(work / "main.swift"), "-L",
                        str(ROOT / f"local-only/native-physics/macos-{platform.machine()}"),
                        "-lzgtasa_native_physics", "-framework", "Security", "-framework", "CoreFoundation",
                        "-o", str(work / "verify")], check=True)
        subprocess.run([str(work / "verify"), str(ROOT)], check=True)


if __name__ == "__main__":
    main()
