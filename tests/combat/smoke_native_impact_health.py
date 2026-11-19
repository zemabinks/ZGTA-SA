#!/usr/bin/env python3
"""Actual archived quiet/fall damage versus ordered native health prediction."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
def main():
    out=ROOT/'local-only/native-physics/tests/impact-health';out.mkdir(parents=True,exist_ok=True)
    paths=['ios/App/NativeMultiplayerClient.swift','tests/combat/smoke_native_impact_health.py','tests/combat/smoke_native_impact_health.js','tests/combat/smoke_native_impact_health.swift']
    before={p:(ROOT/p).read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out) as temp:
        work=Path(temp);fixture=work/'reference.json'
        subprocess.run(['node',str(ROOT/'tests/combat/smoke_native_impact_health.js'),str(fixture)],check=True)
        (work/'main.swift').write_text(before[paths[3]].decode().replace('// ACTUAL_PREDICTION',function(before[paths[0]].decode(),'struct NativeHealthPrediction {')))
        result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
        (out/'compile.log').write_text(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(fixture)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==v for p,v in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual archived hurt method with controlled integer crash/fall inputs and real native prediction','No fractional retail damage balance, physical collision, rendering or transport in this gate']}
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
