#!/usr/bin/env python3
"""Original coordinator query replay; component physics has separate gates."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/moving-support'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=['ios/App/NativeMovingSupport.swift','tests/vehicles/smoke_native_moving_support.py','tests/vehicles/smoke_native_moving_support.js','tests/vehicles/smoke_native_moving_support.swift','ios/App/NativeFootLocomotion.swift']
    before={p:(ROOT/p).read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);reference=work/'reference.json'
        subprocess.run(['node',str(ROOT/'tests/vehicles/smoke_native_moving_support.js'),str(reference)],cwd=ROOT,check=True)
        (work/'NativeMovingSupport.swift').write_bytes(before[paths[0]])
        (work/'NativeFootLocomotion.swift').write_bytes(before['ios/App/NativeFootLocomotion.swift'])
        (work/'main.swift').write_bytes(before['tests/vehicles/smoke_native_moving_support.swift'])
        compile=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),str(work/'NativeMovingSupport.swift'),str(work/'NativeFootLocomotion.swift'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
        (OUT/'compile.log').write_text(compile.stdout+compile.stderr);compile.check_returncode()
        result=subprocess.run([str(work/'verify'),str(reference)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==data for p,data in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sources':{p:hashlib.sha256(data).hexdigest() for p,data in before.items()},'output':result.stdout+result.stderr,
                'limits':['Actual archived coordinator executed with controlled body snapshots, broad-phase responses and synthetic tread triangles; not a full-world physical integration or retail test','All six frame rates compare the same original state-machine clock and inputs; a separate native controller integration gate is required']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
