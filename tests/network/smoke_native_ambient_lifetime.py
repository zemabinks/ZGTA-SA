#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Reproduce same-ID NPC cache reuse with literal typed store and renderer keys."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--previous-root',type=Path,help='Optional previous independent source tree; must fail the same regression')
    args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/ambient-lifetime-161'/str(time.time_ns());out.mkdir(parents=True)
    report=dict(status='RUNNING',results=[],scope=__doc__)
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    try:
        for label,root,expected in [('candidate',ROOT,0)]+([('previous',args.previous_root.resolve(),1)]if args.previous_root else[]):
            directory=out/label;directory.mkdir()
            paths=[root/'ios/App'/(name+'.swift')for name in ['NativeAmbientPedestrianProtocol','NativeAmbientPedestrianPaths','NativeAmbientPedestrians','NativeWorldRenderer']]
            inputs=[*paths,Path(__file__).resolve(),Path(__file__).with_suffix('.swift')]
            frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
            renderer=paths[3].read_text()
            animation=re.search(r'let identity=("[^"\n]+"),animator:NativeAmbientPedestrianAnimation',renderer).group(1)
            ground=re.search(r'let identity=("[^"\n]+"),point=frame.position',renderer).group(1)
            carrier=directory/'Keys.swift';carrier.write_text('import Foundation\nfunc animationKey(_ npc:NativeAmbientPedestrians.Frame,name:String)->String{return '+animation+'}\nfunc groundKey(_ frame:NativeAmbientPedestrians.Frame)->String{return '+ground+'}\n')
            if label=='candidate':
                # Compile the actual ground-frame projection, rather than an
                # exact argument substring that rejects added context fields.
                begin=renderer.index('return .init(id:frame.id,skin:frame.skin,seed:frame.seed,flags:frame.flags,position:SIMD3(point.x,point.y,z),')
                cursor=renderer.index('(',begin);depth=1;cursor+=1
                while depth:
                    if renderer[cursor]=='(':depth+=1
                    elif renderer[cursor]==')':depth-=1
                    cursor+=1
                with carrier.open('a')as file:
                    file.write('func projectGround(_ frame:NativeAmbientPedestrians.Frame,z:Double)->NativeAmbientPedestrians.Frame{let point=frame.position;'+renderer[begin:cursor]+'}\n')
            row=dict(name=label,sourceHashes=frozen);report['results'].append(row);save()
            command=['xcrun','swiftc','-parse-as-library','-Onone','-whole-module-optimization','-j','1','-num-threads','1','-module-cache-path',str(directory/'modules'),*map(str,paths[:3]),str(carrier),str(Path(__file__).with_suffix('.swift')),'-o',str(directory/'gate')]
            if label=='candidate':command[2:2]=['-D','CHECK_GROUND_CONTEXT']
            with(directory/'compile.log').open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
            row['compileExit']=r.returncode;assert r.returncode==0,(directory/'compile.log').read_text()[-6000:]
            r=subprocess.run([str(directory/'gate')],capture_output=True,text=True,timeout=60)
            (directory/'runtime.log').write_text(r.stdout+r.stderr);row.update(exitCode=r.returncode,output=r.stdout+r.stderr,sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items()))
            assert row['sourcesHeld'] and r.returncode==expected,r.stdout+r.stderr
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:save();print(json.dumps(report,indent=2))
if __name__=='__main__':main()
