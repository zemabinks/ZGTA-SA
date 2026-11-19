#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored native camera policy/lifecycle and passive-writer regressions.

No original resources, server, UI or device are used. The actual Renderer query
methods and real native body owners are compiled from immutable source copies.
The accepted host physics archive is read, never rebuilt or modified here.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import uuid
from tests.movement.smoke_native_climb_runtime import function

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/camera-policy-109'
NAMES=['SwiftRapierWorld','NativeWorldRay','NativeGroundVehicle','NativeOtherVehicles',
       'NativeUnattendedVehicle','NativeVehicleDamage','NativeVehicleDamageController',
       'NativeVehicleDynamics','NativeVehicleForces','NativeBikeDynamics','NativeFlightDynamics',
       'NativeVehicleBuoyancy','NativeTrainDynamics','NativeRenderWareCollision',
       'NativeRenderWareCollisionWorld','ServerAddress','NativeGameInput','NativeGameCamera',
       'NativePassiveCameraTrace']


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library',type=Path,default=ROOT/'local-only/native-physics'/('macos-'+platform.machine()))
    parser.add_argument('--sensitivity',action='store_true',help='Also prove the query tests fail when the new exclusion is removed from the extracted candidate.')
    args=parser.parse_args();OUT.mkdir(parents=True,exist_ok=True)
    subprocess.run(['python3',str(ROOT/'native-physics/source_stamp.py'),'check',str(args.library)],check=True)
    paths=[ROOT/'ios/App'/(n+'.swift') for n in NAMES]
    paths += [ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'tests/ui/smoke_native_camera_policy.swift',Path(__file__)]
    before={str(p.relative_to(ROOT)):p.read_bytes() for p in paths}
    renderer=before['ios/App/NativeWorldRenderer.swift'].decode()
    methods='\n\n'.join(function(renderer,m) for m in ['private func cameraRay(','private func worldRay('])
    work=OUT/'snapshot';work.mkdir(exist_ok=True)
    sources=[]
    for name in NAMES:
        file=work/(name+'.swift');file.write_bytes(before['ios/App/'+name+'.swift']);sources.append(str(file))
    harness=before['tests/ui/smoke_native_camera_policy.swift'].decode()
    carrier=work/'main.swift';carrier.write_text(harness.replace('// ACTUAL_RENDERER_QUERY_METHODS',methods))
    archive=args.library/'libzgtasa_native_physics.a'
    archive_hash=hashlib.sha256(archive.read_bytes()).hexdigest()
    run_outputs={}
    def compile_and_run(label,source):
        carrier.write_text(source)
        binary=work/label
        command=['xcrun','swiftc','-whole-module-optimization','-Onone','-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),
                 *sources,str(carrier),'-L',str(args.library),'-lzgtasa_native_physics','-framework','Security',
                 '-framework','CoreFoundation','-o',str(binary)]
        (OUT/(label+'-command.json')).write_text(json.dumps(command,indent=2)+'\n')
        with (OUT/(label+'-compile.log')).open('w') as log:
            result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,text=True)
        if result.returncode:print((OUT/(label+'-compile.log')).read_text());result.check_returncode()
        run_output=OUT/(label+'-run-'+uuid.uuid4().hex)
        run_outputs[label]=run_output
        result=subprocess.run([str(binary),str(run_output)],capture_output=True,text=True)
        (OUT/(label+'-run.log')).write_text(result.stdout+result.stderr)
        return result
    result=compile_and_run('candidate',harness.replace('// ACTUAL_RENDERER_QUERY_METHODS',methods))
    if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
    report=json.loads((run_outputs['candidate']/'report.json').read_text())
    if args.sensitivity:
        marker='let dynamicOthers=originalVehiclePolicy ? self.groundVehicle?.cameraExcludedOtherColliders ?? []:[]'
        assert marker in methods,'Actual production exclusion marker changed'
        negative=methods.replace(marker,'let dynamicOthers=Set<UInt64>()')
        result=compile_and_run('without-policy',harness.replace('// ACTUAL_RENDERER_QUERY_METHODS',negative))
        assert (result.returncode!=0 and 'promoted other must not obstruct the driven camera' in result.stdout+result.stderr), \
            'Historical-policy-equivalent negative did not fail at the intended query assertion'
        report['sensitivity']='PASS: removing the scoped exclusion fails the actual native driven-camera query'
    assert all((ROOT/p).read_bytes()==data for p,data in before.items()),'Source changed during immutable gate'
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==archive_hash,'Host archive changed'
    report.update(sourceUnchanged=True,sourceHashes={p:hashlib.sha256(data).hexdigest() for p,data in before.items()},
                  library=str(archive),librarySHA256=archive_hash,sourceStampVerified=True,
                  limits=['Authored synthetic metadata and actual native physics/owner/query methods; no original game data',
                          'Tagged-other actor membership is an explicit policy fixture; no native remote-ped registration exists',
                          'No rendered UI/GPU/retail runtime or physical-controller/device acceptance'])
    (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':main()
