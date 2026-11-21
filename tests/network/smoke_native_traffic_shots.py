#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual compact traffic observation routing and car-relative shot origins."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--prepare-only',action='store_true');args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-shots-169'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientTrafficProtocol','NativeAmbientTrafficRoads','NativeAmbientTraffic','NativeAmbientTrafficMotion','NativeAmbientTrafficPresentation','NativeAmbientTrafficScene','NativeTrafficShotSource','NativeOrdinaryShot','NativeShotTracers','NativeParticleEffects','NativeOrdinaryShotEffects','NativeVehicleAudioDynamics','NativeShotAudioPlan','NativeAudioPanSweep','NativeBulletPass']
    sources=[ROOT/'ios/App'/(name+'.swift')for name in names]+[Path(__file__).with_suffix('.swift')]
    inputs=[*sources,Path(__file__).resolve()];frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='PREPARED',sourceHashes=frozen,scope='Complete production typed traffic scene/receiver/origin helper; authored roads, cars and optional holder callback. No renderer, original poses, audio playback, damage, sockets or retail claim.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        if not args.prepare_only:
            command=['xcrun','swiftc','-parse-as-library','-j','1','-num-threads','1','-whole-module-optimization','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
            with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            report['compileExit']=r.returncode;assert r.returncode==0,(out/'compile.log').read_text()[-6000:]
            r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=90)
            (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
            assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save()
        print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
