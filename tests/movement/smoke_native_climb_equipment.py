#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual climb/equipment ownership through input cancellation and real phases."""
from pathlib import Path
import argparse,hashlib,json,os,platform,runpy,subprocess,textwrap,time
BASE=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--negative-root',type=Path)
args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
out=BASE/'local-only/research/climb-equipment-208';out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
reports=[]
for label,root in ([('historical',args.negative_root.resolve())]if args.negative_root else [])+[('current',BASE)]:
 driver=(BASE/'tests/movement/smoke_native_climb_carrier.py').read_text()
 start=driver.index(' helper=runpy.run_path(');end=driver.index(' work=out/(label+',start)
 builder=textwrap.dedent(driver[start:end]);needle="(BASE/'tests/movement/smoke_native_climb_carrier.swift')"
 assert builder.count(needle)==1
 builder=builder.replace(needle,"(BASE/'tests/movement/smoke_native_climb_equipment.swift')")
 exec(compile(builder,str(out/'selected-assembly.py'),'exec'))
 needle='    var health=100';assert source.count(needle)==1
 source=source.replace(needle,'    var hasParachute=false // Explicit carrier storage for the actual gear owner.\n    var recordNextOwnerTick=false,recordedClimbOwner:Bool?\n'+needle)
 needle='            expectedHeld=motion.heldFeet';assert source.count(needle)==1
 source=source.replace(needle,'            if recordNextOwnerTick {recordedClimbOwner=climb != nil;recordNextOwnerTick=false}\n'+needle)
 needle='    func emitFootWeaponEventsForTest';assert source.count(needle)==1
 source=source.replace(needle,function(renderer,'func setFlightGear(')+'\n'+needle)
 work=out/(label+'-'+str(time.time_ns()));work.mkdir();(work/'main.swift').write_text(source)
 physics=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativeClimbController','NativeRapierClimbQueries']
 files=[root/'ios/App'/f'{n}.swift'for n in physics+names]+[root/'ios/App/NativeWorldRenderer.swift',root/'ios/App/NativeSkeletalActor.swift',root/'tests/movement/smoke_native_climb_runtime.swift',root/'tests/movement/smoke_native_climb_runtime.py',BASE/'tests/movement/smoke_native_climb_carrier.py',BASE/'tests/movement/smoke_native_climb_equipment.swift',Path(__file__).resolve()]
 frozen={str(p):sha(p)for p in files}
 report=dict(label=label,status='RUNNING',startedAt=time.time(),carrierSHA256=hashlib.sha256(source.encode()).hexdigest(),sourceHashes=frozen,carrierBoundary='Explicit missing hasParachute storage and a first-receiving-fixed-tick observer in our independent carrier; all selected production method bodies are unchanged.')
 def save():(work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 save()
 try:
  command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1','-j','1','-module-cache-path',str(out/'modules'),'-I',str(BASE/'native-physics/include'),*[str(root/'ios/App'/f'{n}.swift')for n in physics],str(work/'main.swift'),'-L',str(BASE/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
  r=subprocess.run(command,capture_output=True,text=True,timeout=600);(work/'compile.log').write_text(r.stdout+r.stderr);report['compileExit']=r.returncode;save();assert r.returncode==0,'Compilation failure is not a gameplay difference'
  command=[str(work/'verify'),str(BASE),str(work/'actual-cases.json')]+(['historical']if label=='historical'else[])
  r=subprocess.run(command,capture_output=True,text=True,timeout=120);(work/'runtime.log').write_text(r.stdout+r.stderr);report['runtimeExit']=r.returncode;save();assert r.returncode==(42 if label=='historical'else 0)
  result=json.loads((work/'actual-cases.json').read_text());assert len(result['cases'])==70 and result['differences']==(30 if label=='historical'else 0)
  report.update(status='EXPECTED_OLD_DIFFERENCES'if label=='historical'else'PASS',cases=70,differences=result['differences'])
 except BaseException as error:report.update(status='FAIL',error=repr(error));raise
 finally:
  report.update(sourceHeld=all(sha(Path(n))==h for n,h in frozen.items()),completedAt=time.time());save()
 assert report['sourceHeld'];reports.append(dict(report,path=str(work)))
(out/'report.json').write_text(json.dumps(dict(status='PASS',results=reports,actualNice=os.getpriority(os.PRIO_PROCESS,0),scope='Actual gear/input/climb/foot owner regression with authored admitted ledges and real phases. Flight dispatch, UI, network, GPU and retail remain separate.'),indent=2)+'\n')
print('PASS actual climb/equipment owners:',[(r['label'],r['cases'],r['differences'])for r in reports],flush=True)
