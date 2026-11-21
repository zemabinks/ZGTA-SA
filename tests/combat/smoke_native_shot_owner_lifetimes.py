#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual shot-owner admission ledger, independent of render/packet clocks."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, time
ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only',action='store_true')
    args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/shot-owner-lifetimes-175'/str(time.time_ns());out.mkdir(parents=True)
    paths=[ROOT/'ios/App/NativeShotOwners.swift',Path(__file__).with_suffix('.swift'),Path(__file__).resolve()]
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    report=dict(status='PREPARED',startedAt=time.time(),sourceHashes=frozen,scope='Complete actual admission ledger and authored identities/lifecycle transitions; no renderer, transport, physics, clock, App or retail acceptance')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        if not args.prepare_only:
            with(out/'compile.log').open('x')as log:
                r=subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths[:2]),'-o',str(out/'gate')],stdout=log,stderr=subprocess.STDOUT,timeout=180)
            report['compileExit']=r.returncode;save();assert r.returncode==0,(out/'compile.log').read_text()[-4000:]
            r=subprocess.run([str(out/'gate')],capture_output=True,text=True,timeout=30)
            report.update(exitCode=r.returncode,output=r.stdout+r.stderr);save();assert r.returncode==0,report['output'];report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in frozen.items()),completedAt=time.time());save();print({k:v for k,v in report.items()if k!='sourceHashes'})

if __name__=='__main__':main()
