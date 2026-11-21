#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Replay actual renderer path-loading methods with a controlled HTTP boundary.

The graph decoder/store are production code. Transport completion and monotonic
time are explicit test seams; no UI, GPU or live server behavior is simulated.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def method(source,marker):
    start=source.index(marker);brace=source.index('{',start);depth=1;end=brace+1
    while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end].replace('private ','').replace('ProcessInfo.processInfo.systemUptime','TestClock.now')
def renderer_methods(source):
    advance=method(source,'    func advanceAmbientPedestrians(')
    prefix=advance[:advance.index('        var rates:')]+ '\n    }\n'
    return '\n'.join([method(source,'    private func reloadAmbientPedestrianSourceIfChanged('),method(source,'    func configureAmbientPedestrians('),prefix])
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--previous-root',type=Path);args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/population-loading-162'/str(time.time_ns());out.mkdir(parents=True)
    renderer=ROOT/'ios/App/NativeWorldRenderer.swift';harness=Path(__file__).with_suffix('.swift')
    paths=[ROOT/'ios/App'/(n+'.swift')for n in ['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientPedestrians']]
    inputs=[renderer,harness,Path(__file__).resolve(),*paths]
    old=args.previous_root/'ios/App/NativeWorldRenderer.swift'if args.previous_root else None
    if old:inputs.append(old)
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope='Literal renderer resource methods; only HTTP and monotonic clock substituted. Actual graph/store; no normal UI, GPU, live-server or retail claim')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        report['runs']=[]
        for label,source in [('candidate',renderer)]+([('previous',old)]if old else[]):
            generated=out/(label+'.swift')
            generated.write_text(harness.read_text().replace('/* ACTUAL_RENDERER_METHODS */',renderer_methods(source.read_text())))
            command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths),str(generated),'-o',str(out/label)]
            with(out/(label+'-compile.log')).open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
            row=dict(label=label,compileExit=r.returncode);report['runs'].append(row);save()
            assert r.returncode==0,(out/(label+'-compile.log')).read_text()[-7000:]
            r=subprocess.run([str(out/label)],capture_output=True,text=True,timeout=120)
            (out/(label+'-runtime.log')).write_text(r.stdout+r.stderr);row.update(exitCode=r.returncode,output=r.stdout+r.stderr);save()
            if label=='candidate':assert r.returncode==0,r.stdout+r.stderr
            else:assert r.returncode!=0 and 'Repeated same graph announcement cancelled live load'in r.stdout+r.stderr,'Prior source did not fail the retained cancellation witness'
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save();print(json.dumps(report,indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
