#!/usr/bin/env python3
"""Verify synchronous native muzzle-event ownership without UI or networking."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    output = ROOT / 'local-only/native-physics/tests/core-shots'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='run-', dir=output) as temporary:
        snapshot = Path(temporary)
        shutil.copyfile(ROOT / 'tests/combat/smoke_native_shot_delivery.swift', snapshot / 'main.swift')
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
