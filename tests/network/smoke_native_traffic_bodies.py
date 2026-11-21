#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual Rapier traffic chassis ownership, model lifetime and rendering basis."""
from pathlib import Path
import hashlib,json,os,platform,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-bodies-164'/str(time.time_ns());out.mkdir(parents=True)
    files=[ROOT/'ios/App'/f'{name}.swift'for name in ['SwiftRapierWorld','NativeAmbientTrafficBodies']]+[Path(__file__).with_suffix('.swift')]
    library=ROOT/'local-only/native-physics'/('macos-'+platform.machine())/'libzgtasa_native_physics.a'
    inputs=[*files,library,Path(__file__).resolve()];frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope=__doc__)
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        args=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*map(str,files),'-L',str(library.parent),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(out/'gate')]
        with(out/'compile.log').open('x')as log:result=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        report['compileExit']=result.returncode
        if result.returncode:report['status']='COMPILE_FAIL';save();raise RuntimeError((out/'compile.log').read_text()[-6000:])
        result=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=60);(out/'runtime.log').write_text(result.stdout+result.stderr)
        report.update(status='PASS'if result.returncode==0 else'FAIL',exitCode=result.returncode,output=result.stdout+result.stderr);save();print(result.stdout+result.stderr,end='');assert result.returncode==0
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save()
    assert report['sourcesHeld']
if __name__=='__main__':main()
