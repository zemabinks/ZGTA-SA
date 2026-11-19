#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual native solver/force owners with authored geometry and renderer input."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from tests.vehicles.smoke_native_parked_phase import NAMES as VEHICLE_NAMES
from tests.resources.smoke_native_actor_selection import extract

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-motor',type=Path)
    args=parser.parse_args()
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/legacy-gravity-144'/str(time.time_ns());out.mkdir(parents=True)
    names=VEHICLE_NAMES+['NativeCharacterMotor','NativeCharacterController','NativeRapierCharacterQueries',
                         'NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPGameCamera']
    library=ROOT/('local-only/native-physics/macos-'+platform.machine())/'libzgtasa_native_physics.a'
    subprocess.run(['python3',str(ROOT/'native-physics/source_stamp.py'),'check',str(library.parent)],check=True)
    paths=[ROOT/'ios/App'/(name+'.swift') for name in names]+[ROOT/'ios/App/NativeWorldRenderer.swift',Path(__file__),Path(__file__).with_suffix('.swift'),library,ROOT/'native-physics/include/ZGTARapier.h',ROOT/'native-physics/src/lib.rs']
    if args.historical_motor:paths.append(args.historical_motor.resolve())
    captured={p:p.read_bytes() for p in paths}
    renderer=captured[ROOT/'ios/App/NativeWorldRenderer.swift'].decode()
    harness=captured[Path(__file__).with_suffix('.swift')].decode().replace('// ACTUAL_RECEIVE_LEGACY_GAMEPLAY',extract(renderer,'    func receiveLegacyGameplay('))
    harness=harness.replace('// ACTUAL_FALLBACK_BRANCH',extract(renderer,'else if !driving && (verticalSpeed != 0 || (legacyGravity ?? 0)<0)'))
    results=[]
    for label,motor in [('current',None)]+([('historical',args.historical_motor.resolve())] if args.historical_motor else []):
        work=out/label;work.mkdir();sources=[];interface_only=False
        for name in names:
            source=captured[motor] if motor and name=='NativeCharacterMotor' else captured[ROOT/'ios/App'/(name+'.swift')]
            if motor and name=='NativeCharacterMotor':
                text=source.decode();marker='final class NativeCharacterMotor {'
                assert text.count(marker)==1 and 'gravityAcceleration' not in text
                observer='\n    var gravityAcceleration:Double=20 // Inert API compatibility; historical force body is unchanged.'
                modified=text.replace(marker,marker+observer,1);assert modified.replace(observer,'')==text
                source=modified.encode();interface_only=True
            target=work/(name+'.swift');target.write_bytes(source);sources.append(str(target))
        gate=work/'Gate.swift';gate.write_text(harness)
        command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone',
                 '-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-physics/include'),*sources,str(gate),
                 '-L',str(library.parent),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
        start=time.monotonic()
        with (work/'compile.log').open('w') as log:
            build=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        if build.returncode:print((work/'compile.log').read_text()[-6000:]);build.check_returncode()
        result=subprocess.run([str(work/'verify')],capture_output=True,text=True,timeout=90)
        (work/'runtime.log').write_text(result.stdout+result.stderr)
        expected=result.returncode==0 and 'PASS ' in result.stdout if label=='current' else result.returncode==2 and 'Normalized gravity units' in result.stdout
        row=dict(label=label,exitCode=result.returncode,output=result.stdout,seconds=time.monotonic()-start,command=command,
                 historicalInertField=interface_only,expectationMet=expected)
        results.append(row);(out/'attempts.json').write_text(json.dumps(results,indent=2)+'\n');print(result.stdout,flush=True)
        if not expected:raise RuntimeError('Unexpected '+label+' result; retained logs')
    assert all(p.read_bytes()==data for p,data in captured.items())
    report=dict(status='PASS',sourceUnchanged=True,sourceHashes={str(p):hashlib.sha256(data).hexdigest() for p,data in captured.items()},
                results=results,originalDataUsed=False,actualCBridgeAndRapier=True,
                scope='Actual world, character/coordinator, driven/promoted car/bike, and literal renderer command method. Authored geometry; unrelated follow-camera is an explicit boundary. Retail, live server, special-task tuning, full inverted contacts and physical-device acceptance remain separate.')
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    (out.parent/'physics-latest.json').write_text(json.dumps(dict(report,work=str(out)),indent=2)+'\n')
    print(json.dumps(dict(status='PASS',work=str(out))))

if __name__=='__main__':main()
