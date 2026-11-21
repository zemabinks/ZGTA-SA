#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Verify gunshot transients through the actual native spatial mixer."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--prepare-only',action='store_true');parser.add_argument('--compile-only',action='store_true');args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/shot-attack-169'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeRateAudio','NativeVehicleAudioDynamics','NativeVehicleAudioSpatial','NativeAudioPanSweep','NativeVehicleLoopAudio']
    sources=[ROOT/'ios/App'/(name+'.swift')for name in names]+[Path(__file__).with_suffix('.swift')]
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*sources,Path(__file__).resolve()]}
    report=dict(status='PREPARED',sourceHashes=frozen,scope='Actual complete native mixer/PCM/spatial helper and authored samples, offline memory output; no original sound, live audio output, app/UI or retail claim.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        if not args.prepare_only:
            command=['xcrun','swiftc','-parse-as-library','-j','1','-num-threads','1','-whole-module-optimization','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
            with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            report['compileExit']=r.returncode;assert r.returncode==0,(out/'compile.log').read_text()[-6000:]
            if args.compile_only:report['status']='PASS_COMPILE_ONLY'
            else:
                r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=90)
                (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
                assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save()
        print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
