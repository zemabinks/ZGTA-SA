#!/usr/bin/env python3
"""Actual archived support-buffer/ray comparison; original data remains local."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/vehicle-treads'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=['ios/App/NativeVehicleTread.swift','tests/vehicles/smoke_native_vehicle_treads.py','tests/vehicles/smoke_native_vehicle_treads.js','tests/vehicles/smoke_native_vehicle_treads.swift','tools/assets/prepare_native_vehicle_treads.js']
    before={p:(ROOT/p).read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);reference=work/'reference.json'
        subprocess.run(['node',str(ROOT/'tests/vehicles/smoke_native_vehicle_treads.js'),str(reference)],cwd=ROOT,check=True)
        (work/'NativeVehicleTread.swift').write_bytes(before[paths[0]])
        (work/'main.swift').write_bytes(before['tests/vehicles/smoke_native_vehicle_treads.swift'])
        compile=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),str(work/'NativeVehicleTread.swift'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
        (OUT/'compile.log').write_text(compile.stdout+compile.stderr);compile.check_returncode()
        result=subprocess.run([str(work/'verify'),str(ROOT),str(reference)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==data for p,data in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,
                'sources':{p:hashlib.sha256(data).hexdigest() for p,data in before.items()},'output':result.stdout+result.stderr,
                'limits':['Actual original query equations and local original data; no original retail executable, GPU, input or live-scene claim','Component query/pose gate; character carrying integration has separate acceptance']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
