#!/usr/bin/env python3
"""Deterministic production-state reconciliation tests; no service or UI."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]

def run(test,sources,output):
    with tempfile.TemporaryDirectory(prefix='run-',dir=output) as temporary:
        snapshot=Path(temporary)
        for name in sources:
            shutil.copyfile(ROOT/'ios/App'/f'{name}.swift',snapshot/f'{name}.swift')
        shutil.copyfile(ROOT/test,snapshot/'main.swift')
        args=['xcrun','swiftc','-O','-parse-as-library','-module-cache-path',str(output/'modules')]
        args += [str(snapshot/f'{name}.swift') for name in sources]
        args += [str(snapshot/'main.swift'),'-o',str(snapshot/'verify')]
        subprocess.run(args,check=True);subprocess.run([str(snapshot/'verify')],check=True)

def main():
    output=ROOT/'local-only/native-physics/tests/ammo-reconciliation';output.mkdir(parents=True,exist_ok=True)
    run('tests/combat/smoke_native_inventory_prediction.swift',['NativeInventoryPrediction'],output)
    run('tests/combat/smoke_native_ammo_reconciliation.swift',['ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeWeaponShotDelivery'],output)
if __name__=='__main__':main()
