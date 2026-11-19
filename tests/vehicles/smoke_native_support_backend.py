#!/usr/bin/env python3
"""Actual native client/authority/legacy-observer support protocol."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,os,subprocess,tempfile
from tests.vehicles.smoke_native_coupling_backend import NAMES,MODULES
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/support-backend'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    paths=[f'ios/App/{name}.swift' for name in NAMES]+['ios/App/NativeActorAnimation.swift']+MODULES+['tests/vehicles/smoke_native_support_backend.py','tests/vehicles/smoke_native_support_backend.js','tests/vehicles/smoke_native_support_backend.swift']
    before={p:(ROOT/p).read_bytes() for p in paths}
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);game=work/'game';data=game/'local-only/selfhost';data.mkdir(parents=True)
        for name in MODULES:(game/name).write_bytes(before[name])
        (data/'client-catalog.json').write_text(json.dumps({'vehicles':[],'homes':[]}));(data/'weapon-catalog.json').write_text(json.dumps({'items':[],'shops':[]}))
        actor=before['ios/App/NativeActorAnimation.swift'].decode();actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        (work/'main.swift').write_text('\n'.join(before[f'ios/App/{name}.swift'].decode() for name in NAMES)+'\n'+actor+'\n'+before['tests/vehicles/smoke_native_support_backend.swift'].decode())
        result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),str(work/'main.swift'),'-o',str(work/'client')],capture_output=True,text=True)
        (OUT/'compile.log').write_text(result.stdout+result.stderr);result.check_returncode()
        (work/'fixture.js').write_bytes(before['tests/vehicles/smoke_native_support_backend.js'])
        environment=dict(os.environ,ZGTA_JOIN_CODE='',ZGTA_JOIN_CODE_FILE='',ZGTA_DISCORD_CLIENT_ID='',ZGTA_DISCORD_CLIENT_SECRET='')
        result=subprocess.run(['node',str(work/'fixture.js'),str(game),str(work/'client'),str(OUT/'server-report.json')],capture_output=True,text=True,env=environment,timeout=40)
        unchanged=all((ROOT/p).read_bytes()==value for p,value in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(value).hexdigest() for p,value in before.items()},'output':result.stdout+result.stderr,
                'limits':['Synthetic platform ID and local network; no visual remote actor, retail executable, physical device or WAN claim']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
