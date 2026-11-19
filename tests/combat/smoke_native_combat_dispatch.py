#!/usr/bin/env python3
"""Actual Renderer attack/control/marker methods with real native CLP state."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/combat-88/dispatch'
NAMES=['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeFootLocomotion','NativeMelee','NativeMeleeInput']
FILES=['ios/App/NativeWorldRenderer.swift','ios/App/NativeSkeletalActor.swift','tests/combat/smoke_native_melee.swift','tests/combat/smoke_native_combat_dispatch.py']+[f'ios/App/{n}.swift' for n in NAMES]
TEST=r'''
var checks=0,raw=0
func check(_ v:Bool,_ m:String){checks+=1;precondition(v,m)}
extension RendererHarness {
 func deliver(_ frame:NativeFootAnimation.Frame,feet:SIMD3<Float>){emitFootWeaponEvents(frame,feet:feet)}
 func tick(held:Bool=false,delta:Double=1/60)->NativeFootAnimation.Frame {
  weaponTriggerHeld=held
  let animator=footAnimator!,definition=footWeaponDefinitions[equippedWeapon],state=character?.state ?? CharacterState()
  let airborne = !state.grounded
  let locomotion=footLocomotion.update(delta:delta,input:.init())
  // ACTUAL_AIM_CONTEXT
  // ACTUAL_GUN_CONTROL
  var input=NativeFootAnimation.Input();input.gun=effectiveAim ? .init(pitch:0.2,yaw:0.1):nil
  let frame=animator.update(delta:delta,input:input);emitFootWeaponEvents(frame,feet:SIMD3(1,2,3));return frame
 }
}
func make(_ id:Int=22)->RendererHarness {
 let h=RendererHarness();h.equippedWeapon=id;h.footAnimator!.arm(profiles[id]);return h
}
for state in ["busy","stun","roll","air","swim","climb","vehicle","parachute","dead","reload","not-ready"] {
 let h=make()
 if state=="busy"{check(h.footAnimator!.knock("koSkidBack"),"Actual knock clip required")}
 if state=="stun"{h.footAnimator!.flinch("flinch",stun:true);check(h.footAnimator!.stunned,"Actual stun clip required")}
 if state=="roll"{check(h.footAnimator!.roll(1),"Actual roll clip required")}
 if state=="air"{h.character=CharacterProbe();h.character!.state.grounded=false}
 if state=="swim"{h.swimming=true};if state=="climb"{h.climb=1};if state=="vehicle"{h.driving=true}
 if state=="parachute"{h.personalFlight.chuting=true};if state=="dead"{h.health=0}
 if state=="reload"{h.weaponReloading=true};if state=="not-ready"{h.weaponReady=false}
 check(!h.requestFootWeaponFire(),"Actual request started a new gun attack during \(state)")
}
for id in [34,35,36] {
 let h=make(id);check(!h.requestFootWeaponFire(),"Actual scoped/launcher request bypassed sight aim\(id)")
 h.aiming=true;check(h.requestFootWeaponFire(),"Aimed sight could not request\(id)")
}
for id in [40,43,44,45,46] {
 let h=make(id);h.aiming=true;check(!h.hasNativeFootWeaponTiming && !h.requestFootWeaponFire(),"Utility took native gun timing\(id)")
}
let jet=make();jet.personalFlight.flying=true;jet.personalFlight.on=true;jet.character=CharacterProbe();jet.character!.state.grounded=false
check(jet.requestFootWeaponFire(),"Valid arm gun cannot fire while jetpack-owned")
let heavy=make(34);heavy.aiming=true;heavy.personalFlight.flying=true;heavy.personalFlight.on=true
check(!heavy.requestFootWeaponFire(),"Unsupported heavy gun bypassed jetpack hands")

for hz in [30,60,120] {
 let dt=1.0/Double(hz)
 let h=make();var delivered=0;h.onFootWeaponShot={_,_ in delivered+=1;return true};h.aiming=true
 for _ in 0..<hz {_=h.tick(delta:dt)}
 check(h.requestFootWeaponFire(),"Ordinary request not accepted")
 h.footAnimator!.flinch("flinch",stun:true)
 var rawDuringStun=0
 for _ in 0..<max(1,hz/5) {let f=h.tick(delta:dt);if h.footAnimator!.stunned{rawDuringStun+=f.shots.count};raw+=f.shots.count}
 check(rawDuringStun>0 && delivered==0,"Actual gun marker bypassed stun at\(hz)Hz fixture")
 h.cancelWeaponInput();for _ in 0..<(hz*2) {_=h.tick(delta:dt)}
 check(delivered==0,"Suppressed old marker replayed after stun")
 check(h.requestFootWeaponFire(),"Explicit later request blocked after stun")
 for _ in 0..<hz {_=h.tick(delta:dt)}
 check(delivered==1,"Fresh post-stun shot did not deliver exactly once")

 let melee=make(0);var hits=0;melee.onFootMeleeHit={_ in hits+=1;return true}
 check(melee.requestFootMeleeAttack(),"Actual melee request not accepted")
 melee.advanceForTest(melee.controlsForTest());melee.footAnimator!.flinch("flinch",stun:true)
 var markers=0
 for _ in 0..<max(1,hz/4) {
  let f=melee.footAnimator!.update(delta:dt);if melee.footAnimator!.stunned{markers+=f.shots.count}
  melee.deliver(f,feet:.zero)
 }
 check(markers>0 && hits==0,"Actual committed melee marker bypassed source stun suppression")
}
let committed=make();committed.aiming=true
for _ in 0..<60 {_=committed.tick()}
check(committed.requestFootWeaponFire(),"Committed attack fixture")
committed.footAnimator!.knock("koSkidBack")
var keptPose=false,committedHits=0;committed.onFootWeaponShot={_,_ in committedHits+=1;return true}
for _ in 0..<30 {let frame=committed.tick();keptPose=keptPose || frame.aim.rightArm>0}
check(keptPose && committedHits==1,"Busy task erased committed gun pose or marker")

for id in [0,16,22,41] {
 let h=make(id);var count=0;h.onFootWeaponShot={_,_ in count+=1;return true};h.onFootMeleeHit={_ in count+=1;return true}
 if id==0{_=h.requestFootMeleeAttack();h.advanceForTest(h.controlsForTest())}else{_=h.requestFootWeaponFire()}
 h.cancelWeaponInput();for _ in 0..<120 {_=h.tick()}
 check(count==0,"Task cancellation replayed weapon\(id) input")
}
let atomic=make();var emits:[Int]=[]
var pair=atomic.footAnimator!.update(delta:0);pair.shots=[false,true]
atomic.onFootWeaponShot={w,_ in emits.append(w);atomic.weaponReady=false;return true}
atomic.deliver(pair,feet:.zero)
check(emits==[22],"Second hand ignored synchronous empty/reload readiness")
atomic.weaponReady=true;emits=[]
atomic.onFootWeaponShot={w,_ in emits.append(w);atomic.equippedWeapon=24;return true}
atomic.deliver(pair,feet:.zero)
check(emits==[22],"Old-frame second hand spent a newly selected weapon")
let stream=make(37);var streamEmits=0
stream.onFootWeaponShot={_,_ in streamEmits+=1;stream.weaponReady=false;return true}
check(stream.requestFootWeaponFire(),"Final stream round fixture")
for _ in 0..<120 {if streamEmits>0{break};_=stream.tick(held:true)}
check(streamEmits==1 && stream.acceptedStreamShot && stream.nativeWeaponStreamActive,"Final accepted stream round lost its current-frame presentation")
stream.acceptedStreamShot=false
check(!stream.nativeWeaponStreamActive,"Empty stream remained active without a current accepted marker")
stream.acceptedStreamShot=true;stream.footAnimator!.flinch("flinch",stun:true)
check(!stream.nativeWeaponStreamActive,"Accepted stream presentation bypassed stun")
stream.health=0;check(!stream.nativeWeaponStreamActive,"Accepted stream presentation survived death")
print("PASS actual combat dispatch: \(checks) real-CLP request/control/marker checks, \(raw) raw stun markers suppressed, scope/jetpack/tasks/weapon ownership")
'''
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--reference-request',type=Path)
 parser.add_argument('--reference-emission',type=Path);parser.add_argument('--identity-only',action='store_true')
 parser.add_argument('--melee-only',action='store_true');args=parser.parse_args()
 OUT.mkdir(parents=True,exist_ok=True);inputs={n:(ROOT/n).read_bytes() for n in FILES};renderer=inputs['ios/App/NativeWorldRenderer.swift'].decode()
 markers=['private func combatEligibility(','var canRequestFootWeaponFire:','var canEmitFootWeaponShot:','var canEmitFootCombatMarker:','var hasNativeFootWeaponTiming:','var nativeWeaponStreamActive:',
  'private var activeMeleeDefinition:','var hasNativeFootMeleeTiming:','var canNativeFootMeleeGuard:',
  '@discardableResult func requestFootMeleeAttack(','private func meleeControls(','private func advanceMelee(','private func emitFootWeaponEvents(','func cancelWeaponInput()','@discardableResult func requestFootWeaponFire(']
 methods=[]
 for marker in markers:
  reference_path=args.reference_request if 'requestFootWeaponFire(' in marker else args.reference_emission if 'emitFootWeaponEvents(' in marker else None
  src=reference_path.read_text() if reference_path else renderer
  methods.append(function(src,marker))
 a=renderer.index('        let aimContext=combatEligibility(');b=renderer.index('\n        let meleeFrame=',a);aim=renderer[a:b]
 a=renderer.index('        let fireContext=combatEligibility(');b=renderer.index('\n        if airborne {',a);control=renderer[a:b]
 skeletal=inputs['ios/App/NativeSkeletalActor.swift'].decode();source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
 source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
 source+='\n'+'\n'.join(inputs[f'ios/App/{n}.swift'].decode() for n in NAMES)
 harness=inputs['tests/combat/smoke_native_melee.swift'].decode().split('var checks=0,frames=0')[0]
 test=TEST if not args.identity_only else TEST[:TEST.index('for state in [')]+TEST[TEST.index('let atomic='):]
 if args.melee_only:
  a=test.index(' let h=make();var delivered=0');b=test.index(' let melee=make(0);',a);test=test[:a]+test[b:]
 source+='\n'+harness.replace('// ACTUAL_RENDERER_METHODS','\n'.join(methods))+'\n'+test.replace('// ACTUAL_AIM_CONTEXT',aim).replace('// ACTUAL_GUN_CONTROL',control)
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temp:
  p=Path(temp);(p/'reference.json').write_text('{}');(p/'verify.swift').write_text(source);exe=p/'verify'
  compiled=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),str(p/'verify.swift'),'-o',str(exe)],capture_output=True,text=True)
  (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
  if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
  result=subprocess.run([str(exe),str(ROOT),str(p/'reference.json')],capture_output=True,text=True)
  report={'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,'sourceHashes':{n:hashlib.sha256(v).hexdigest() for n,v in inputs.items()},'limits':['Actual extracted Root request/control/emission with actual native CLP; controlled world/UI/callback carriers, no GPU/retail runtime','Paired-hand event array is a synthetic carrier to test synchronous readiness and selection ownership; no dual-wield acquisition claim']}
  if args.reference_request:report['historicalRequest']={'path':str(args.reference_request),'sha256':hashlib.sha256(args.reference_request.read_bytes()).hexdigest()}
  if args.reference_emission:report['historicalEmission']={'path':str(args.reference_emission),'sha256':hashlib.sha256(args.reference_emission.read_bytes()).hexdigest()}
  report['identityOnly']=args.identity_only
  report['meleeOnly']=args.melee_only
  name='before-request' if args.reference_request else 'before-emission' if args.reference_emission else 'report'
  if args.identity_only:name+='-identity'
  if args.melee_only:name+='-melee'
  (OUT/(name+'.json')).write_text(json.dumps(report,indent=2)+'\n')
  print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
if __name__=='__main__':main()
