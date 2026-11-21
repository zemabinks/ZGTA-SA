#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Execute actual rider time admission and literal renderer clock/command blocks.

All tracks and geometry are invented. The carrier does not draw with Metal,
schedule real UIKit callbacks, run a server or claim retail acceptance.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse
import hashlib
import json
import os
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth, quoted, escaped = 0, False, False
    for at in range(opening, len(text)):
        c = text[at]
        if quoted:
            if escaped:
                escaped = False
            elif c == '\\':
                escaped = True
            elif c == '"':
                quoted = False
            continue
        if c == '"':
            quoted = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[start:at+1]
    raise ValueError('Unclosed source block: ' + marker)


def carrier(renderer, historical=None):
    draw = block(renderer, '    private func drawActors(')
    begin = draw.index('        let riderTime = ')
    clock = draw[begin:draw.index('        let riderIDs = ', begin)]
    # Select the actual passenger/foot presentation loop, rather than an
    # earlier vehicle-physics loop. Newer renderers share presented roots with
    # targeting; the rider cache/action assertions below remain unchanged.
    loops = ['        for player in presentedRemotePlayers {',
             '        for player in remotePlayers {']
    marker = next(value for value in loops if value+'\n            // A passenger' in draw)
    remote = draw[draw.index(marker):]
    start = remote.index('                let input=NativeRiderAnimation.Input(dead:player.life<=0),playbackKey=')
    passenger_cache = remote[start:remote.index('                let pose:NativeSkeletalActor.Pose', start)]
    passenger_action = block(remote, '                    if remoteRiderActions[player.id] != action {')
    driver = remote[remote.index('            let playbackKey="\\(player.vehicleID'):]
    driver_cache = driver[:driver.index('            if let playback {')]
    driver_action = block(driver, '                if remoteRiderActions[player.id] != action {')
    own_passenger = block(draw, '                if ownRiderPlayback==nil,let playback=NativeRiderPlayback(definition:definition,seat:seat,library:library) {')
    own_driver = block(draw, '                        if ownRiderPlayback==nil,let playback=NativeRiderPlayback(definition:definition,library:library) {')
    completion_driver = block(draw, '                            if frame.state == .stood,let ready=pendingVehicleExit {')
    completion_passenger = block(draw, '                    if sample.state == .stood,let ready=pendingVehicleExit{')
    release = block(draw, '                            if let release=frame.releasedDoor,let damage=')
    old_begin=old_clock=''
    if historical is not None:
        old_draw = block(historical, '    private func drawActors(')
        old_begin = block(historical,'    @discardableResult func beginVehicleExit(').replace('func beginVehicleExit(', 'func beginHistoricalVehicleExit(',1)
        begin = old_draw.index('        let riderTime = ')
        old_clock = old_draw[begin:old_draw.index('        let riderIDs = ', begin)]
    declarations = '\n'.join(line for line in renderer.splitlines() if line.strip().startswith((
        'private var lastRiderDraw:', 'private var riderPoseClock=', 'private var riderMonotonicNow:')))
    clear_line = next(line for line in renderer.splitlines() if 'lastRiderDraw=0;' in line)
    reset = block(renderer, '    func resetMultiplayerSession()')
    assert '        discardOwnedVehicle()' in reset
    revoke = block(renderer, '    func revokeVehicleForServerPlacement()')
    assert 'discardOwnedVehicle()' in revoke
    enter = block(renderer, '    func enter(_ source: RemoteVehicle, kind: String)')
    enter_reset = next(line for line in enter.splitlines() if 'vehicleExitSerial &+= 1' in line)
    passenger_enter = block(renderer, '    @discardableResult func enterPassenger(')
    passenger_reset = next(line for line in passenger_enter.splitlines() if 'vehicleExitSerial &+= 1' in line)
    # Fail closed on a moved/extra consumer or changed fallback ownership.
    traffic = block(draw, '        for seat in NativeTrafficOccupants.followOrder(trafficOccupantSeats) {')
    assert traffic.count('owner.update(interval:riderPoseInterval,') == 1
    assert traffic.count('.update(interval:riderPoseInterval,') == 1
    detached = block(draw, '        for entry in trafficRiderRetention.detached {')
    assert detached.count('owner.update(interval:riderPoseInterval,') == 1
    human_draw=draw.replace(traffic,'',1).replace(detached,'',1)
    assert human_draw.count('.update(interval:riderPoseInterval,') == 9
    assert draw.count('.update(interval:riderPoseInterval,') == 11
    traffic_owner=(ROOT/'ios/App/NativeTrafficRiderActor.swift').read_text()
    assert traffic_owner.count('animator.update(interval:interval,') == 1
    assert traffic_owner.count('fall.update(delta:delta)') == 1
    foot_clocked = 'animator.update(at:riderTime,' in draw
    assert foot_clocked,'Remote foot retains its independently owned timestamp adapter'
    assert draw.count('.update(delta:riderDelta,') == 0
    assert draw.count('delta:riderDelta,') == 0
    assert draw.count('presentationDelta:riderDelta,') == 1 # actual remote-bike presentation owner
    if foot_clocked:
        # NPCs use the same admitted display timestamp but own a separate
        # animation collection. Keep the human clock assertion scoped to its
        # actual loop, and fail closed if either consumer moves or multiplies.
        human, ambient = draw.split('        for npc in presentedAmbientPedestrians {', 1)
        assert human.count('animator.update(at:riderTime,') == 1
        assert ambient.count('animator.update(at:riderTime,') == 1
    assert draw.count('playback.enter(') == 4 and draw.count('playback.leave(') == 2
    assert 'guard let drawable = view.currentDrawable' not in draw
    drawable = renderer.index('view.currentDrawable')
    draw_call = renderer.index('drawActors(encoder:', drawable)
    assert drawable < draw_call
    return r'''
import Foundation
import simd
// Test adapters: no UIKit, device or real asynchronous dispatch occurs here.
enum AppState {case active,inactive}
final class UIApplication {static let shared=UIApplication();var applicationState:AppState = .active}
final class View {var window:Int?=1}
final class ProcessInfo {static let processInfo=ProcessInfo();var systemUptime:Double=0}
final class DispatchQueue {
    static let main=DispatchQueue();var queued:[()->Void]=[]
    func async(execute:@escaping()->Void){queued.append(execute)}
    func flush(){let all=queued;queued=[];all.forEach{$0()}}
}
struct RenderClock {var resets=0;mutating func reset(){resets+=1}}
final class RemoteFootClockSpy {var resets=0;func resetDisplayClock(){resets+=1}}
final class Actor {}
struct Player {
    var id="remote",vehicleID:String?="car",ridingSeat=1,action=1,life=100
    var vehicleDamage=""
}
struct Vehicle {var damage=""}
struct Shared {var vehicle=Vehicle()}
enum NativeVehicleDamage {
    struct Decoded {var open=Array(repeating:false,count:8)}
    static func decode(_ text:String)->Decoded?{Decoded()}
}
final class DamageState {
    struct Door {var open:Double=1}
    var doors=Array(repeating:Door(),count:8),releases:[(Int,Double)]=[]
    func isOpen(_ part:Int)->Bool{false}
    func letGo(_ part:Int,angle:Double){releases.append((part,angle))}
}
final class DamageController {let state=DamageState()}
final class Ground {let damageController:DamageController?=DamageController();func exit(){}}
final class Coupling {func setOwnedVehicle(_ id:String?){}}
final class RendererCarrier {
''' + declarations + r'''
    let remoteGunAudio=NativeRemoteGunAudio(),weaponFlashes=NativeWeaponFlash()
    var onRemoteGunAudio:((NativeRemoteGunAudio.Event)->Void)?
    var localShotVehicles=[42],localShotVehiclesAt:Double=1,localShotVehicleSource:String?="old-source"
    var now:Double=0
    let view=View();var renderClock=RenderClock()
    var remoteServerTimeOffsetMilliseconds:Double?=1
    var driving=true,pendingVehicleExit:(()->Void)?,pendingExitPlacement:(()->Void)?
    var vehicleExitSerial:UInt64=0,currentVehicleID:String?="same-id"
    var ownRiderPlayback:NativeRiderPlayback?,ownRiderFeet:Int?,ownRiderSide = -1
    var ownRiderCapture:Int?,ownRiderPrevious:Int?,ownRiderAnimation:Int?
    var passengerAccumulator:Double=0,drivingSpeed:Float=0,flightVerticalSpeed:Float=0
    var vehiclePitch:Float=0,vehicleFallbackRoll:Float=0,activeModelOrigin:Float=0,pendingVehicleSnapshot:Int?
    // Opaque pre130 carrier for the optional historical control only.
    var pendingVehicleBodyPose:Int?
    var activeHandling:Int?,vehicleKind="car",vehicleHorn=false,vehicleSiren=false,steeringInput:Float=0
    var vehicleWorkingControl:Float=0,vehicleHop=false,riderDoorHolds:[String:[Int:Double]]=[:]
    var vehicleCoupling:Coupling?=Coupling()
    var riderDefinitions:NativeRiderDefinitions?,activeVehicleModel="invented",passengerSeat:Int?
    var isPassenger:Bool{passengerSeat != nil}
    var passengerFrame:Shared?,groundVehicle:Ground?=Ground()
    var remoteRiderPlayback:[String:(String,NativeRiderPlayback)]=[:],remoteRiderActions:[String:Int]=[:]
    var remoteRiderCapture:[String:Int]=[:],remoteRiderPrevious:[String:Int]=[:]
    var remoteFootAnimations:[String:(String,RemoteFootClockSpy)]=[:]
    // Explicit presentation-owner boundary; world-root playback is exercised
    // with its actual implementation by smoke_native_remote_motion.py.
    var remoteRootClockResets=0
    func resetRemoteFootPresentation(){remoteRootClockResets+=1}
    init(){riderMonotonicNow = {[unowned self] in self.now}}
    static func sharedDoorOpen(_ part:Int?,damage:String)->Bool{false}
''' + block(renderer, '    func resetDisplayClock()') + '\n' + block(renderer, '    @discardableResult func beginVehicleExit(') + '\n' + old_begin + '\n' + block(renderer,'    private func discardOwnedVehicle()') + '\n' + revoke + r'''
    func resetOwnerForTest(){
''' + next(line for line in reset.splitlines() if line.strip()=='discardOwnedVehicle()') + r'''
    }
    func admitOwnerForTest(_ value:NativeRiderPlayback,passenger:Bool=false){
        if passenger {
''' + passenger_reset + r'''
        }else{
''' + enter_reset + r'''
        }
        driving=true;currentVehicleID="same-id";ownRiderPlayback=value
    }
    func clearPoseClock(){
''' + clear_line + r'''
    }
    func successfulDraw()->(Double,Double,NativeRiderPoseClock.Interval){
''' + clock + r'''
        return (riderTime,riderDelta,riderPoseInterval)
    }
    func ownPassenger(_ interval:NativeRiderPoseClock.Interval,at riderTime:Double,definition:NativeRiderDefinitions.Definition,library:NativeSkeletalAnimationLibrary,dead:Bool=false)->NativeRiderPlayback.Frame? {
        let seat=passengerSeat ?? 1,sourceSeat=definition.seats[seat],frame=Shared()
''' + own_passenger + r'''
        return ownRiderPlayback?.update(interval:interval,input:.init(dead:dead))
    }
    func ownDriver(_ interval:NativeRiderPoseClock.Interval,at riderTime:Double,age time:Double,definition:NativeRiderDefinitions.Definition,library:NativeSkeletalAnimationLibrary,input:NativeRiderAnimation.Input = .init())->NativeRiderPlayback.Frame? {
        let sourceSeat=definition.seats[0],car=matrix_identity_float4x4,entryOrigin=SIMD3<Float>(-1,0,0)
''' + own_driver + r'''
        return ownRiderPlayback?.update(interval:interval,input:input)
    }
    func passenger(_ interval:NativeRiderPoseClock.Interval,at riderTime:Double,player:Player,vehicleID:String,model:String="invented",actor:Actor,definition:NativeRiderDefinitions.Definition,library:NativeSkeletalAnimationLibrary)->NativeRiderPlayback.Frame? {
        let shared=Shared()
''' + passenger_cache + r'''
        if let playback {
            let action=player.action&63,sourceSeat=definition.seats[player.ridingSeat]
''' + passenger_action + r'''
            return playback.update(interval:interval,input:input)
        }
        return nil
    }
    func driver(_ interval:NativeRiderPoseClock.Interval,at riderTime:Double,player:Player,model:String="invented",actor:Actor,source:NativeRiderDefinitions.Definition,library:NativeSkeletalAnimationLibrary)->NativeRiderPlayback.Frame? {
        let sourceSeat=source.seats[0],input=NativeRiderAnimation.Input(dead:player.life<=0)
''' + driver_cache + r'''
        if let playback {
            let action=player.action&63
''' + driver_action + r'''
            return playback.update(interval:interval,input:input)
        }
        return nil
    }
    func consumeDriver(_ frame:NativeRiderPlayback.Frame){
''' + release + '\n' + completion_driver + r'''
    }
    func consumePassenger(_ sample:NativeRiderPlayback.Frame){
''' + completion_passenger + r'''
    }
}
''' + (r'''
final class HistoricalRendererCarrier {
    private var lastRiderDraw: Double = 0
    func successfulDraw(at time:Double)->Double {
        ProcessInfo.processInfo.systemUptime=time
''' + old_clock + r'''
        return riderDelta
    }
}
''' if historical is not None else '')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-root',type=Path,help='Optional frozen Core115 checkout for literal historical controls, read only.')
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/research/rider-timed-116/gate')
    args=parser.parse_args()
    out=Path(os.path.abspath(args.out))
    if not out.is_relative_to(ROOT/'local-only') or any(p.is_symlink() for p in [out,*out.parents]):
        raise SystemExit('Use a regular local-only output directory.')
    if out.exists():raise SystemExit('Output exists; retain immutable prior evidence and choose a new output.')
    out.mkdir(parents=True,mode=0o700)
    old=args.historical_root.resolve() if args.historical_root else None
    if old==ROOT:raise SystemExit('Historical controls require a separate frozen checkout; current is never a historical substitute.')
    paths=[ROOT/'ios/App'/name for name in ['NativeSkeletalActor.swift','NativeRiderAnimation.swift',
        'NativeBoardingAnimation.swift','NativeRiderPlayback.swift','NativeWorldRenderer.swift']]
    paths += [ROOT/'tests/vehicles/smoke_native_rider_clock.swift',Path(__file__).resolve(),ROOT/'tests/vehicles/smoke_native_rider_timed.swift']
    shot_sources=[ROOT/'ios/App'/name for name in ['NativeAmbientPedestrianProtocol.swift','NativeAmbientTrafficProtocol.swift','NativeOrdinaryShot.swift','NativeRemoteGunAudio.swift','NativeWeaponFlash.swift']]
    paths += shot_sources
    if old is not None:
        paths += [old/'ios/App'/name for name in ['NativeRiderPlayback.swift','NativeWorldRenderer.swift',
            'NativeRiderAnimation.swift','NativeBoardingAnimation.swift']]
    before={str(p):sha(p) for p in paths}
    current=paths[3].read_text();historical=None
    if old is not None:
        historical=(old/'ios/App/NativeRiderPlayback.swift').read_text()
        consumer=block(current,'    func update(delta dt:Double,')
        assert consumer==block(historical,'    func update(delta dt:Double,'),'Direct delta consumer changed.'
        name='NativeRiderAnimation.swift'
        assert block((ROOT/'ios/App'/name).read_text(),'    func update(delta dt:Double,')==block((old/'ios/App'/name).read_text(),'    func update(delta dt:Double,'),'Legacy rider equations changed.'
        name='NativeBoardingAnimation.swift'
        assert (ROOT/'ios/App'/name).read_bytes()==(old/'ios/App'/name).read_bytes(),'Legacy boarding equations changed.'
    library=paths[0].read_text().split('struct NativeSkeletalLayer {',1)[0].replace('import Metal\n','')
    fixture=paths[5].read_text().replace('@main enum RiderClockSmoke {','enum RiderClockSmoke {')
    snapshots={'ActualClipLibrary.swift':library,'RiderAnimation.swift':paths[1].read_text(),
        'BoardingAnimation.swift':paths[2].read_text(),'Playback.swift':current,
        'Fixtures.swift':fixture,'RendererCarrier.swift':carrier(paths[4].read_text(),(old/'ios/App/NativeWorldRenderer.swift').read_text() if old else None),
        'TimedTests.swift':paths[7].read_text()}
    for path in shot_sources:snapshots[path.name]=path.read_text()
    if historical is not None:
        snapshots['HistoricalPlayback.swift']=historical.replace('final class NativeRiderPlayback {','final class HistoricalRiderPlayback {',1)
    for name,text in snapshots.items():(out/name).write_text(text)
    binary=out/'verify'
    command=['xcrun','swiftc','-Onone','-whole-module-optimization','-j','1','-num-threads','1','-module-cache-path',str(out/'modules'),
        *[str(out/name) for name in snapshots],'-o',str(binary)]
    if historical is not None:command[2:2]=['-D','HISTORICAL_CONTROLS']
    start=time.monotonic()
    with (out/'compile.log').open('w') as log:
        process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        (out/'compiler-process.json').write_text(json.dumps(dict(pid=process.pid,processGroup=process.pid,command=command))+'\n')
        try:compile_exit=process.wait(timeout=900)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL);process.wait()
            (out/'compile-timeout.json').write_text(json.dumps(dict(timeoutSeconds=900,killedOwnProcessGroup=process.pid))+'\n')
            raise
    if compile_exit:
        print((out/'compile.log').read_text()[-6000:])
        raise RuntimeError('Actual-source carrier compile failed; see '+str(out/'compile.log'))
    ran=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
    (out/'runtime.log').write_text(ran.stdout+ran.stderr)
    data=json.loads(ran.stdout)
    after={p:sha(Path(p)) for p in before}
    assert before==after,'Source or fixture changed during test.'
    report=dict(status='PASS' if ran.returncode==0 else 'FAIL',compileExit=compile_exit,runExit=ran.returncode,
        seconds=time.monotonic()-start,sourceHashes=before,sourceUnchanged=True,
        historicalExecuted=data.get('historicalExecuted',False),historicalRequested=old is not None,directDeltaConsumerUnchanged=True if old else None,
        literalRendererClockAndCommandBlocks=True,historicalClassRenameOnly=True if old else None,result=data,
        scope='Actual CLP1 reader/planner/playback, actual clock and extracted literal renderer admission/cache/completion blocks; invented tracks and adapters. No UIKit/Metal/device/server/retail acceptance.')
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))
    if ran.returncode:raise SystemExit(ran.returncode)
    assert data['historicalExecuted']==(old is not None),'Historical control reporting mismatch.'


if __name__=='__main__':main()
