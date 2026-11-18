#!/usr/bin/env python3
"""Actual Renderer hit/motion methods, real animation clips and native motor."""
from pathlib import Path
import hashlib,json,platform,subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/hit-runtime'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    names=['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePersonalFlightController','NativeFootLocomotion','NativeHeadingContinuity','NativeSprintController','NativeMelee','NativeMeleeInput','NativeFallDamage','NativeLocalHitReaction','NativePedestrianReaction','NativeOriginalWorldVitals']
    physics=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativeClimbController','NativeRapierClimbQueries']
    paths=[f'ios/App/{name}.swift' for name in names+physics]+['ios/App/NativeMultiplayerClient.swift','ios/App/NativeSkeletalActor.swift','ios/App/NativeWorldRenderer.swift','smoke_native_climb_runtime.swift','smoke_native_hit_runtime.py','smoke_native_hit_runtime.swift']
    before={p:(ROOT/p).read_bytes() for p in paths};renderer=before['ios/App/NativeWorldRenderer.swift'].decode()
    markers=['private func combatEligibility(','var canEmitFootWeaponShot:','var canEmitFootCombatMarker:','var hasNativeFootWeaponTiming:','private func footMotion(','private func beginClimb(','private func climbingMotion(','private func emitFootWeaponEvents(','func cancelWeaponInput(','func cancelGameplayInput(','func letGoOfLedge(','private var activeMeleeDefinition:','var hasNativeFootMeleeTiming:','var canNativeFootMeleeGuard:','private func meleeControls(','private func advanceMelee(','func receiveHit(','var footWireDown:','private func cancelFootAimForTask(']
    methods='\n'.join(function(renderer,marker) for marker in markers)
    methods=renderer[renderer.index('    private var weaponEventFeet:'):renderer.index('    func weaponMuzzle(',renderer.index('    private var weaponEventFeet:'))]+'\n'+methods
    skeletal=before['ios/App/NativeSkeletalActor.swift'].decode()
    source='import CoreFoundation\n'+skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
    source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
    for name in names:source+='\n'+before[f'ios/App/{name}.swift'].decode()
    client=before['ios/App/NativeMultiplayerClient.swift'].decode()
    source+='\n'+function(client,'struct NativeHealthPrediction {')+'\n'+function(client,'struct NativeIncomingHit {')
    harness=before['smoke_native_climb_runtime.swift'].decode().split('@main enum ClimbRuntimeSmoke')[0]
    harness=harness.replace('final class ClimbRuntimeHarness {','final class ClimbRuntimeHarness {\n    let localHitReaction=NativeLocalHitReaction()')
    source+='\n'+harness.replace('// ACTUAL_RENDERER_METHODS',methods)+'\n'+before['smoke_native_hit_runtime.swift'].decode()
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as temp:
        work=Path(temp);(work/'main.swift').write_text(source);sources=[]
        for name in physics:p=work/(name+'.swift');p.write_bytes(before[f'ios/App/{name}.swift']);sources.append(str(p))
        result=subprocess.run(['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-O','-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],capture_output=True,text=True)
        (OUT/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(ROOT)],capture_output=True,text=True)
        unchanged=all((ROOT/p).read_bytes()==v for p,v in before.items())
        report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,
                'limits':['Actual current Renderer methods/decoder, local real clips and native physics; controlled accepted event inputs','No UIKit/Metal rendering, real peer transport, retail executable or physical device evidence']}
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
