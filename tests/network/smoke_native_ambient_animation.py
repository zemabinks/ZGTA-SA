#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual NPC/common pose owner; authored CLP and optional private references."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owned-reference',type=Path,help='Private normalized archived NPC policy observations; never fetched or published')
    parser.add_argument('--historical-root',type=Path,help='Separate frozen pre-fix renderer/remote-controller source for a negative witness')
    args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/ambient-animation-159'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePedestrianReaction','NativeAmbientPedestrianProtocol','NativeAmbientPedestrianAnimation','NativeWorldRenderer']
    paths=[ROOT/'ios/App'/(name+'.swift')for name in names]
    paths += [Path(__file__).resolve(),Path(__file__).with_suffix('.swift'),Path(__file__).with_name('smoke_native_ambient_animation_reference.swift')]
    if args.owned_reference:
        assert args.owned_reference.is_file() and args.owned_reference.stat().st_size<=8*1048576
        paths.append(args.owned_reference.resolve())
    historical=None
    if args.historical_root:
        historical=args.historical_root.resolve();assert historical!=ROOT
        for name in names[:6]:
            p=historical/'ios/App'/(name+'.swift');assert p.read_bytes()==(ROOT/'ios/App'/p.name).read_bytes(),'Historical common controller changed'
            paths.append(p)
        paths += [historical/'ios/App/NativeRemoteFootAnimation.swift',historical/'ios/App/NativeWorldRenderer.swift']
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    actor=paths[0].read_text()
    common=actor[:actor.index('struct NativeSkinVertex')].replace('import Metal','')
    common+='\nfinal class NativeSkeletalActor {\n'+actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')]+'}\n'
    for p in paths[1:6]:common+='\n'+p.read_text()
    (out/'Common.swift').write_text(common)
    source=paths[7].read_text();renderer=paths[8].read_text()
    assert 'animation:NativeAmbientPedestrianAnimation' in renderer
    assert 'var drawPosition=npc.position,drawHeading=npc.heading' in renderer
    assert 'let snapshot=NativeAmbientPedestrianAnimation.Snapshot(position:drawPosition,heading:drawHeading,' in renderer
    assert 'guard ambientPedestrians.acceptRider(id:npc.id,generation:npc.generation,' in renderer
    assert 'speed:hypot(npc.velocity.x,npc.velocity.y),flags:npc.flags,state:npc.state,' in renderer
    assert 'life:npc.dead ? 0:100' not in renderer,'NPCs must not acquire human-health heuristics'
    tests=paths[10].read_text();extra=[]
    if historical:
        old=(historical/'ios/App/NativeWorldRenderer.swift').read_text()
        start=old.index('            let speed=hypot(npc.velocity.x,npc.velocity.y)')
        end=old.index('            if let state=npc.state',start)
        constructor=old[start:end]
        assert 'life:npc.dead ? 0:100,down:npc.down ? 1:0)'in constructor
        witness='''import Foundation
import simd
private struct HistoricalNPC {
    var position=SIMD3<Double>.zero,velocity=SIMD3<Double>.zero
    var heading=0.0,dead=false,down=true
    var state:NativeAmbientPedestrianProtocol.State?
}
private func historicalSnapshot(_ npc:HistoricalNPC,_ animator:NativeRemoteFootAnimation)->NativeRemoteFootAnimation.Snapshot {
''' + constructor + '''
    return snapshot
}
func verifyHistoricalNPCWitness(_ library:NativeSkeletalAnimationLibrary) {
    let animator=NativeRemoteFootAnimation(library:library,style:.init(),weapons:[:],random:{0.25})
    let snapshot=historicalSnapshot(HistoricalNPC(),animator)
    _=animator.update(at:10,active:true,snapshot:snapshot)
    for frame in 1...300{_=animator.update(at:10+Double(frame)/60,active:true,snapshot:snapshot)}
    NPCAnimationCandidateTests.check(!animator.animator.dead && !animator.animator.floored,"Historical renderer unexpectedly holds server down")
    print("NEGATIVE_WITNESS frozen renderer snapshot and actual human wrapper automatically recover while NPC down remains set")
}
'''
        (out/'HistoricalWitness.swift').write_text(witness)
        extra=[historical/'ios/App/NativeRemoteFootAnimation.swift',out/'HistoricalWitness.swift']
        marker='        print("PASS NPC animation candidate:';assert marker in tests
        tests=tests.replace(marker,'        verifyHistoricalNPCWitness(library)\n'+marker,1)
    (out/'Tests.swift').write_text(tests)
    spy=re.sub(r'\bNativeFootAnimation\b','NPCFootSpy',source).replace('private var ','var ').replace('private func advance(','func advance(')
    (out/'PolicyCarrier.swift').write_text(spy)
    report=dict(status='RUNNING',sourceHashes=frozen,results=[],historicalRequested=historical is not None,archivedReferenceRequested=args.owned_reference is not None,
        scope='Actual NPC/common controller and CLP decoder with authored tracks; optional frozen renderer/human-wrapper negative witness and separate mock-controller policy comparison. No GPU/UI/device or retail acceptance.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status'],sourcesHeld=report.get('sourcesHeld')),indent=2)+'\n')
    save()
    try:
        commands=[('actual-common-controller',[out/'Common.swift',paths[6],paths[7],out/'Tests.swift',*extra],[])]
        if args.owned_reference:commands.append(('archived-policy-calls',[paths[5],paths[6],out/'PolicyCarrier.swift',paths[11]],[str(args.owned_reference.resolve())]))
        for name,sources,arguments in commands:
            row=dict(name=name,startedAt=time.time());report['results'].append(row);save()
            command=['xcrun','swiftc','-parse-as-library','-Onone','-whole-module-optimization','-j','1','-num-threads','1','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/name)]
            with(out/(name+'-compile.log')).open('x')as log:r=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            row['compileExit']=r.returncode;save()
            if r.returncode:raise RuntimeError((out/(name+'-compile.log')).read_text()[-6500:])
            r=subprocess.run([str(out/name),*arguments],capture_output=True,text=True,timeout=90)
            (out/(name+'-runtime.log')).write_text(r.stdout+r.stderr)
            row.update(exitCode=r.returncode,output=r.stdout+r.stderr,seconds=time.time()-row['startedAt']);save();assert r.returncode==0,name
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),completedAt=time.time());save()
        print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'},indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
