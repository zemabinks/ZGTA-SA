#!/usr/bin/env python3
"""Actual archived impact/rollover routines versus native event ownership."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,platform,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
    out=ROOT/'local-only/native-physics/tests/bike-ejection';out.mkdir(parents=True,exist_ok=True)
    names=['SwiftRapierWorld','NativeVehicleDamage','NativeVehicleDamageController']
    paths=[f'ios/App/{n}.swift' for n in names]+['tests/vehicles/smoke_native_bike_ejection.py','tests/vehicles/smoke_native_bike_ejection.js','tests/vehicles/smoke_native_bike_ejection.swift']
    before={p:(ROOT/p).read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out) as temp:
        work=Path(temp);fixture=work/'reference.json'
        subprocess.run(['node',str(ROOT/'tests/vehicles/smoke_native_bike_ejection.js'),str(fixture)],check=True)
        sources=[]
        for n in names:
            p=work/(n+'.swift');p.write_bytes(before[f'ios/App/{n}.swift']);sources.append(str(p))
        p=work/'main.swift';p.write_bytes(before['tests/vehicles/smoke_native_bike_ejection.swift']);sources.append(str(p))
        result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],capture_output=True,text=True)
        (out/'compile.log').write_text(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(fixture)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==v for p,v in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual archived force and rollover expressions with controlled body/contact inputs','No real collision, Renderer exit, retail runtime or rendered rider acceptance in this gate']}
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
