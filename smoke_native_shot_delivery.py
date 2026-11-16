#!/usr/bin/env python3
"""Verify synchronous native muzzle-event ownership without UI or networking."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent

def main():
    output = ROOT / 'local-only/native-physics/tests/core-shots'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='run-', dir=output) as temporary:
        snapshot = Path(temporary)
        shutil.copyfile(ROOT / 'smoke_native_shot_delivery.swift', snapshot / 'main.swift')
        sources = []
        for name in ['ServerAddress', 'NativeInventoryPrediction', 'NativeOriginalWorldArsenal', 'NativeWeaponState', 'NativeWeaponShotDelivery']:
            target = snapshot / f'{name}.swift'
            shutil.copyfile(ROOT / 'ios/App' / target.name, target)
            sources.append(target)
        subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(output / 'modules'),
                        *map(str, sources), str(snapshot / 'main.swift'), '-o', str(snapshot / 'verify')], check=True)
        subprocess.run([str(snapshot / 'verify')], check=True)

if __name__ == '__main__':
    main()
