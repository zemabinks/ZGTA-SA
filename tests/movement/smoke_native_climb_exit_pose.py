#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual successful and aborted climb poses on the first completion tick."""
from pathlib import Path
import argparse,hashlib,json,os,platform,runpy,subprocess,textwrap,time
BASE=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--negative-root',type=Path)
args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
out=BASE/'local-only/research/climb-exit-pose-209';out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
reports=[]
for label,root in ([('historical',args.negative_root.resolve())]if args.negative_root else [])+[('current',BASE)]:
 driver=(BASE/'tests/movement/smoke_native_climb_carrier.py').read_text()
 start=driver.index(' helper=runpy.run_path(');end=driver.index(' work=out/(label+',start)
 builder=textwrap.dedent(driver[start:end]);needle="(BASE/'tests/movement/smoke_native_climb_carrier.swift')"
 assert builder.count(needle)==1;builder=builder.replace(needle,"(BASE/'tests/movement/smoke_native_climb_exit_pose.swift')")
 exec(compile(builder,str(out/'selected-assembly.py'),'exec'))
 needle='    var health=100';assert source.count(needle)==1
 source=source.replace(needle,'    var hasParachute=false // Explicit carrier storage for actual gear owner.\n'+needle)
 needle='    func emitFootWeaponEventsForTest';assert source.count(needle)==1
 source=source.replace(needle,function(renderer,'func setFlightGear(')+'\n'+needle)
 if 'var completionClips:[String]?'not in source:
  needle='    var health=100';assert source.count(needle)==1
  source=source.replace(needle,'    var completionClips:[String]?\n'+needle)
  needle='                completedFeet=motion.heldFeet;completedPart=partBefore;checks += 1';assert source.count(needle)==1
  source=source.replace(needle,'                completionClips=footAnimationFrame!.blends.filter{$0.weight>0}.map(\\.clip)\n'+needle)
 assert source.count('completionClips=footAnimationFrame!.blends.filter{$0.weight>0}.map(\\.clip)')==1
 work=out/(label+'-'+str(time.time_ns()));work.mkdir();(work/'main.swift').write_text(source)
 physics=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativeClimbController','NativeRapierClimbQueries']
 files=[root/'ios/App'/f'{n}.swift'for n in physics+names]+[root/'ios/App/NativeWorldRenderer.swift',root/'ios/App/NativeSkeletalActor.swift',root/'tests/movement/smoke_native_climb_runtime.swift',root/'tests/movement/smoke_native_climb_runtime.py',BASE/'tests/movement/smoke_native_climb_carrier.py',BASE/'tests/movement/smoke_native_climb_exit_pose.swift',Path(__file__).resolve()]
 frozen={str(p):sha(p)for p in files}
 report=dict(label=label,status='RUNNING',startedAt=time.time(),sourceHashes=frozen,carrierSHA256=hashlib.sha256(source.encode()).hexdigest(),carrierBoundary='Missing gear storage and, for the older carrier only, a first-completion clip observer. Selected production method bodies unchanged.')
 def save():(work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 save()
 try:
  command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1','-j','1','-module-cache-path',str(out/'modules'),'-I',str(BASE/'native-physics/include'),*[str(root/'ios/App'/f'{n}.swift')for n in physics],str(work/'main.swift'),'-L',str(BASE/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
  r=subprocess.run(command,capture_output=True,text=True,timeout=600);(work/'compile.log').write_text(r.stdout+r.stderr);report['compileExit']=r.returncode;save();assert r.returncode==0,'Compile failure is not a pose discrepancy'
  command=[str(work/'verify'),str(BASE),str(work/'actual-cases.json')]+(['historical']if label=='historical'else[])
  r=subprocess.run(command,capture_output=True,text=True,timeout=120);(work/'runtime.log').write_text(r.stdout+r.stderr);report['runtimeExit']=r.returncode;save();assert r.returncode==(42 if label=='historical'else 0)
  actual=json.loads((work/'actual-cases.json').read_text());assert len(actual['cases'])==30 and actual['differences']==(20 if label=='historical'else 0)
  report.update(status='EXPECTED_OLD_DIFFERENCES'if label=='historical'else'PASS',cases=30,differences=actual['differences'],successfulControls=10,abortedCases=20)
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:
  report.update(sourceHeld=all(sha(Path(n))==h for n,h in frozen.items()),completedAt=time.time());save()
 assert report['sourceHeld'];reports.append(dict(report,path=str(work)))
(out/'report.json').write_text(json.dumps(dict(status='PASS',results=reports,actualNice=os.getpriority(os.PRIO_PROCESS,0),scope='Actual native Renderer/task/CLP/motor/Rapier with authored admitted ledges and first-completion snapshots. No original-PC blend/timing, GPU, normal App or retail acceptance.'),indent=2)+'\n')
print('PASS actual climb exit poses:',[(r['label'],r['cases'],r['differences'])for r in reports],flush=True)
