#!/usr/bin/env python3
"""Deterministic production-state reconciliation tests; no service or UI."""
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent

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
    run('smoke_native_inventory_prediction.swift',['NativeInventoryPrediction'],output)
    run('smoke_native_ammo_reconciliation.swift',['ServerAddress','NativeInventoryPrediction','NativeWeaponState','NativeWeaponShotDelivery'],output)
if __name__=='__main__':main()
