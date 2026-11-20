#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual bounded world preparation, Metal resources and literal scene admission."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import time
ROOT=Path(__file__).resolve().parents[2]

def function(text, marker):
    start=text.index(marker);opening=text.index('{',start);depth=1;end=opening+1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end].replace('private ','')

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--require-gpu",action="store_true");args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/world-streaming-155'/str(time.time_ns());out.mkdir(parents=True)
    renderer=ROOT/'ios/App/NativeWorldRenderer.swift';text=renderer.read_text()
    methods='\n'.join(function(text,marker) for marker in [
        '    private func retireWorldCellRequests()', '    private func synchronizeWorldCellIntents()',
        '    private func load(name:String)'])
    assert 'retireWorldCellRequests()' in function(text,'    private func refreshWorldSharpSource()')
    nearby=function(text,'    func loadNearby()')
    assert nearby.index('synchronizeWorldCellIntents()')<nearby.index('for name in far')
    assert 'retireUnretainedCollisionLoads()' in nearby
    paths=[ROOT/'ios/App'/f'{n}.swift' for n in ['ServerAddress','WorldBinary','NativeWorldCellLoader']]
    fixture=Path(__file__).with_suffix('.swift');harness=out/'Gate.swift'
    harness.write_text(fixture.read_text().replace('// ACTUAL_RENDERER_METHODS',methods))
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*paths,renderer,fixture,Path(__file__)]}
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Authored WRL2 and PNG, actual parser/Metal buffer and texture readback, deterministic bounded transfer/worker scheduling and literal renderer admission; no normal UI, hardware or retail acceptance')
    try:
        command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone',
                 '-module-cache-path',str(out/'modules'),*map(str,paths),str(harness),
                 '-framework','MetalKit','-framework','ImageIO','-framework','Security','-o',str(out/'gate')]
        with (out/'compile.log').open('x') as log:
            compiled=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        if compiled.returncode:
            report.update(status='COMPILE_FAIL',exitCode=compiled.returncode)
            print((out/'compile.log').read_text()[-5000:]);compiled.check_returncode()
        run=subprocess.run([str(out/'gate'),*(['--require-gpu'] if args.require_gpu else [])],capture_output=True,text=True,timeout=180)
        (out/'runtime.log').write_text(run.stdout+run.stderr)
        report.update(status=('SKIP_GPU' if run.stdout.startswith('SKIP') else 'PASS') if run.returncode==0 else 'FAIL',exitCode=run.returncode,output=run.stdout+run.stderr)
        print(run.stdout+run.stderr);run.check_returncode()
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items())
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
        print(json.dumps({k:report.get(k) for k in ['status','exitCode','sourcesHeld']}),str(out))
    assert report['sourcesHeld']
if __name__=='__main__':main()
