#!/usr/bin/env python3
"""Exercise current Renderer climb/foot methods with real animation/native core."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,platform,runpy,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]

RELOAD_AUDIO_TESTS=r'''
    var reloadChecks=0
    func reloadCheck(_ accepted:Bool,_ message:String){precondition(accepted,message);reloadChecks+=1;checks+=1}
    for deferred in [false,true] {
        DispatchQueue.main.clear();Sink.played=[];Sink.stopped=[]
        let task=try ClimbRuntimeHarness(root:root,top:1.8,depth:2)
        let owner=ClimbReloadAudioOwner(task)
        let animator=task.footAnimator!
        reloadCheck(animator.beginReload()>0 && animator.reloading,"Real owned CLP reload must be active before climb")
        owner.audio.deferFetch=deferred;owner.audio.reload(weapon:22)
        if deferred {DispatchQueue.main.drain();reloadCheck(owner.audio.pending.count==2,"Both actual reload phase loads must be pending")}
        var callbacks=0
        let binding=task.onReloadTaskCancelled!
        task.onReloadTaskCancelled={
            reloadCheck(task.climb != nil && !animator.reloading,"Callback ran before accepted task actually reset reload")
            callbacks+=1;binding()
        }
        reloadCheck(task.attemptClimbForTest(),"Actual ledge/geometry must admit the climb")
        reloadCheck(callbacks==1 && !animator.reloading,"Accepted climb must cancel its active reload once")
        reloadCheck(!task.attemptClimbForTest() && callbacks==1,"Rejected repeat emitted a second cancellation")
        DispatchQueue.main.drain();owner.audio.releaseSamples()
        reloadCheck(Sink.played==(deferred ? []:["143_11"]),"Accepted climb retained old delayed phase or sample completion")
        reloadCheck(Sink.stopped.isEmpty,"Task cancellation stopped a committed one-shot")
    }
    for reason in ["missing-animation","missing-ledge","driving","input-reset","no-active-reload"] {
        DispatchQueue.main.clear();Sink.played=[];Sink.stopped=[]
        let task=try ClimbRuntimeHarness(root:root,top:1.8,depth:2)
        let owner=ClimbReloadAudioOwner(task)
        let animator=task.footAnimator!
        if reason != "no-active-reload" {reloadCheck(animator.beginReload()>0 && animator.reloading,"Real reload fixture")}
        owner.audio.reload(weapon:22)
        var callbacks=0;let binding=task.onReloadTaskCancelled!
        task.onReloadTaskCancelled={callbacks+=1;binding()}
        if reason=="missing-animation" {task.footAnimator=nil}
        if reason=="missing-ledge" {task.character!.reset(feet:SIMD3(30,0,0),active:true,grounded:true)}
        if reason=="driving" {task.driving=true}
        if reason=="input-reset" {
            task.cancelGameplayInput()
            reloadCheck(animator.reloading,"Actual input-only reset canceled a legitimate animation reload")
        } else {
            let accepted=task.attemptClimbForTest()
            reloadCheck(accepted==(reason=="no-active-reload"),"Actual climb admission control "+reason)
        }
        reloadCheck(callbacks==0,"Rejected/input-only/nonreload task emitted reload cancellation: "+reason)
        DispatchQueue.main.drain()
        reloadCheck(Sink.played==["143_11","143_12"],"Continuing reload lost second phase: "+reason)
    }
    print("PASS accepted-climb reload audio:",reloadChecks,"actual task/audio/GVC-binding checks; inert sound sink")
'''

def function(source,marker):
 start=source.index(marker)
 opening=source.index('{',start)
 depth=0;quote=False;escape=False
 for index in range(opening,len(source)):
  char=source[index]
  if quote:
   if escape:escape=False
   elif char=='\\':escape=True
   elif char=='"':quote=False
   continue
  if char=='"':quote=True;continue
  if char=='{':depth+=1
  elif char=='}':
   depth-=1
   if depth==0:return source[start:index+1]
 raise RuntimeError('Unbalanced Swift method: '+marker)

def main():
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 methods=['private func combatEligibility(','var canEmitFootWeaponShot:','var canEmitFootCombatMarker:','var hasNativeFootWeaponTiming:','private func footMotion(','private func beginClimb(','private func climbingMotion(',
          'private func emitFootWeaponEvents(','func cancelWeaponInput(','func cancelGameplayInput(','func letGoOfLedge(',
          'private var activeMeleeDefinition:','var hasNativeFootMeleeTiming:','var canNativeFootMeleeGuard:',
          'private func meleeControls(','private func advanceMelee(','private func cancelFootAimForTask(']
 extracted='\n\n'.join(function(renderer,marker) for marker in methods)
 shot_feet=renderer[renderer.index('    private var weaponEventFeet:'):renderer.index('    func weaponMuzzle(',renderer.index('    private var weaponEventFeet:'))]
 extracted=shot_feet+'\n'+extracted
 skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text()
 library=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
 aim=skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]
 source=library+'\nfinal class NativeSkeletalActor {\n'+aim+'}\n'
 names=['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePersonalFlightController',
        'NativeFootLocomotion','NativeHeadingContinuity','NativeSprintController','NativeMelee','NativeMeleeInput','NativeFallDamage']
 for name in names:source+='\n'+(ROOT/'ios/App'/f'{name}.swift').read_text()
 audio_helper=runpy.run_path(str(ROOT/'tests/audio/smoke_native_reload_audio.py'),run_name='climb_audio_fixture')
 source+='\n'+audio_helper['audio_carrier']((ROOT/'ios/App/NativeGameAudio.swift').read_text(),(ROOT/'ios/App/NativeAudioEnvelope.swift').read_text())
 binding=function((ROOT/'ios/App/NativeGameViewController.swift').read_text(),'        renderer?.onReloadTaskCancelled =')
 source+='\nfinal class ClimbReloadAudioOwner {\n let audio=Audio();weak var renderer:ClimbRuntimeHarness?\n init(_ renderer:ClimbRuntimeHarness){self.renderer=renderer;bind()}\n func bind(){\n'+binding+'\n}\n}\n'
 source+='\n'+(ROOT/'tests/movement/smoke_native_climb_runtime.swift').read_text().replace('// ACTUAL_RENDERER_METHODS',extracted).replace('// ACTUAL_RELOAD_AUDIO_TESTS',RELOAD_AUDIO_TESTS)
 paths=[f'ios/App/{name}.swift'for name in names]+[f'ios/App/{name}.swift'for name in ['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativeClimbController','NativeRapierClimbQueries','NativeWorldRenderer','NativeSkeletalActor','NativeGameViewController','NativeGameAudio','NativeAudioEnvelope']]+['tests/movement/smoke_native_climb_runtime.py','tests/movement/smoke_native_climb_runtime.swift','tests/audio/smoke_native_reload_audio.py']
 snapshots={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest()for name in paths}
 evidence_directory=ROOT/'local-only/research/climbing'
 evidence_directory.mkdir(parents=True,exist_ok=True)
 subprocess.run(['node',str(ROOT/'tests/movement/smoke_native_climb_entry.js'),str(evidence_directory/'entry-reference.json')],cwd=ROOT,check=True)
 (evidence_directory/'runtime-source.swift').write_text(source)
 with tempfile.TemporaryDirectory(prefix='zgtasa-climb-runtime-') as temporary:
  work=Path(temporary);(work/'main.swift').write_text(source)
  command=['swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',
    '-I',str(ROOT/'native-physics/include'),str(ROOT/'ios/App/SwiftRapierWorld.swift'),str(ROOT/'ios/App/NativeCharacterMotor.swift'),
    str(ROOT/'ios/App/NativeRapierCharacterQueries.swift'),str(ROOT/'ios/App/NativeCharacterController.swift'),
    str(ROOT/'ios/App/NativeClimbController.swift'),str(ROOT/'ios/App/NativeRapierClimbQueries.swift'),str(work/'main.swift'),
    '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
    '-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
  compiled=subprocess.run(command,capture_output=True,text=True,timeout=900)
  (evidence_directory/'runtime-build.log').write_text(compiled.stdout+compiled.stderr)
  if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
  result=subprocess.run([str(work/'verify'),str(ROOT)],capture_output=True,text=True,timeout=120)
  (evidence_directory/'runtime-run.log').write_text(result.stdout+result.stderr)
  print(result.stdout+result.stderr,end='');result.check_returncode()
 assert all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest for name,digest in snapshots.items()),'actual source changed during climb/audio gate'
 (evidence_directory/'reload-audio-owner-report.json').write_text(json.dumps({'status':'PASS','sourceUnchanged':True,'sourceHashes':snapshots,'carrierSHA256':hashlib.sha256(source.encode()).hexdigest(),'output':result.stdout,'boundary':'Actual CLP, Rapier climb query, Renderer beginClimb/reset/input methods, actual GVC audio binding and actual Audio methods; inert audio sink only, no speaker/retail timing'},indent=2)+'\n')
 evidence=ROOT/'local-only/research/climbing/runtime-methods.sha256'
 evidence.write_text(hashlib.sha256(extracted.encode()).hexdigest()+'\n')
if __name__=='__main__':main()
