#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual local pellet resolver; authored scenes and optional private observations."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference',type=Path);args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/local-shots-172'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeLocalShotMesh','NativeLocalShotPackets']
    sources=[ROOT/'ios/App'/(n+'.swift')for n in names]+[Path(__file__).with_suffix('.swift')]
    inputs=[*sources,Path(__file__).resolve()]+([args.reference.resolve()]if args.reference else[])
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Actual ray/capsule/piece/pellet/grouping, vehicle triangle BVH/occupant selection and packet helpers; authored camera/world/mesh inputs plus optional archived scalar/kernel cases. No original asset mesh, GPU renderer, socket, damage authority or retail claim')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        with(out/'compile.log').open('x')as log:r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-num-threads','1','-whole-module-optimization','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=240)
        report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-5000:]
        r=subprocess.run([str(out/'gate'),*([str(args.reference.resolve())]if args.reference else[])],capture_output=True,text=True,timeout=90)
        report.update(exitCode=r.returncode,output=r.stdout+r.stderr);(out/'runtime.log').write_text(r.stdout+r.stderr);save();assert r.returncode==0,r.stdout+r.stderr
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()),completedAt=time.time());save();print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
