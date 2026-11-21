#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Remote packet/scene/targeting carrier with authored clocks; no assets or UI."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def block(text,marker):
    start=text.index(marker);at=text.index('{',start)+1;depth=1
    while depth:
        depth+=(text[at]=='{')-(text[at]=='}');at+=1
    return text[start:at]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owned-reference',type=Path,help='Private offline archived interpolation-kernel measurements')
    args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/remote-motion-157'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeMultiplayerClient','NativeWorldRenderer','NativeGameViewController','NativeActorAnimation','NativeMelee','NativeRemoteFootMotion','NativeShotTargeting','NativeSAMPClient','NativeSAMPWorldConnection']
    paths=[ROOT/'ios/App'/(n+'.swift')for n in names]
    paths += [Path(__file__).resolve(),Path(__file__).with_suffix('.swift')]
    paths += [ROOT/'ios/App'/f'{n}.swift'for n in ['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientPedestrians']]
    shot_sources=[ROOT/'ios/App'/f'{n}.swift'for n in ['NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeHumanShots','NativeWeaponFlash']]
    paths += shot_sources
    if args.owned_reference:paths.append(args.owned_reference.resolve())
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    network,renderer,controller,actor,melee=[p.read_text()for p in paths[:5]]
    common='import Foundation\nimport CoreFoundation\nimport simd\n'
    common+='\n'.join(block(network,n)for n in ['struct NativeVehicleSeatSession {','struct RemotePlayer {','struct RemoteVehicle {','struct NativeHealthPrediction {'])
    common+='\n'+block(actor,'struct NativePedestrianMotion {')
    common+='\n'+'\n'.join(block(melee,n)for n in ['struct NativeMeleeProbe {','struct NativeMeleeEvent {','enum NativeMeleeTargeting {'])
    packet=block(network,'    private func updateRows(').replace('ProcessInfo.processInfo.systemUptime','receiptTime')
    fields=renderer[renderer.index('    var remotePlayers: [RemotePlayer]'):renderer.index('    var remoteVehicles: [RemoteVehicle]')]
    scene=fields+'\n'+'\n'.join(block(renderer,n)for n in ['    private static func remoteAppearanceIsFoot(','    private func resetRemoteFootPresentation()','    private func recordRemoteFootPackets()','    func advanceRemoteFootPresentation('])
    # UIKit/Metal/attachment seams are explicit spies. Packet codec, scene
    # admission, frame sampling and target factories are literal source.
    draw=next(line.strip()for line in renderer.splitlines()if line.strip().startswith('let footPosition=remoteSupportPosition(player) ?? player.position'))
    assert 'for player in presentedRemotePlayers {\n            // A passenger' in renderer
    assert 'people: presentedRemotePlayers.map { NativeWeaponEffects.Target' in renderer
    tick=block(controller,'    @objc private func tick(')
    assert tick.index('advanceRemoteFootPresentation(')<tick.index('attack()')
    assert 'renderer.presentedRemotePlayers.map' in controller[controller.index('gameHUD.radar.players ='):][:150]
    hookup=block(controller,'        network.onPlayers =')
    candidate=block(controller,'    private var meleeCandidates:')
    emit=block(controller,'    private func emitWeaponShot(')
    start=emit.index('let candidates=renderer.presentedRemotePlayers.map')
    stream=block(emit[start:],'let candidates=')
    instant=block(emit[emit.index('let candidates=renderer.presentedRemotePlayers.map',start+len(stream)):],'let candidates=')
    legacy=paths[7].read_text();adapter=paths[8].read_text()
    assert 'player.receivedAt=ProcessInfo.processInfo.systemUptime;players[id]=player;publishedPlayers()' in legacy
    assert 'packetReceivedAt:p.receivedAt' in adapter
    harness=Path(__file__).with_suffix('.swift').read_text()
    for key,value in {'COMMON':common,'ACTUAL_PACKET':packet,'ACTUAL_SCENE':scene,'ACTUAL_DRAW':draw,'ACTUAL_HOOKUP':hookup,'ACTUAL_MELEE':candidate,'ACTUAL_STREAM':stream,'ACTUAL_INSTANT':instant}.items():
        assert '// '+key in harness,key
        harness=harness.replace('// '+key,value)
    generated=out/'Gate.swift';generated.write_text(harness)
    report=dict(status='RUNNING',sourceHashes=frozen,generatedSHA256=hashlib.sha256(generated.read_bytes()).hexdigest(),scope='Literal row decoder with explicit receipt-clock seam, actual callback/scene playback/draw-root and target factories; authored5Hz/jitter/lifecycle traces. No real socket, GPU, UIKit, phone, browser UI or retail acceptance.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        npc=[ROOT/'ios/App'/f'{n}.swift'for n in ['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientPedestrians']]
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(paths[5]),str(paths[6]),*map(str,npc),*map(str,shot_sources),str(generated),'-o',str(out/'gate')]
        with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        report['compileExit']=r.returncode
        if r.returncode:report['status']='COMPILE_FAIL';save();raise RuntimeError((out/'compile.log').read_text()[-6500:])
        r=subprocess.run([str(out/'gate')]+([str(args.owned_reference.resolve())]if args.owned_reference else[]),capture_output=True,text=True,timeout=90)
        (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(status='PASS'if r.returncode==0 else'FAIL',exitCode=r.returncode,output=r.stdout+r.stderr);save();print(r.stdout+r.stderr,end='')
        assert r.returncode==0
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save()
        print(json.dumps({k:v for k,v in report.items()if k not in ['sourceHashes','output']},indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
