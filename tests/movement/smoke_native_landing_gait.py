#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual CLP/animation landing completion, with authored root tracks."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile,time

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--negative-root',type=Path)
p.add_argument('--owned-library',type=Path)
args=p.parse_args()
os.setpriority(os.PRIO_PROCESS,0,15)
out=ROOT/'local-only/research/landing-gait-124';out.mkdir(parents=True,exist_ok=True)
names=['NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation']
paths=[ROOT/'ios/App'/(name+'.swift') for name in names]+[Path(__file__).resolve(),ROOT/'tests/movement/smoke_native_landing_gait.swift']
if args.owned_library:paths.append(args.owned_library.resolve())
if args.negative_root:paths.append(args.negative_root.resolve()/'ios/App/NativeFootAnimation.swift')
before={str(v):hashlib.sha256(v.read_bytes()).hexdigest() for v in paths}
actor=paths[0].read_text()
common=actor[:actor.index('struct NativeSkinVertex')].replace('import Metal','')
common+='\nfinal class NativeSkeletalActor {\n'+actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')]+'}\n'
for source in paths[1:4]:common+='\n'+source.read_text()
harness=(ROOT/'tests/movement/smoke_native_landing_gait.swift').read_text()
rows=[]
with tempfile.TemporaryDirectory(prefix='gate-',dir=out) as directory:
    work=Path(directory)
    for label,source in ([('historical',args.negative_root.resolve()/'ios/App/NativeFootAnimation.swift')] if args.negative_root else [])+[('current',paths[4])]:
        original=source.read_text()
        marker='final class NativeFootAnimation {'
        assert original.count(marker)==1
        observer='\n    var gateHasMovementAction:Bool { action != nil }'
        observed=original.replace(marker,marker+observer)
        assert observed.replace(observer,'')==original
        text=common+'\n'+observed+'\n'+harness
        generated=work/(label+'.swift');generated.write_text(text);binary=work/label
        start=time.monotonic()
        compile=subprocess.run(['xcrun','swiftc','-O','-whole-module-optimization','-num-threads','1','-module-cache-path',str(out/'modules'),str(generated),'-o',str(binary)],capture_output=True,text=True,timeout=240)
        (out/(label+'-compile.log')).write_text(compile.stdout+compile.stderr)
        if compile.returncode:print((compile.stdout+compile.stderr)[-12000:],flush=True)
        assert compile.returncode==0,'Compilation failed; retained separately, not an accepted historical negative'
        command=[str(binary)]+([str(args.owned_library.resolve())] if args.owned_library else [])
        result=subprocess.run(command,capture_output=True,text=True,timeout=90)
        (out/(label+'-runtime.log')).write_text(result.stdout+result.stderr)
        row=dict(label=label,exitCode=result.returncode,seconds=time.monotonic()-start,generatedSourceSHA256=hashlib.sha256(text.encode()).hexdigest(),output=result.stdout)
        rows.append(row)
        (out/'attempts.json').write_text(json.dumps(rows,indent=2)+'\n')
        if label=='historical':assert result.returncode==2 and 'completed landing retained gait phase' in result.stdout,row
        else:assert result.returncode==0 and 'PASS' in result.stdout,row
assert all(hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest for name,digest in before.items())
report=dict(status='PASS',actualNice=os.getpriority(os.PRIO_PROCESS,0),results=rows,sourceHashes=before,sourceUnchanged=True,
            scope='Actual CLP decoder and foot/gun/swim/flight animation code; authored clips. Optional owned clips remain private CPU evidence.',
            readOnlyTaskObserver='One getter exposes actual action lifetime; the animation algorithm is byte-preserved',
            noGPUDeviceOrRetailClaim=True)
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['status','actualNice','results']},indent=2))
