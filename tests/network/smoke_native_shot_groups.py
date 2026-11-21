#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual native URLSession and independent backend grouped-shot integration."""
from pathlib import Path
import hashlib,json,os,runpy,shutil,signal,struct,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
 os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/native-shot-groups'/str(time.time_ns());out.mkdir(parents=True)
 names=runpy.run_path(str(ROOT/'tests/network/smoke_original_world_wire.py'))['NAMES']+['NativeHumanShots']
 sources=['ios/App/'+n+'.swift'for n in names]+['ios/App/NativeActorAnimation.swift','ios/App/NativeWorldRenderer.swift','ios/App/NativeGameViewController.swift','tests/network/smoke_native_shot_groups.py','tests/network/smoke_native_shot_groups.js','tests/network/smoke_native_shot_groups.swift','tests/network/smoke_original_world_wire.py']
 backend=['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js']
 frozen={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest()for n in sources+backend}
 report=dict(status='RUNNING',startedAt=time.time(),sourceHashes=frozen,scope='Actual native transport/prediction/packet builder, extracted renderer strike admission with explicit actor roster, and backend socket/authority; authored catalog/geometry/victims; server declines unrelated placement capability; no App/render/retail acceptance')
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
  renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text();start=renderer.index('    func receiveAcceptedStrike(');brace=renderer.index('{',start);end=brace+1;depth=1
  while depth:depth+=(renderer[end]=='{')-(renderer[end]=='}');end+=1
  carrier='''
final class StrikeRenderer {
 struct Person {let id:String,code:String;var health=100}
 var remotePlayers:[Person]=[],remoteFootAnimations:[String:(String,Int)]=[:]
 let humanShots=NativeHumanShots()
 func actorName(code:String)->String {code=="s7" ? "authored-rig":"other-rig"}
 func riderMonotonicNow()->Double {1}
'''+renderer[start:end]+'\n}\n'
  binding='network.onAcceptedStrike = {[weak self] strike in self?.renderer?.receiveAcceptedStrike(strike)}'
  assert binding in (ROOT/'ios/App/NativeGameViewController.swift').read_text()
  (out/'main.swift').write_text('\n'.join((ROOT/'ios/App'/(n+'.swift')).read_text()for n in names)+'\n'+motion+'\n'+carrier+'\n'+Path(__file__).with_suffix('.swift').read_text())
  fixture=out/'game';fixture.mkdir()
  for name in backend:shutil.copy2(ROOT/name,fixture/name)
  settings=fixture/'local-only/selfhost';settings.mkdir(parents=True)
  (settings/'client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
  (settings/'weapon-catalog.json').write_text(json.dumps(dict(items=[dict(id=25,name='Authored six-ray fixture',ammo=20,capacity=5,price=0,slot=3,fire='INSTANT_HIT',stats=dict(range=40,pellets=6,damage=4,loop=[0,9,0]))],shops=[])))
  world=fixture/'local-only/site/game/world';world.mkdir(parents=True)
  (world/'index.json').write_text(json.dumps(dict(detail=dict(size=375,grid=16,origin=-3000,cells=[dict(cell=28)]),inside=dict(cells=[]))))
  vertices=[(1500,-2625,0),(1875,-2625,0),(1875,-2250,0),(1500,-2250,0)]
  (world/'c28.col.bin').write_bytes(struct.pack('<4I',0x324c4353,4,2,0)+b''.join(struct.pack('<3f',*v)for v in vertices)+struct.pack('<6I',0,1,2,0,2,3))
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
