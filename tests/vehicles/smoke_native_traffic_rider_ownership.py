#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual driver lifetime, NPC matching/correction and full raw-pose adapter."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--prepare-only',action='store_true');args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-rider-ownership-168'/str(time.time_ns());out.mkdir(parents=True)
    app=ROOT/'ios/App';tests=ROOT/'tests/vehicles'
    names=['NativeTrafficOccupants','NativeTrafficRiderRetention','NativeTrafficRiderHandoff','NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientPedestrians']
    ownership=[app/(n+'.swift')for n in names]+[tests/'smoke_native_traffic_rider_ownership.swift']
    actor_names=['NativeActorAnimation','NativeSkeletalActor','NativeRiderAnimation','NativeTrafficOccupants','NativeTrafficRiderFall','NativeTrafficRiderActor']
    actor=[app/(n+'.swift')for n in actor_names]
    foot=app/'NativeFootAnimation.swift';clock=app/'NativeRiderPlayback.swift'
    # Literal production type/clock boundaries, excluding unrelated controllers.
    blend=foot.read_text().split('struct NativeFootAnimationStyle {',1)[0]
    timing=clock.read_text().split('/// Public bA phase plans',1)[0]
    fixture=tests/'smoke_native_traffic_rider_actor.swift'
    renderer=app/'NativeWorldRenderer.swift';text=renderer.read_text()
    begin=text.index('        for seat in NativeTrafficOccupants.followOrder(trafficOccupantSeats) {')
    begin=text.index('            let identity=',begin)
    end=text.index('            let position=SIMD3<Float>(car.body.position)',begin)
    cache=text[begin:end]
    assert cache.count('trafficRiderOwners[seat.targetID]')==2 and 'old.bindCompatible(actor)'in cache
    cache_source='''final class TrafficRiderOwnerCache {
    var source="authored-source"
    var trafficRiderOwners:[String:NativeTrafficRiderActor]=[:]
    func fixedCJSourceIdentity()->String{source}
    func bind(seat:NativeTrafficOccupants.Seat,name:String,actor:NativeSkeletalActor,definition:NativeRiderDefinitions.Definition,library:NativeSkeletalAnimationLibrary)->NativeTrafficRiderActor {
'''+cache+'''        return owner
    }
}
'''
    (out/'actual-renderer-cache.swift').write_text(cache_source)
    (out/'actor.swift').write_text('\n'.join([blend,timing,*[p.read_text()for p in actor],cache_source,fixture.read_text()]))
    inputs=[*ownership,*actor,foot,clock,fixture,renderer,Path(__file__).resolve()]
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='PREPARED',sources=frozen,results=[],compilerInvoked=False,scope='Actual production lifetimes/matcher/NPC correction and complete raw-pose adapter/decoder with authored data. Metal buffer creation, no rendered frame, full renderer, live server, physical device or original-game fidelity claim.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        if not args.prepare_only:
            report['compilerInvoked']=True
            for name,files in [('ownership',ownership),('actor',[out/'actor.swift'])]:
                binary=out/name
                command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-j','1','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,files),'-o',str(binary)]
                with(out/(name+'-compile.log')).open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
                assert r.returncode==0,(out/(name+'-compile.log')).read_text()[-6500:]
                r=subprocess.run([str(binary)],capture_output=True,text=True,timeout=90)
                (out/(name+'-runtime.log')).write_text(r.stdout+r.stderr)
                report['results'].append(dict(name=name,exitCode=r.returncode,output=r.stdout+r.stderr));save()
                assert r.returncode==0,r.stdout+r.stderr
            report['status']='PASS'
    except BaseException as e:report.update(status='FAIL',error=repr(e));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save()
        print(json.dumps({k:v for k,v in report.items()if k!='sources'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
