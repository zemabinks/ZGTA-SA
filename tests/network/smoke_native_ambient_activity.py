#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual native NPC scripts, optional original clips and archived policy data."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original-clips',type=Path,help='Owner-local converted CLP library; never downloaded or published')
    parser.add_argument('--owned-reference',type=Path,help='Private normalized archived activity observations')
    args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/ambient-activity-160'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePedestrianReaction','NativeAmbientPedestrianProtocol','NativeAmbientPedestrianAnimation','NativeSAMPSkinCatalog','NativeWorldRenderer']
    paths=[ROOT/'ios/App'/(name+'.swift')for name in names]
    paths += [Path(__file__).resolve(),Path(__file__).with_suffix('.swift'),Path(__file__).with_name('smoke_native_ambient_activity_reference.swift')]
    for option,limit in [(args.original_clips,64*1048576),(args.owned_reference,8*1048576)]:
        if option:assert option.is_file() and option.stat().st_size<=limit;paths.append(option.resolve())
    reference_extras=[]
    if args.owned_reference:
        envelope=json.loads(args.owned_reference.read_text())
        for filename in ['cases.json','authored-durations.json']:
            value=args.owned_reference.parent/filename
            assert value.is_file() and value.stat().st_size<=8*1048576
            assert hashlib.sha256(value.read_bytes()).hexdigest()==envelope['parentFiles'][filename]['sha256']
            paths.append(value.resolve());reference_extras.append(str(value.resolve()))
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    actor=paths[0].read_text()
    common=actor[:actor.index('struct NativeSkinVertex')].replace('import Metal','')
    common+='\nfinal class NativeSkeletalActor {\n'+actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')]+'}\n'
    for p in paths[1:6]:common+='\n'+p.read_text()
    (out/'Common.swift').write_text(common)
    source=paths[7].read_text();renderer=paths[9].read_text()
    assert 'id:npc.id,seed:npc.seed,femaleActivity:sampSkinCatalog?.femaleActivity(forModel:legacyPedStyles[name] ?? name,sourceIdentity:fixedCJSourceIdentity()) ?? false,'in renderer
    assert 'waitingLinkKind:npc.waitingLinkKind)'in renderer
    assert source.index('animator.revive()')<source.index('activity.update(now:now'),'Authoritative revive must precede new live scripts'
    planner='import Foundation\n'+source[source.index('struct NativeAmbientPedestrianActivity {'):]
    # Replay fixtures start partway through an actor lifetime. Only the
    # captured first-mood field is writable in this separate policy carrier.
    (out/'PlannerCarrier.swift').write_text(planner.replace('private(set) var firstMood','var firstMood'))
    report=dict(status='RUNNING',sourceHashes=frozen,results=[],scope='Literal NPC/common controller and CLP decoder; authored clips plus optional owner-local original-resource and archived-policy checks. No rendered/retail/hardware acceptance.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status'],sourcesHeld=report.get('sourcesHeld')),indent=2)+'\n')
    save()
    try:
        commands=[('actual-common-activities',[out/'Common.swift',paths[6],paths[7],paths[8],paths[11]],([str(args.original_clips.resolve())]if args.original_clips else []))]
        if args.owned_reference:commands.append(('archived-activity-policy',[out/'PlannerCarrier.swift',paths[12]],[str(args.owned_reference.resolve()),*reference_extras]))
        for name,sources,arguments in commands:
            row=dict(name=name,startedAt=time.time());report['results'].append(row);save()
            command=['xcrun','swiftc','-parse-as-library','-Onone','-whole-module-optimization','-j','1','-num-threads','1','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/name)]
            with(out/(name+'-compile.log')).open('x')as log:r=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            row['compileExit']=r.returncode;save()
            if r.returncode:raise RuntimeError((out/(name+'-compile.log')).read_text()[-6500:])
            r=subprocess.run([str(out/name),*arguments],capture_output=True,text=True,timeout=120)
            (out/(name+'-runtime.log')).write_text(r.stdout+r.stderr)
            row.update(exitCode=r.returncode,output=r.stdout+r.stderr,seconds=time.time()-row['startedAt']);save();assert r.returncode==0,name
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),completedAt=time.time());save()
        print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'},indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
