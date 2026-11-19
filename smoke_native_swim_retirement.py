#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual water-exit coordination, with authored queries, input and CLP clips."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, tempfile, time
from smoke_native_climb_runtime import function

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--negative-root',type=Path)
args=parser.parse_args()
os.setpriority(os.PRIO_PROCESS,0,15)
out=root/'local-only/research/swim-retirement-136';out.mkdir(parents=True,exist_ok=True)
names=['NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation',
       'NativeFootAnimation','NativePersonalFlightController','NativeSprintController',
       'NativeHeadingContinuity','NativeFootLocomotion','NativeSwimController']
paths=[root/'ios/App'/(name+'.swift') for name in names]
paths += [root/'ios/App/NativeWorldRenderer.swift',root/'ios/App/NativeCharacterController.swift',
          root/'ios/App/SwiftRapierWorld.swift',root/'smoke_native_landing_gait.swift',
          root/'smoke_native_swim_retirement.swift',Path(__file__).resolve()]
if args.negative_root:paths.append(args.negative_root/'ios/App/NativeWorldRenderer.swift')
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
actor=paths[0].read_text()
common=actor[:actor.index('struct NativeSkinVertex')].replace('import Metal','')
common+='\nfinal class NativeSkeletalActor {\n'+actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')]+'}\n'
for source in paths[1:len(names)]:common+='\n'+source.read_text()
controller=(root/'ios/App/NativeCharacterController.swift').read_text()
common+='\nstruct NativeCharacterMotor {struct Press{}}\nfinal class NativeCharacterController {\n'
common+='\n'.join(function(controller,marker) for marker in ['struct Output {','struct Motion {'])
common+='\nvar supportAfloat=false\n}\n'
world=(root/'ios/App/SwiftRapierWorld.swift').read_text()
common+='\nenum SwiftRapierWorld {\n'+'\n'.join(function(world,marker) for marker in ['static func gtaToRapier(','static func rapierToGTA('])+'\n}\n'
common+='\n'+(root/'smoke_native_landing_gait.swift').read_text().split('let kinds=')[0]
template=(root/'smoke_native_swim_retirement.swift').read_text()
rows=[]
with tempfile.TemporaryDirectory(prefix='gate-',dir=out) as directory:
    work=Path(directory)
    for label,source in ([('historical',args.negative_root/'ios/App/NativeWorldRenderer.swift')] if args.negative_root else [])+[('current',root/'ios/App/NativeWorldRenderer.swift')]:
        method=function(source.read_text(),'private func swimmingMotion(')
        text=common+'\n'+template.replace('// ACTUAL_SWIMMING_MOTION',method)
        generated=work/(label+'.swift');generated.write_text(text);binary=work/label
        started=time.monotonic()
        compile=subprocess.run(['xcrun','swiftc','-O','-whole-module-optimization','-num-threads','1',
            '-module-cache-path',str(out/'modules'),str(generated),'-o',str(binary)],capture_output=True,text=True,timeout=240)
        (out/(label+'-compile.log')).write_text(compile.stdout+compile.stderr)
        if compile.returncode:print((compile.stdout+compile.stderr)[-10000:])
        assert compile.returncode==0,'Compilation failure is not a historical negative'
        run=subprocess.run([str(binary)],capture_output=True,text=True,timeout=60)
        (out/(label+'-runtime.log')).write_text(run.stdout+run.stderr)
        rows.append({'label':label,'code':run.returncode,'seconds':time.monotonic()-started,
                     'generatedSHA256':hashlib.sha256(text.encode()).hexdigest(),'output':run.stdout})
        (out/'attempts.json').write_text(json.dumps(rows,indent=2)+'\n')
        if label=='historical':assert run.returncode==2 and 'retired swim wrote facing before foot control' in run.stdout,rows[-1]
        else:assert run.returncode==0 and 'PASS swim retirement' in run.stdout,rows[-1]
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==sha for p,sha in hashes.items())
report={'passed':True,'actualNice':os.getpriority(os.PRIO_PROCESS,0),'sourceHashes':hashes,'sourceUnchanged':True,
        'results':rows,'scope':'Actual extracted renderer/controller/locomotion/sprint/CLP code; authored water/character-output boundaries. No physics scene, GPU, retail or hardware acceptance.'}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':True,'actualNice':report['actualNice'],'results':rows},indent=2))
