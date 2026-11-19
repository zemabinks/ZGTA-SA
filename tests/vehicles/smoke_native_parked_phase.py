#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual Rapier parked phase handoffs using authored vehicle definitions.

Requires a local native-physics macOS archive. No original game assets, server,
GPU, browser or application state is used.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,os,platform,subprocess,time

ROOT=Path(__file__).resolve().parents[2]
NAMES=['SwiftRapierWorld','NativeGroundVehicle','NativeOtherVehicles','NativeUnattendedVehicle',
       'NativeVehicleDamage','NativeVehicleDamageController','NativeVehicleDynamics','NativeVehicleForces',
       'NativeBikeDynamics','NativeFlightDynamics','NativeVehicleBuoyancy','NativeTrainDynamics','NativeVehicleCoupling']

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--historical-root',type=Path)
    p.add_argument('--prepare-only',action='store_true')
    a=p.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/parked-phase-122'/str(time.time_ns());out.mkdir(parents=True)
    library=ROOT/('local-only/native-physics/macos-'+platform.machine())/'libzgtasa_native_physics.a'
    assert library.is_file(),'Build native-physics for this Mac first'
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    paths=[ROOT/'ios/App'/(n+'.swift') for n in NAMES]+[Path(__file__).resolve(),ROOT/'tests/vehicles/smoke_native_parked_phase.swift',library]
    roots=[('historical',a.historical_root.resolve())] if a.historical_root else []
    roots+=[('current',ROOT)]
    for label,r in roots:
        if label=='historical':paths += [r/'ios/App'/(n+'.swift')for n in ['NativeOtherVehicles','NativeUnattendedVehicle']]
    frozen={str(p):sha(p)for p in paths};results=[]
    for label,r in roots:
        work=out/label;work.mkdir();sources=[]
        for name in NAMES:
            src=r/'ios/App'/(name+'.swift') if name in ['NativeOtherVehicles','NativeUnattendedVehicle'] else ROOT/'ios/App'/(name+'.swift')
            text=src.read_text()
            if label=='historical' and name=='NativeUnattendedVehicle':
                assert 'func restoreWheelSpin(' not in text
                # Interface-only negative bridge; the old state/solver/lifecycle
                # implementations remain unchanged. It deliberately transfers
                # no counters, reproducing the prior admission contract.
                text+='\nextension NativeUnattendedVehicle {func restoreWheelSpin(front:Double,rear:Double){}}\n'
            dest=work/(name+'.swift');dest.write_text(text);sources.append(str(dest))
        main=work/'Gate.swift';main.write_bytes((ROOT/'tests/vehicles/smoke_native_parked_phase.swift').read_bytes());sources.append(str(main))
        exe=work/'verify'
        cmd=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1',
             '-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,
             '-L',str(library.parent),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(exe)]
        row={'label':label,'command':cmd,'prepared':True};results.append(row)
        if a.prepare_only:continue
        start=time.monotonic();built=subprocess.run(cmd,capture_output=True,text=True,timeout=600)
        (work/'compile.log').write_text(built.stdout+built.stderr);built.check_returncode()
        ran=subprocess.run([str(exe),label],capture_output=True,text=True,timeout=90)
        (work/'runtime.log').write_text(ran.stdout+ran.stderr)
        row.update(exitCode=ran.returncode,seconds=time.monotonic()-start,output=ran.stdout)
        if label=='historical':assert ran.returncode==2 and 'demotion lost wheel phase' in ran.stdout,row
        else:assert ran.returncode==0 and 'PASS' in ran.stdout,row
    assert all(sha(Path(p))==h for p,h in frozen.items())
    report={'status':'PREPARED_NOT_COMPILED' if a.prepare_only else 'PASS','sourceUnchanged':True,'sourceHashes':frozen,
            'results':results,'actualNice':os.getpriority(os.PRIO_PROCESS,0),
            'scope':'Actual native solver/world/pool with invented definitions/floor. Presentation handoff, not retail handling or rendered wheel acceptance.'}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'results':[{k:r[k]for k in ['label','exitCode','seconds','output']if k in r}for r in results],'output':str(out)},indent=2))

if __name__=='__main__':main()
