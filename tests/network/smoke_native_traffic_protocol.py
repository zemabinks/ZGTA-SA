#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Literal independent traffic codec with invented semantic packet fixtures."""
from pathlib import Path
import hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-protocol-162'/str(time.time_ns());out.mkdir(parents=True)
    sources=[ROOT/'ios/App'/(name+'.swift')for name in ['NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol']]+[Path(__file__).with_suffix('.swift')]
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*sources,Path(__file__).resolve()]}
    report=dict(status='RUNNING',sourceHashes=frozen,scope=__doc__)
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
        with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        report['compileExit']=r.returncode;assert r.returncode==0,(out/'compile.log').read_text()[-6000:]
        r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=60);(out/'runtime.log').write_text(r.stdout+r.stderr)
        report.update(exitCode=r.returncode,output=r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save();print(json.dumps(report,indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
