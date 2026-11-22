#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual native decoder and independent backend vehicle-condition integration."""
from pathlib import Path
import hashlib,json,os,runpy,shutil,signal,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
 os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/native-vehicle-condition'/str(time.time_ns());out.mkdir(parents=True)
 names=runpy.run_path(str(ROOT/'tests/network/smoke_original_world_wire.py'))['NAMES']
 sources=['ios/App/'+n+'.swift'for n in names]+['ios/App/NativeActorAnimation.swift','tests/network/smoke_native_vehicle_condition.py','tests/network/smoke_native_vehicle_condition.js','tests/network/smoke_native_vehicle_condition.swift','tests/network/smoke_original_world_wire.py']
 backend=['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js']
 frozen={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest()for n in sources+backend}
 report=dict(status='RUNNING',startedAt=time.time(),sourceHashes=frozen,scope='Actual native URLSession decoder and backend HTTP/WebSocket/authority. Authored car and in-memory driver uses normal admission. Server declines unrelated placement capability. No App/render/hardware/retail acceptance.')
 def save():(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
 def run(command,log,budget):
  with log.open('x')as stream:
   p=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
   try:return p.wait(timeout=budget)
   except subprocess.TimeoutExpired:
    os.killpg(p.pid,signal.SIGTERM)
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
    return 124
   finally:
    if p.poll() not in [None,0]:
     try:os.killpg(p.pid,signal.SIGTERM)
     except ProcessLookupError:pass
 save()
 try:
  actor=(ROOT/'ios/App/NativeActorAnimation.swift').read_text();motion=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
  (out/'main.swift').write_text('\n'.join((ROOT/'ios/App'/(n+'.swift')).read_text()for n in names)+'\n'+motion+'\n'+Path(__file__).with_suffix('.swift').read_text())
  fixture=out/'game';fixture.mkdir()
  for name in backend:shutil.copy2(ROOT/name,fixture/name)
  settings=fixture/'local-only/selfhost';settings.mkdir(parents=True)
  (settings/'client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
  (settings/'weapon-catalog.json').write_text('{\"items\":[],\"shops\":[]}')
  world=fixture/'local-only/site/game/world';world.mkdir(parents=True)
  (world/'index.json').write_text('{\"water\":[],\"tiles\":[]}')
  code=run(['xcrun','swiftc','-O','-j','1','-whole-module-optimization','-num-threads','1','-module-cache-path',str(out/'modules'),str(out/'main.swift'),'-o',str(out/'verify')],out/'compile.log',300)
  report['compileExit']=code;save();assert code==0,(out/'compile.log').read_text()[-4000:]
  code=run(['node',str(Path(__file__).with_suffix('.js')),str(fixture),str(out/'verify')],out/'runtime.log',45)
  report.update(exitCode=code,output=(out/'runtime.log').read_text());save();assert code==0,report['output']
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in frozen.items()),'Production/test sources changed during the gate'
  report['status']='PASS'
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:
  report.update(completedAt=time.time(),sourcesHeld=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in frozen.items()));save();print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
