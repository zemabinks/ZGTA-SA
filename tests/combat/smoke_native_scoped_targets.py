#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual scoped resolver, drawing and resource-admission source predicates."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def block(source,marker):
 a=source.index(marker);brace=source.index('{',a);b=brace+1;depth=1
 while depth:depth+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[a:b].replace('private ','')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,help='Optional historical renderer predicates with current actual helper/typed boundary');p.add_argument('--prepare-only',action='store_true');args=p.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/scoped-targets-173'/str(time.time_ns());out.mkdir(parents=True)
 current=ROOT/'ios/App/NativeWorldRenderer.swift';selected=(args.source or current).resolve()
 renderer=current.read_text();source=selected.read_text();fixture=Path(__file__).with_suffix('.swift');carrier=fixture.read_text()
 names=['NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots']
 paths=[ROOT/'ios/App'/(n+'.swift')for n in names]+[current,selected,fixture,Path(__file__).resolve()]
 frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
 carrier=carrier.replace('// ACTUAL_FOOT_ROLE',block(source,'    private static func remoteAppearanceIsFoot('))
 carrier=carrier.replace('// ACTUAL_DRAW_RADIUS',block(renderer,'    private var remoteDrawDistance:'))
 carrier=carrier.replace('// ACTUAL_RESOLVE',block(source,'    func resolveLocalShot('))
 start=source.index('        for player in remotePlayers where simd_distance(',source.index('    private func synchronizeStockPedDemand('))
 carrier=carrier.replace('// ACTUAL_RESOURCE_DEMAND',block(source[start:],'        for player in remotePlayers where simd_distance('))
 guard=next(line.strip()for line in source.splitlines()if 'guard simd_distance(player.position,scenePosition)<'in line)
 carrier=carrier.replace('// ACTUAL_DRAW_GUARD',guard.replace('else{continue}','else{return false}'))
 (out/'Gate.swift').write_text(carrier)
 report=dict(status='PREPARED',startedAt=time.time(),sourceHashes=frozen,renderer=str(selected),historicalPredicates=bool(args.source),scope='Actual literal resolver and draw/resource/role predicates, actual complete gun geometry; authored model readiness/rows, clear-world and empty vehicle boundaries. No GPU/App/server/retail acceptance')
 def save():
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
 save()
 try:
  if not args.prepare_only:
   with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths[:len(names)]),str(out/'Gate.swift'),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
   report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-4000:]
   r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=60);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0,report['output'];report['status']='PASS'
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:
  report.update(sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items()),completedAt=time.time());save();print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
