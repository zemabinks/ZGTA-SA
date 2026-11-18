#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual Renderer passenger camera adapter and native camera on invented poses."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

ROOT=Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def block(text, signature):
    """Extract a literal balanced declaration; no algorithm rewriting."""
    start=text.index(signature)
    opening=text.index('{',start)
    depth=1
    for end in range(opening+1,len(text)):
        if text[end]=='{':depth+=1
        elif text[end]=='}':depth-=1
        if not depth:return text[start:end+1]
    raise ValueError('Unclosed declaration: '+signature)


def visible(text):
    return text.replace('private struct ','struct ').replace('private static func ','static func ').replace('private func ','func ')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-source',type=Path,help='Historical Renderer source: its unchanged adapter must fail the same assertions.')
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/research/passenger-camera-115')
    args=parser.parse_args()
    out=args.out.resolve()
    if ROOT/'local-only' not in out.parents:raise SystemExit('Output must be in this checkout local-only.')
    out.mkdir(parents=True,exist_ok=True)
    paths={name:ROOT/'ios/App'/name for name in ['NativeWorldRenderer.swift','NativeGroundVehicle.swift','SwiftRapierWorld.swift',
        'NativeMultiplayerClient.swift','NativeRiderAnimation.swift','NativeGameCamera.swift']}
    paths['test.py']=Path(__file__).resolve();paths['test.swift']=ROOT/'smoke_native_passenger_camera.swift'
    if args.negative_source:paths['negative']=args.negative_source.resolve()
    before={str(p):sha(p) for p in paths.values()}
    source={name:path.read_text() for name,path in paths.items()}
    renderer=source['NativeWorldRenderer.swift'];ground=source['NativeGroundVehicle.swift']
    wire=source['NativeMultiplayerClient.swift'];rapier=source['SwiftRapierWorld.swift']
    replacements={
        'ACTUAL_AXIS_CONVERSION':'\n'.join(block(rapier,'    static func '+name+'(') for name in ['gtaToRapier','rapierToGTA']),
        'ACTUAL_GROUND_COORDINATES':'\n'.join([block(ground,'    struct CameraFrame {')]+[
            block(ground,'    static func '+name+'(') for name in ['rotation','modelOffset','transform']]),
        'ACTUAL_WIRE_TYPES':'\n'.join(block(wire,'struct '+name+' {') for name in ['NativeVehicleSeatSession','RemotePlayer','RemoteVehicle']),
        'ACTUAL_CAMERA_DEFINITION':visible(block(renderer,'    private struct CameraVehicleDefinition:')),
        'ACTUAL_SHARED_FRAME_TYPE':visible(block(renderer,'    private struct SharedVehicleFrame {')),
        'ACTUAL_RENDERER_MATRICES':'\n'.join(visible(block(renderer,'    private static func '+name+'(')) for name in ['translation','rotationX','rotationY','rotationZ']),
        'ACTUAL_SHARED_FRAME_METHOD':visible(block(renderer,'    private func sharedVehicleFrame(')),
    }
    results=[]
    stamp=str(time.time_ns());work=out/('snapshot-'+stamp);work.mkdir()
    for name in ['NativeGameCamera.swift','NativeRiderAnimation.swift']:(work/name).write_text(source[name])
    def run(label,adapter_source):
        harness=source['test.swift']
        for marker,value in dict(replacements,ACTUAL_CAMERA_ADAPTER=visible(block(adapter_source,'    private func nativeCameraVehicle('))).items():
            token='// '+marker
            assert harness.count(token)==1,marker
            harness=harness.replace(token,value)
        assert '// ACTUAL_' not in harness
        test=work/(label+'.swift');test.write_text(harness)
        binary=work/label
        command=['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),str(work/'NativeGameCamera.swift'),
                 str(work/'NativeRiderAnimation.swift'),str(test),'-o',str(binary)]
        started=time.monotonic()
        compiled=subprocess.run(command,capture_output=True,text=True,timeout=180)
        (out/(label+'-compile.log')).write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:raise RuntimeError(label+' compile failed; see retained log')
        ran=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
        (out/(label+'-runtime.log')).write_text(ran.stdout+ran.stderr)
        data=json.loads(ran.stdout)
        result=dict(label=label,compileExit=0,runExit=ran.returncode,seconds=time.monotonic()-started,result=data)
        results.append(result);return result
    if args.negative_source:
        old=run('historical-negative',source['negative'])
        assert old['runExit']>0 and old['result']['status']=='FAIL' and old['result']['failure']=='passenger eye lost selected seat',old
    current=run('current',renderer)
    assert current['runExit']==0 and current['result']['status']=='PASS',current
    after={p:sha(Path(p)) for p in before}
    assert before==after,'Scoped source changed during gate'
    report=dict(status='PASS',sourceUnchanged=True,sourceHashes=before,results=results,snapshot=str(work),
        boundary='Literal actual Renderer camera adapter/shared frame/coordinate functions, actual native camera and wire types. Invented metadata and explicit physics storage/prediction boundaries; unused HTTP fails immediately.',
        noRenderedPhysicsOrRetailAcceptance=True)
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':main()
