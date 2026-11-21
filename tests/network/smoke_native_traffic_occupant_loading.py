#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual occupant resource lifetime methods with explicit transport/clock seams."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time

ROOT=Path(__file__).resolve().parents[2]
def block(source,needle):
    start=source.index(needle);brace=source.index('{',start);end=brace+1;depth=1
    while depth:depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end].replace('private ','').replace('ProcessInfo.processInfo.systemUptime','TestClock.now')
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--previous-renderer',type=Path);args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-occupant-loading-166'/str(time.time_ns());out.mkdir(parents=True)
    renderer=ROOT/'ios/App/NativeWorldRenderer.swift';fixture=Path(__file__).with_suffix('.swift')
    files=[ROOT/'ios/App/ServerAddress.swift',ROOT/'ios/App/NativeTrafficOccupants.swift']
    inputs=[*files,renderer,fixture,Path(__file__).resolve()]+([args.previous_renderer]if args.previous_renderer else[])
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=hashes,results=[],scope=__doc__)
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        for label,path in ([('previous',args.previous_renderer)]if args.previous_renderer else[])+[('candidate',renderer)]:
            source=path.read_text();methods='\n'.join(block(source,needle)for needle in ['    private func cancelTrafficOccupantLoad()','    private func loadTrafficOccupantsIfNeeded()'])
            code=out/(label+'.swift');code.write_text(fixture.read_text().replace('// ACTUAL_RESOURCE_METHODS',methods));exe=out/label
            command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,files),str(code),'-framework','Security','-o',str(exe)]
            with(out/(label+'-compile.log')).open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
            assert r.returncode==0,(out/(label+'-compile.log')).read_text()[-5000:]
            r=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);output=r.stdout+r.stderr
            (out/(label+'-runtime.log')).write_text(output);report['results'].append(dict(label=label,compileExit=0,exitCode=r.returncode,output=output));save()
            if label=='previous':assert r.returncode!=0 and "Cached-source return retained another source's pending request"in output,output
            else:assert r.returncode==0,output
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items());save();print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'}))
    assert report['sourcesHeld']
if __name__=='__main__':main()
