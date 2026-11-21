#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual scoped draw-phase request, bounded cell ownership and ray coverage."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def block(source,marker):
 a=source.index(marker);b=source.index('{',a)+1;depth=1
 while depth:depth+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[a:b].replace('private ','')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path);p.add_argument('--prepare-only',action='store_true');args=p.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/scoped-coverage-173'/str(time.time_ns());out.mkdir(parents=True)
 selected=(args.source or ROOT/'ios/App/NativeWorldRenderer.swift').resolve();source=selected.read_text();fixture=Path(__file__).with_suffix('.swift');carrier=fixture.read_text()
 marker='    private func prefetchScopedShotCoverage('
 draw=block(source,'    func draw(in view: MTKView)')
 calls=[line.strip()for line in draw.splitlines()if line.strip()=='prefetchScopedShotCoverage()']
 assert len(calls)<=1
 # The historical draw phase has no request hook. This explicitly absent
 # capability is the negative boundary; the actual new method is used whole.
 carrier=carrier.replace('// ACTUAL_PREFETCH',block(source,marker)if marker in source else '')
 carrier=carrier.replace('// ACTUAL_DRAW_HOOK','\n'.join(calls))
 names=['NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeWorldRay']
 paths=[ROOT/'ios/App'/(n+'.swift')for n in names]+[selected,fixture,Path(__file__).resolve()]
 frozen={str(n):hashlib.sha256(n.read_bytes()).hexdigest()for n in paths}
 report=dict(status='PREPARED',startedAt=time.time(),sourceHashes=frozen,renderer=str(selected),historicalPredicates=bool(args.source),drawRequestHooks=len(calls),scope='Actual scoped prefetch method/draw invocation and complete ray/cell-retention owners; authored camera and explicitly asynchronous loader/trace boundaries. No HTTP, Rapier, GPU, App or retail acceptance')
 def save():
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
 save()
 try:
  (out/'Gate.swift').write_text(carrier)
  if not args.prepare_only:
   with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths[:len(names)]),str(out/'Gate.swift'),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
   report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-5000:]
   r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=60);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0,report['output'];report['status']='PASS'
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:
  report.update(sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items()),completedAt=time.time());save();print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
