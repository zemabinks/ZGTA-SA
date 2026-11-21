#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual controller hitch branch and frame-clock input/physics separation."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def block(source,marker):
 a=source.index(marker);b=source.index('{',a)+1;depth=1
 while depth:depth+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[a:b]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,help='Historical controller branch; actual current clock remains compiled');p.add_argument('--prepare-only',action='store_true');args=p.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/foreground-input-176'/str(time.time_ns());out.mkdir(parents=True)
 current=ROOT/'ios/App/NativeGameViewController.swift';selected=(args.source or current).resolve();clock=ROOT/'ios/App/NativeGameInput.swift';fixture=Path(__file__).with_suffix('.swift')
 sources=[current,selected,clock,fixture,Path(__file__).resolve()];frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in sources}
 src=current.read_text()
 for marker in ['    @objc private func applicationResigned()', '    @objc private func applicationReturned()', '    override func present(']:
  assert 'resetControls()'in block(src,marker),marker
 assert 'if !acceptsInput && inputWasAvailable { resetControls() }'in src
 assert 'setAiming(false)'in block(src,'    private func resetControls()')
 assert 'aimButton.isSelected = aiming'in block(src,'    private func setAiming(')
 gate=fixture.read_text().replace('// ACTUAL_CONTROLLER_DISCONTINUITY',block(selected.read_text(),'        if timing.discontinuity'))
 (out/'Gate.swift').write_text(gate)
 report=dict(status='PREPARED',startedAt=time.time(),sourceHashes=frozen,historicalBranch=bool(args.source),scope='Complete actual frame clock plus extracted actual controller discontinuity branch; authored timestamps, virtual stick and controller neutral gate. ResetControls is an explicit state boundary, lifecycle ownership hooks source-checked. No actual stall, UIKit, App, hardware, browser runtime or retail acceptance')
 def save():
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
 save()
 try:
  if not args.prepare_only:
   with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(clock),str(out/'Gate.swift'),'-o',str(out/'gate')],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=180)
   report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-4000:]
   r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=30);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0,report['output'];report['status']='PASS'
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:
  report.update(sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items()),completedAt=time.time());save();print({k:v for k,v in report.items()if k!='sourceHashes'})
if __name__=='__main__':main()
