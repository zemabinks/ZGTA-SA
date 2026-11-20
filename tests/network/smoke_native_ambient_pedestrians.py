#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Bounded typed NPC channel and compact graph, with optional private data."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owned-graph',type=Path);parser.add_argument('--owned-crc')
    parser.add_argument('--owned-motion-reference',type=Path)
    args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
    assert bool(args.owned_graph)==bool(args.owned_crc)
    out=ROOT/'local-only/research/ambient-native-158'/str(time.time_ns());out.mkdir(parents=True)
    sources=[ROOT/'ios/App'/f'{n}.swift'for n in ['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientPedestrians']]+[Path(__file__).with_suffix('.swift')]
    assert not args.owned_motion_reference or args.owned_graph
    inputs=[*sources,Path(__file__).resolve()]+([args.owned_graph.resolve()]if args.owned_graph else[])+([args.owned_motion_reference.resolve()]if args.owned_motion_reference else[])
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Actual standalone typed channel/graph implementations with authored byte goldens. Optional original graph data/query acceptance only; no live channel, rendering, NPC AI or damage integration.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),**report),indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
        with(out/'compile.log').open('x')as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        report['compileExit']=result.returncode
        if result.returncode:report['status']='COMPILE_FAIL';save();raise RuntimeError((out/'compile.log').read_text()[-6500:])
        command=[str(out/'gate')]+([str(args.owned_graph.resolve()),args.owned_crc]if args.owned_graph else[])+([str(args.owned_motion_reference.resolve())]if args.owned_motion_reference else[])
        result=subprocess.run(command,capture_output=True,text=True,timeout=90)
        (out/'runtime.log').write_text(result.stdout+result.stderr);report.update(status='PASS'if result.returncode==0 else'FAIL',exitCode=result.returncode,output=result.stdout+result.stderr);save();print(result.stdout+result.stderr,end='');assert result.returncode==0
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save();print(json.dumps({k:v for k,v in report.items()if k not in ['sourceHashes','output']}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
