#!/usr/bin/env python3
"""Deterministic production recovery/weapon parser checks; no network or UI."""
from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
def main():
    output=ROOT/'local-only/native-physics/tests/connection-recovery';output.mkdir(parents=True,exist_ok=True)
    sources=['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState']
    with tempfile.TemporaryDirectory(prefix='clock-',dir=output) as temporary:
        work=Path(temporary)
        for name in sources:shutil.copyfile(ROOT/'ios/App'/f'{name}.swift',work/f'{name}.swift')
        shutil.copyfile(ROOT/'smoke_native_connection_recovery.swift',work/'main.swift')
        subprocess.run(['xcrun','swiftc','-O','-parse-as-library','-module-cache-path',str(output/'modules'),*[str(work/f'{name}.swift') for name in sources],str(work/'main.swift'),'-o',str(work/'verify')],check=True)
        subprocess.run([str(work/'verify')],check=True)
    (output/'report.json').write_text(json.dumps({'pass':True,'scope':'Pure production-clock state and actual weapon parser; no services/UI','sources':{name:hashlib.sha256((ROOT/'ios/App'/f'{name}.swift').read_bytes()).hexdigest() for name in sources}},indent=2)+'\n')
if __name__=='__main__':main()
