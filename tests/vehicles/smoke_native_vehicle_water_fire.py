#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Real driven/parked water-fire ownership; authored data and real Rapier.

Requires the prebuilt host physics archive. An explicit historical root verifies
the two preceding-source failures separately. Production owners are copied
unchanged; conditional compilation selects only the authored test entrypoint.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import runpy
import signal
import subprocess
import time

ROOT=Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-root',type=Path)
    parser.add_argument('--historical-only',action='store_true')
    parser.add_argument('--library',type=Path,default=ROOT/'local-only/native-physics'/('macos-'+platform.machine()))
    args=parser.parse_args()
    assert not args.historical_only or args.historical_root
    os.setpriority(os.PRIO_PROCESS,0,15)
    library=args.library.resolve();archive=library/'libzgtasa_native_physics.a'
    assert archive.is_file(),'Build native-physics for this Mac first'
    names=runpy.run_path(str(ROOT/'tests/vehicles/smoke_native_parked_phase.py'))['NAMES']
    changed={'NativeVehicleBuoyancy','NativeVehicleDamage','NativeVehicleDamageController','NativeGroundVehicle','NativeUnattendedVehicle'}
    variants=[('historical',args.historical_root.resolve())]if args.historical_root else[]
    if not args.historical_only:variants.append(('current',ROOT))
    paths=[ROOT/'ios/App'/(n+'.swift')for n in names]+[Path(__file__).resolve(),Path(__file__).with_suffix('.swift'),ROOT/'tests/vehicles/smoke_native_parked_phase.py',ROOT/'native-physics/source_stamp.py',archive,library/'source-stamp.json']
    if args.historical_root:paths += [args.historical_root.resolve()/'ios/App'/(n+'.swift')for n in changed]
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    frozen={str(p):sha(p)for p in paths}
    out=ROOT/'local-only/research/vehicle-water-fire-test'/str(time.time_ns());out.mkdir(parents=True)
    report=dict(status='RUNNING',startedAt=time.time(),sourceHashes=frozen,results=[],oneHeavyJob=True,actualNice=os.getpriority(os.PRIO_PROCESS,0),scope='Complete actual driven/parked/damage/force/Rapier owners; invented car, streaming floor and water providers. Real force steps, condition/repair/emergence at15/30/60/120Hz, and distinct boat/seaplane floating flags. Read-only clock introspection. No original resources, engine-fire rendering, full vehicle-family, browser, App, hardware or retail timing claim.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    def execute(command,budget):
        p=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
        report['activeOwnedProcessGroup']=p.pid;save()
        def stop():
            if p.poll()is None:
                os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(timeout=15)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
        try:
            try:stdout,stderr=p.communicate(timeout=budget);code=p.returncode
            except subprocess.TimeoutExpired:stop();stdout,stderr=p.communicate();code=124
            return subprocess.CompletedProcess(command,code,stdout,stderr)
        except BaseException:stop();raise
        finally:report['activeOwnedProcessGroup']=None;save()
    save()
    try:
        checked=execute(['python3','native-physics/source_stamp.py','check',str(library)],60)
        (out/'archive-stamp.log').write_text(checked.stdout+checked.stderr);assert checked.returncode==0,checked.stderr
        for label,source_root in variants:
            work=out/label;work.mkdir();sources=[]
            for name in names:
                source=(source_root if name in changed else ROOT)/'ios/App'/(name+'.swift')
                target=work/(name+'.swift');target.write_bytes(source.read_bytes());sources.append(str(target))
            gate=work/'Gate.swift';gate.write_bytes(Path(__file__).with_suffix('.swift').read_bytes())
            command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*(['-D','HISTORICAL']if label=='historical'else[]),'-I',str(ROOT/'native-physics/include'),*sources,str(gate),'-L',str(library),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'gate')]
            row=dict(label=label,startedAt=time.time(),command=command,runtimeCases=[]);report['results'].append(row);save()
            built=execute(command,600);(work/'compile.log').write_text(built.stdout+built.stderr);row['compileExit']=built.returncode;save();assert built.returncode==0,built.stderr[-3000:]
            cases=[('parked',['parked']),('driven',['driven'])]if label=='historical'else[('all',[])]
            for name,options in cases:
                ran=execute([str(work/'gate'),*options],120);text=ran.stdout+ran.stderr;(work/(name+'-runtime.log')).write_text(text);row['runtimeCases'].append(dict(case=name,exitCode=ran.returncode,output=text));save()
                if label=='historical':assert ran.returncode==42 and 'submerged '+name+' automobile kept advancing fire clock'in text,text
                else:assert ran.returncode==0 and 'PASS'in text,text
            row['seconds']=time.time()-row['startedAt'];save()
        assert all(sha(Path(n))==h for n,h in frozen.items())
        report['status']='EXPECTED_HISTORICAL_FAILURES_ONLY'if args.historical_only else'PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(completedAt=time.time(),inputsHeld=all(sha(Path(n))==h for n,h in frozen.items()));save()
        print(json.dumps(dict(status=report['status'],inputsHeld=report['inputsHeld'],results=[{k:r[k]for k in ['label','compileExit','runtimeCases','seconds']if k in r}for r in report['results']],output=str(out)),indent=2))

if __name__=='__main__':main()
