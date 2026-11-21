#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compact SDRDv1 reader/query gate; owner-local references are optional."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owned-graph',type=Path);parser.add_argument('--owned-crc')
    parser.add_argument('--owned-reference',type=Path)
    args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
    assert bool(args.owned_graph)==bool(args.owned_crc)
    assert not args.owned_reference or args.owned_graph
    out=ROOT/'local-only/research/traffic-roads-162'/str(time.time_ns());out.mkdir(parents=True)
    sources=[ROOT/'ios/App'/(name+'.swift')for name in ['NativeAmbientPedestrianPaths','NativeAmbientTrafficRoads']]+[Path(__file__).with_suffix('.swift')]
    inputs=[*sources,Path(__file__).resolve()]
    for path,limit in [(args.owned_graph,8*1048576),(args.owned_reference,2*1048576)]:
        if path:assert path.is_file() and path.stat().st_size<=limit;inputs.append(path.resolve())
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Literal native compact road parser/query methods with invented graph and optional owner-local archived query observations. No traffic movement, renderer, AI or retail claim.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
        with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        report['compileExit']=r.returncode;assert r.returncode==0,(out/'compile.log').read_text()[-6000:]
        command=[str(out/'gate')]+([str(args.owned_graph.resolve()),args.owned_crc]if args.owned_graph else[])+([str(args.owned_reference.resolve())]if args.owned_reference else[])
        r=subprocess.run(command,capture_output=True,text=True,timeout=120);(out/'runtime.log').write_text(r.stdout+r.stderr)
        report.update(exitCode=r.returncode,output=r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save();print(json.dumps(report,indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
