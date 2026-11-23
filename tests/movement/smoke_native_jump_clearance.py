#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual Renderer jump admission, original local CLP and native Rapier roofs.

The optional negative root runs unchanged earlier owners through the same
independently authored fixtures. No original source/data is distributed.
"""
from pathlib import Path
import argparse,hashlib,json,os,platform,runpy,subprocess,time
BASE=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--negative-root',type=Path)
args=parser.parse_args()
os.setpriority(os.PRIO_PROCESS,0,15)
out=BASE/'local-only/research/jump-clearance-205';out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
reports=[]
for label,root in ([('historical',args.negative_root.resolve())]if args.negative_root else [])+[('current',BASE)]:
 helper=runpy.run_path(str(root/'tests/movement/smoke_native_climb_runtime.py'),run_name='jump_clearance_helpers');function=helper['function']
 renderer=(root/'ios/App/NativeWorldRenderer.swift').read_text()
 methods=['func jump(', 'private func combatEligibility(','var canEmitFootWeaponShot:','var canEmitFootCombatMarker:','var hasNativeFootWeaponTiming:','private func footMotion(','private func beginClimb(','private func climbingMotion(','private func emitFootWeaponEvents(','func cancelWeaponInput(','func cancelGameplayInput(','func letGoOfLedge(','private var activeMeleeDefinition:','var hasNativeFootMeleeTiming:','var canNativeFootMeleeGuard:','private func meleeControls(','private func advanceMelee(','private func cancelFootAimForTask(']
 extracted='\n\n'.join(function(renderer,m)for m in methods)
 shot=renderer[renderer.index('    private var weaponEventFeet:'):renderer.index('    func weaponMuzzle(',renderer.index('    private var weaponEventFeet:'))]
 skeletal=(root/'ios/App/NativeSkeletalActor.swift').read_text();source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
 source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
 names=['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePersonalFlightController','NativeFootLocomotion','NativeHeadingContinuity','NativeSprintController','NativeMelee','NativeMeleeInput','NativeFallDamage']
 for name in names:source+='\n'+(root/'ios/App'/f'{name}.swift').read_text()
 harness=(root/'tests/movement/smoke_native_climb_runtime.swift').read_text().split('@main enum ClimbRuntimeSmoke {')[0]
 assert harness.count('// ACTUAL_RENDERER_METHODS')==1
 harness=harness.replace('// ACTUAL_RENDERER_METHODS',shot+'\n'+extracted)
 # Observers alter only the independent test carrier. All selected production
 # methods above are included verbatim and source hashes are held throughout.
 assert harness.count('    var health=100')==1 and harness.count('            expectedHeld=motion.heldFeet')==1
 harness=harness.replace('    var health=100','    var observedRequestedJump=0.0\n    var characterActive=true // This carrier activates its actual controller in init.\n    var health=100').replace('            expectedHeld=motion.heldFeet','            observedRequestedJump=max(observedRequestedJump,motion.jump)\n            expectedHeld=motion.heldFeet')
 source+='\n'+harness+'\n'+(BASE/'tests/movement/smoke_native_jump_clearance.swift').read_text()
 
 work=out/(label+'-'+str(time.time_ns()));work.mkdir();(work/'main.swift').write_text(source)
 physics=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativeClimbController','NativeRapierClimbQueries']
 files=[root/'ios/App'/f'{n}.swift'for n in physics+names]+[root/'ios/App/NativeWorldRenderer.swift',root/'ios/App/NativeSkeletalActor.swift',root/'tests/movement/smoke_native_climb_runtime.swift',BASE/'tests/movement/smoke_native_jump_clearance.swift',Path(__file__).resolve()]
 frozen={str(p):sha(p)for p in files}
 report=dict(label=label,status='RUNNING',startedAt=time.time(),carrierSHA256=hashlib.sha256(source.encode()).hexdigest(),sourceHashes=frozen)
 def save():(work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 save()
 try:
  command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path',str(out/'modules'),'-I',str(BASE/'native-physics/include'),*[str(root/'ios/App'/f'{n}.swift')for n in physics],str(work/'main.swift'),'-L',str(BASE/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
  start=time.monotonic();r=subprocess.run(command,capture_output=True,text=True,timeout=600);(work/'compile.log').write_text(r.stdout+r.stderr);report.update(compileExit=r.returncode,compileSeconds=time.monotonic()-start);save();assert r.returncode==0,'Compilation failure is not an accepted negative'
  command=[str(work/'verify'),str(BASE),str(work/'actual-cases.json')]+(['legacy']if label=='historical'else[])
  r=subprocess.run(command,capture_output=True,text=True,timeout=120);(work/'runtime.log').write_text(r.stdout+r.stderr);report['runtimeExit']=r.returncode;save();assert r.returncode==(42 if label=='historical'else 0),'Unexpected actual-owner outcome'
  result=json.loads((work/'actual-cases.json').read_text());assert len(result['cases'])==39 and result['differences']==(12 if label=='historical'else 0)
  report.update(status='EXPECTED_OLD_DIFFERENCES'if label=='historical'else'PASS',cases=39,differences=result['differences'])
 finally:
  report.update(sourceHeld=all(sha(Path(n))==h for n,h in frozen.items()),completedAt=time.time());save()
 assert report['sourceHeld'];reports.append(dict(report,path=str(work)))
(out/'report.json').write_text(json.dumps(dict(status='PASS',results=reports,actualNice=os.getpriority(os.PRIO_PROCESS,0),scope='Actual byte-preserved Renderer input/foot/climb methods, real local CLP and native physics. Authored roofs/ledge. Special original CPed exceptions, muscle/stat modifiers, animation-only missing-resource fallback simulation and retail timings remain unverified.'),indent=2)+'\n')
print('PASS actual jump-clearance owners:',[(r['label'],r['cases'],r['differences'])for r in reports],flush=True)
