#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compact traffic to registered vehicle entry boundary regression."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__);args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-entry-native-164'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeTrafficVehicleEntry']
    sources=[ROOT/'ios/App'/(n+'.swift')for n in names]+[Path(__file__).with_suffix('.swift')]
    inputs=[*sources,Path(__file__).resolve()]
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Native materialization wait/lifetime policy with authored IDs and model-readiness boundary; no native UI, server transfer, driving, collision, crews or retail acceptance')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
        with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        report['compileExit']=r.returncode;assert r.returncode==0,(out/'compile.log').read_text()[-6000:]
        r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=120)
        (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
        assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save();print(json.dumps(report,indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
