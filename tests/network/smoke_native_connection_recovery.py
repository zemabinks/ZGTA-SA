#!/usr/bin/env python3
"""Deterministic production recovery/weapon parser checks; no network or UI."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
    output=ROOT/'local-only/native-physics/tests/connection-recovery';output.mkdir(parents=True,exist_ok=True)
    sources=['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState']
    with tempfile.TemporaryDirectory(prefix='clock-',dir=output) as temporary:
        work=Path(temporary)
        for name in sources:shutil.copyfile(ROOT/'ios/App'/f'{name}.swift',work/f'{name}.swift')
        shutil.copyfile(ROOT/'tests/network/smoke_native_connection_recovery.swift',work/'main.swift')
        subprocess.run(['xcrun','swiftc','-O','-parse-as-library','-module-cache-path',str(output/'modules'),*[str(work/f'{name}.swift') for name in sources],str(work/'main.swift'),'-o',str(work/'verify')],check=True)
        subprocess.run([str(work/'verify')],check=True)
    (output/'report.json').write_text(json.dumps({'pass':True,'scope':'Pure production-clock state and actual weapon parser; no services/UI','sources':{name:hashlib.sha256((ROOT/'ios/App'/f'{name}.swift').read_bytes()).hexdigest() for name in sources}},indent=2)+'\n')
if __name__=='__main__':main()
