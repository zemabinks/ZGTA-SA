#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual thermal policy, rig admission and particle pool; no original data needed.

An optional local --reference accepts the separately produced unchanged browser
callable replay. That generated evidence is never part of the public source.
"""
from pathlib import Path
import argparse,hashlib,json,os,signal,subprocess,time

ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reference',type=Path);parser.add_argument('--adapter-reference',type=Path)
    args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
    names=['NativeVehicleThermalEffects','NativeParticleEffects','NativeVehicleRig','NativeVehiclePaint']
    files=[ROOT/'ios/App'/(n+'.swift')for n in names]+[Path(__file__),Path(__file__).with_suffix('.swift')]
    if args.reference:files.append(args.reference.resolve())
    if args.adapter_reference:
        assert args.reference,'Adapter comparison requires the matching thermal callable reference'
        files.append(args.adapter_reference.resolve())
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    frozen={str(p):sha(p)for p in files}
    out=ROOT/'local-only/research/vehicle-thermal-test'/str(time.time_ns());out.mkdir(parents=True)
    report=dict(status='RUNNING',startedAt=time.time(),sourceHashes=frozen,results=[],actualNice=os.getpriority(os.PRIO_PROCESS,0),oneHeavyJob=True,
        scope='Complete actual thermal policy, rig decoder and particle pool with invented definitions. Optional unchanged browser callable replay is a controlled reference only. Not GPU, real-world browser multiplayer, hardware or retail parity.')
    def save():(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    def run(name,command,budget):
        row=dict(name=name,command=command,startedAt=time.time());report['results'].append(row);save()
        with(out/(name+'.log')).open('x')as log:
            p=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            report['activeOwnedProcessGroup']=p.pid;save()
            try:code=p.wait(timeout=budget)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(timeout=10)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
                code=124
        row.update(exitCode=code,seconds=time.time()-row['startedAt']);report['activeOwnedProcessGroup']=None;save()
        assert code==0,(name,(out/(name+'.log')).read_text()[-3500:])
    try:
        copies=[]
        for source in files[:4]:
            target=out/source.name;target.write_bytes(source.read_bytes());copies.append(str(target))
        gate=out/'Gate.swift';gate.write_bytes(Path(__file__).with_suffix('.swift').read_bytes())
        run('compile',['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*copies,str(gate),'-o',str(out/'gate')],600)
        run('runtime',[str(out/'gate'),*([str(args.reference.resolve())]if args.reference else[]),*([str(args.adapter_reference.resolve())]if args.adapter_reference else[])],120)
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(completedAt=time.time(),inputsHeld=all(sha(Path(p))==h for p,h in frozen.items()));save()
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']))+'\n')
        print(json.dumps({k:report[k]for k in ['status','results','actualNice','inputsHeld']}),flush=True)

if __name__=='__main__':main()
