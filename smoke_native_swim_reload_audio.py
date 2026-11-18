#!/usr/bin/env python3
"""Real water/flight/animation task handoffs with an inert actual-audio carrier.

Requires existing owner-local CLP and prepared native physics. No preparation,
resource hydration, server, audio output or device action is performed.
"""
from pathlib import Path
import argparse,hashlib,json,platform,runpy,subprocess,tempfile
from smoke_native_climb_runtime import function

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/swim-reload-audio-118'
METHODS=['private func combatEligibility(','private func swimmingMotion(',
         'private func personalFlightMotion(','private var personalFlightAnimationInput:',
         'func cancelGameplayInput(']
NAMES=['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation',
       'NativeFootAnimation','NativePersonalFlightController','NativeFootLocomotion',
       'NativeHeadingContinuity','NativeSprintController','NativeSwimController','NativeMelee']
PHYSICS=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries',
         'NativeCharacterController','NativeGameInput']

def harness(renderer,template,name):
    if name!='FixedVelocityHarness':
        shared='private extension Float {var double:Double {Double(self)}}'
        assert template.count(shared)==1
        template=template.replace(shared,'')
    markers=METHODS+(['private func cancelFootAimForTask(']if 'private func cancelFootAimForTask(' in renderer else [])
    methods='\n'.join(function(renderer,marker)for marker in markers)
    start=renderer.index('        if !driving, let character {\n            lastFootVelocity =')
    publish=renderer[start:renderer.index('\n        if let characterOutput',start)]
    start=renderer.index('motion: { [self] step,state,intended in')
    boundary=renderer[renderer.index('\n',start):renderer.index('                    if let held=climbingMotion',start)]
    wrappers='''
    func waterForReload(delta:Double=1/60)->NativeCharacterController.Motion {
        swimmingMotion(delta:delta,state:character!.state,
            intended:.init(displacement:SIMD3(1,2,3),jump:4),push:0,running:false)
    }
    func flightForReload(running:Bool=true)->NativeCharacterController.Motion? {
        personalFlightMotion(delta:1/60,state:character!.state,
            intended:.init(displacement:.zero),forward:0,sideways:0,running:running)
    }
'''
    return template.replace('FixedVelocityHarness',name).replace('// ACTUAL_PUBLISH',publish).replace(
        '// ACTUAL_MOTION_BOUNDARY',boundary).replace('// ACTUAL_HANDOFFS',methods+wrappers)

HISTORY=r'''
    for flight in [false,true] {
        DispatchQueue.main.clear();Sink.played=[];Sink.stopped=[]
        let h=HistoricalVelocityHarness(library:library,mode:flight ? "jetpack":"water")
        let audio=Audio();h.equippedWeapon=flight ? 23:22;h.footWeaponDefinitions=profiles
        h.footAnimator!.arm(profiles[h.equippedWeapon])
        check(h.footAnimator!.beginReload()>0 && h.footAnimator!.reloading,"literal117 active native reload control")
        audio.reloads["23"]=[11,12];audio.reload(weapon:h.equippedWeapon)
        var notified=0;h.onReloadTaskCancelled={notified+=1;audio.cancelReload()}
        if flight{check(h.flightForReload() != nil && h.personalFlight.flying,"literal117 admitted jetpack")}
        else{h.waterEdge=1479;_ = h.waterForReload();check(h.swimController.on,"literal117 admitted swim")}
        check(!h.footAnimator!.reloading && notified==0,"literal117 must reproduce missing owner notification")
        DispatchQueue.main.drain();check(Sink.played==["143_11","143_12"],"literal117 old second phase must reproduce")
    }
    historicalExecuted=true
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--historical-root',type=Path);args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    names=[f'ios/App/{x}.swift'for x in NAMES+PHYSICS]+['ios/App/NativeSkeletalActor.swift',
        'ios/App/NativeWorldRenderer.swift','ios/App/NativeGameViewController.swift',
        'ios/App/NativeGameAudio.swift','ios/App/NativeAudioEnvelope.swift',
        'smoke_native_fixed_velocity.swift','smoke_native_swim_reload_audio.py',
        'smoke_native_swim_reload_audio.swift','smoke_native_reload_audio.py']
    before={n:(ROOT/n).read_bytes()for n in names}
    renderer=before['ios/App/NativeWorldRenderer.swift'].decode()
    skeletal=before['ios/App/NativeSkeletalActor.swift'].decode()
    source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
    source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
    source+='\n'+'\n'.join(before[f'ios/App/{n}.swift'].decode()for n in NAMES)
    template=before['smoke_native_fixed_velocity.swift'].decode().split('@main enum Gate')[0]
    source+='\n'+harness(renderer,template,'FixedVelocityHarness')
    audio=runpy.run_path(str(ROOT/'smoke_native_reload_audio.py'),run_name='water_reload_audio')
    source+='\n'+audio['audio_carrier'](before['ios/App/NativeGameAudio.swift'].decode(),before['ios/App/NativeAudioEnvelope.swift'].decode())
    binding=function(before['ios/App/NativeGameViewController.swift'].decode(),'        renderer?.onReloadTaskCancelled =')
    source+='\nfinal class WaterReloadOwner {\n let audio=Audio();weak var renderer:FixedVelocityHarness?\n init(_ renderer:FixedVelocityHarness){self.renderer=renderer;bind()}\n func bind(){\n'+binding+'\n}\n}\n'
    historical={}
    if args.historical_root:
        old=args.historical_root.resolve()/'ios/App/NativeWorldRenderer.swift';data=old.read_bytes();historical[str(old)]=data
        source+='\n'+harness(data.decode(),template,'HistoricalVelocityHarness')
    source+='\n'+before['smoke_native_swim_reload_audio.swift'].decode().replace('// LITERAL_HISTORICAL_CONTROL',HISTORY if historical else '')
    snapshots={str(ROOT/p):hashlib.sha256(b).hexdigest()for p,b in before.items()}
    snapshots.update({p:hashlib.sha256(b).hexdigest()for p,b in historical.items()})
    for relative in ['local-only/site/game/native/models/animations.clips.bin','local-only/site/game/native/foot-animation.json',
                     f'local-only/native-physics/macos-{platform.machine()}/libzgtasa_native_physics.a']:
        p=ROOT/relative;snapshots[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()
    (OUT/'runtime-source.swift').write_text(source)
    with tempfile.TemporaryDirectory(prefix='actual-',dir=OUT)as temporary:
        work=Path(temporary);entry=work/'main.swift';entry.write_text(source);binary=work/'verify'
        command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1',
            '-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),
            *[str(ROOT/f'ios/App/{n}.swift')for n in PHYSICS],str(entry),
            '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
            '-framework','Security','-framework','CoreFoundation','-o',str(binary)]
        build=subprocess.run(command,capture_output=True,text=True,timeout=900)
        (OUT/'build.log').write_text(build.stdout+build.stderr)
        if build.returncode:print(build.stdout+build.stderr);build.check_returncode()
        result=subprocess.run([str(binary),str(ROOT)],capture_output=True,text=True,timeout=120)
        (OUT/'run.log').write_text(result.stdout+result.stderr);print(result.stdout+result.stderr,end='');result.check_returncode()
    unchanged=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in snapshots.items());assert unchanged
    (OUT/'report.json').write_text(json.dumps({'status':'PASS','historicalExecuted':bool(historical),
        'sourceUnchanged':unchanged,'inputSHA256':snapshots,'carrierSHA256':hashlib.sha256(source.encode()).hexdigest(),
        'output':result.stdout,'boundary':'Actual water/flight/animation and native character/query types, real owned CLP, exact GVC reload binding and actual Audio methods. Controlled existing water fixture and inert audio/sample/scheduler adapters. No device, speaker, network, original-game runtime or retail timing claim.'},indent=2)+'\n')

if __name__=='__main__':main()
