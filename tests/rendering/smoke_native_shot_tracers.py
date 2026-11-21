#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Render and read back actual native tracer shader output with authored lines."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--prepare-only',action='store_true');parser.add_argument('--require-gpu',action='store_true');args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/shot-tracer-gpu-169'/str(time.time_ns());out.mkdir(parents=True)
    sources=[ROOT/'ios/App/NativeShotTracers.swift',ROOT/'ios/App/NativeShotTracerRenderer.swift',Path(__file__).with_suffix('.swift')]
    shader=ROOT/'ios/App/NativeShotTracerShaders.metal'
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in [*sources,shader,Path(__file__).resolve()]}
    report=dict(status='PREPARED',sourceHashes=frozen,scope='Actual complete tracer pool/Metal renderer/shader and GPU stored-pixel readbacks; authored lines, no original scene, Simulator, physical iPhone, audio or retail claim.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        if not args.prepare_only:
            command=['xcrun','swiftc','-parse-as-library','-j','1','-num-threads','1','-whole-module-optimization','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
            with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            report['compileExit']=r.returncode;assert r.returncode==0,(out/'compile.log').read_text()[-6000:]
            r=subprocess.run([str(out/'gate'),str(shader),str(out),*(['--require-gpu']if args.require_gpu else[])],capture_output=True,text=True,timeout=120)
            (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
            assert r.returncode==0,r.stdout+r.stderr;report['status']='SKIP_GPU'if r.stdout.startswith('SKIP')else'PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save()
        print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
