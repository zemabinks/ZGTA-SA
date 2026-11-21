#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Native traffic geometry/prediction/history, optional owner-local reference."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owned-reference',type=Path);parser.add_argument('--owned-graph',type=Path);parser.add_argument('--owned-crc')
    args=parser.parse_args()
    assert bool(args.owned_reference)==bool(args.owned_graph)==bool(args.owned_crc),'Supply all owner-local reference arguments together'
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-motion-native-162'/str(time.time_ns());out.mkdir(parents=True)
    names=['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientTrafficProtocol','NativeAmbientTrafficRoads','NativeAmbientTraffic','NativeAmbientTrafficMotion']
    sources=[ROOT/'ios/App'/(name+'.swift')for name in names]
    sources += [Path(__file__).with_suffix('.swift'),Path(__file__).with_name('smoke_native_traffic_motion_reference.swift')]
    inputs=[*sources,Path(__file__).resolve()]
    if args.owned_reference:
        for p in [args.owned_reference,args.owned_graph]:assert p.is_file() and p.stat().st_size<=16*1048576;inputs.append(p.resolve())
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Horizontal traffic geometry/prediction/history; no terrain/body fit, playable traffic, AI, server, collision, device or retail claim')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,sources),'-o',str(out/'gate')]
        with(out/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        report['compileExit']=r.returncode;assert r.returncode==0,(out/'compile.log').read_text()[-7000:]
        runtime=[str(out/'gate')]+([str(args.owned_reference.resolve()),str(args.owned_graph.resolve()),args.owned_crc]if args.owned_reference else[])
        r=subprocess.run(runtime,capture_output=True,text=True,timeout=120)
        (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
        assert r.returncode==0,r.stdout+r.stderr;report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save();print(json.dumps(report,indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
