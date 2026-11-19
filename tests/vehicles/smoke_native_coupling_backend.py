#!/usr/bin/env python3
"""Actual native URLSession to self-host authority and independent legacy WS observer."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,os,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/coupling-backend'
NAMES=['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeShotTargeting','NativeStreamShotClaims','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPLocalVitals','NativeMultiplayerClient']
MODULES=['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js', 'player_placement.js','vehicle_coupling.js']
TESTS=['tests/vehicles/smoke_native_coupling_backend.py','tests/vehicles/smoke_native_coupling_backend.js','tests/vehicles/smoke_native_coupling_backend.swift']
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 paths=[f'ios/App/{name}.swift' for name in NAMES]+['ios/App/NativeActorAnimation.swift']+MODULES+TESTS
 inputs={name:(ROOT/name).read_bytes() for name in paths}
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temporary:
  work=Path(temporary);game=work/'game';data=game/'local-only/selfhost';data.mkdir(parents=True)
  for name in MODULES:(game/name).write_bytes(inputs[name])
  definition=lambda ident,kind,**extra:dict(id=ident,kind=kind,minimum=[-1,-2,-1],frontAnchor=[0,.5,-2],rearAnchor=None,trailerAnchor=None,targets=[],**extra)
  tractor=definition(8001,'car');tractor.update(rearAnchor=[0,.5,3],targets=[8002])
  trailer=definition(8002,'trailer');trailer.update(rearAnchor=[0,.5,3],trailerAnchor=[0,.5,-2],targets=[8002])
  (data/'coupling-catalog.json').write_text(json.dumps({'version':1,'models':{8001:tractor,8002:trailer}}))
  (data/'client-catalog.json').write_text(json.dumps({'vehicles':[{'model':8001,'name':'Synthetic tractor','price':1,'dealers':['fixture'],'type':'car','colors':[0,0]}],'homes':[]}))
  (data/'weapon-catalog.json').write_text(json.dumps({'items':[],'shops':[]}))
  actor=inputs['ios/App/NativeActorAnimation.swift'].decode();actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
  (work/'main.swift').write_text('\n'.join(inputs[f'ios/App/{name}.swift'].decode() for name in NAMES)+'\n'+actor+'\n'+inputs[TESTS[2]].decode())
  compiled=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),str(work/'main.swift'),'-o',str(work/'client')],capture_output=True,text=True)
  (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
  if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
  (work/'fixture.js').write_bytes(inputs[TESTS[1]])
  environment=dict(os.environ,ZGTA_JOIN_CODE='',ZGTA_JOIN_CODE_FILE='',ZGTA_DISCORD_CLIENT_ID='',ZGTA_DISCORD_CLIENT_SECRET='')
  run=subprocess.run(['node',str(work/'fixture.js'),str(game),str(work/'client'),str(OUT/'server-report.json')],capture_output=True,text=True,env=environment,timeout=75)
  output=run.stdout+run.stderr;(OUT/'runtime.log').write_text(output)
  report={'status':'PASS' if run.returncode==0 else 'FAIL','scope':__doc__,'output':output,
   'sourceHashes':{name:hashlib.sha256(value).hexdigest() for name,value in inputs.items()},
   'liveFilesStillMatchSnapshot':{name:(ROOT/name).read_bytes()==value for name,value in inputs.items()},
   'limits':['Synthetic model IDs, anchor geometry and owned garage/target rows are administrator-seeded before the first native hi; no original data',
             'All subsequent handshake, me, vmove, hitch, topology ACK, parking and disconnect authority uses actual unchanged backend handlers and actual WebSocket peers',
             'A deliberately withheld real accepted ACK and socket destruction simulate uncertain transport; no fabricated topology or accepted response',
             'The separate observer is a real legacy-protocol Node WebSocket client, not a rendered browser or physical controller/iPhone test',
             'No joint solver, retail runtime, internet/LAN router or production service claim']}
  (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(output,end='');run.check_returncode()
if __name__=='__main__':main()
