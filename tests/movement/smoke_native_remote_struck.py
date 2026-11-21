#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual remote reaction/CLP/metadata owners; authored clips, optional private reference."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--reference',type=Path);parser.add_argument('--prepare-only',action='store_true');args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/remote-struck-171'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePedestrianReaction','NativeRemoteFootAnimation','NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeHumanShots','NativeShotTracers','NativeParticleEffects','NativeOrdinaryShotEffects']
    paths=[ROOT/'ios/App'/(n+'.swift')for n in names]+[Path(__file__).resolve(),Path(__file__).with_suffix('.swift')]
    if args.reference:paths.append(args.reference.resolve())
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    actor=paths[0].read_text()
    common=actor[:actor.index('struct NativeSkinVertex')].replace('import Metal','')
    common+='\nfinal class NativeSkeletalActor {\n'+actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')]+'}\n'
    for path in paths[1:len(names)]:common+='\n'+path.read_text()
    common+='\n'+Path(__file__).with_suffix('.swift').read_text()
    report=dict(status='PREPARED',sourceHashes=frozen,generatedSHA256=hashlib.sha256(common.encode()).hexdigest(),
        scope='Actual CLP decoder, foot/gun/swim/flight/reaction/remote and metadata helpers; type-only skeletal actor boundary. Authored clips and optional private archived scalar fixture; no rendered rig, damage authority or retail claim.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        (out/'main.swift').write_text(common)
        if not args.prepare_only:
            with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(out/'main.swift'),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
            report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-5000:]
            r=subprocess.run([str(out/'gate'),*([str(args.reference.resolve())]if args.reference else[])],capture_output=True,text=True,timeout=60)
            (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr);save()
            assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),completedAt=time.time());save()
        print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
