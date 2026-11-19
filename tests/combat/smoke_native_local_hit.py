#!/usr/bin/env python3
"""Actual archived hurt decisions versus independent native response model."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/local-hit'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=['ios/App/NativeLocalHitReaction.swift','ios/App/NativePedestrianReaction.swift','tests/combat/smoke_native_local_hit.py','tests/combat/smoke_native_local_hit.js','tests/combat/smoke_native_local_hit.swift']
    before={p:(ROOT/p).read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);reference=work/'reference.json'
        subprocess.run(['node',str(ROOT/'tests/combat/smoke_native_local_hit.js'),str(reference)],cwd=ROOT,check=True)
        sources=[]
        for name in paths[:2]:p=work/Path(name).name;p.write_bytes(before[name]);sources.append(str(p))
        (work/'main.swift').write_bytes(before['tests/combat/smoke_native_local_hit.swift']);sources.append(str(work/'main.swift'))
        result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),*sources,'-o',str(work/'verify')],capture_output=True,text=True)
        (OUT/'compile.log').write_text(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(reference)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==value for p,value in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,
                'limits':['Actual archived hurt method and reaction helper, controlled actor/animator/effect callbacks and direction bins','No damage authority, rendered animation, fire/spray effects, style-specific counterblows, multiplayer transport or retail executable acceptance']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
