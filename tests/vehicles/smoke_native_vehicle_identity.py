#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored host checks for actual vehicle append/context/transform/rig paths.

Requires macOS/Xcode; uses no game assets, physics archive, network, GPU or UI.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,time
from tests.vehicles.smoke_native_vehicle_transparency import block
ROOT=Path(__file__).resolve().parents[2]

def main():
    out=ROOT/'local-only/research/vehicle-identity-111'/str(time.time_ns());out.mkdir(parents=True)
    renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    network=(ROOT/'ios/App/NativeMultiplayerClient.swift').read_text()
    source=(ROOT/'tests/vehicles/smoke_native_vehicle_identity.swift').read_text()
    names=['NativeVehicleThermalEffects.swift','NativeParticleEffects.swift','NativeVehicleRig.swift','NativeVehiclePaint.swift','NativeVehicleDamage.swift','NativeRemoteBikeAnimation.swift','NativeRemoteSuspension.swift']
    names += ['NativeAmbientPedestrianProtocol.swift', 'NativeAmbientPedestrianPaths.swift', 'NativeAmbientTrafficProtocol.swift', 'NativeAmbientTrafficRoads.swift', 'NativeAmbientTraffic.swift', 'NativeAmbientTrafficMotion.swift', 'NativeAmbientTrafficPresentation.swift', 'NativeAmbientTrafficScene.swift']
    files=[ROOT/'ios/App'/x for x in names]+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'ios/App/NativeMultiplayerClient.swift',ROOT/'tests/vehicles/smoke_native_vehicle_identity.swift',Path(__file__)]
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
    source=source.replace('// ACTUAL_PACKET_STRUCTS','\n'.join(block(network,x)for x in ['struct NativeVehicleSeatSession {','struct RemotePlayer {','struct RemoteVehicle {']))
    markers=['    private struct ActorPoseOverride {','    private struct OwnVehicleDrawSnapshot {','    private struct ParkedVehicleDrawSnapshot {','    private struct VehicleDrawContext {',
        '    private static func remoteAppearanceIsDriver(','    private static func remoteAppearanceIsFoot(','    private static func remoteDriverRenderKey(',
        '    private func actorName(','    func vehicleModelOrigin(',
        '    private func ownVehicleDrawContext(','    private func remoteVehicleDrawContext(','    private func parkedVehicleDrawContext(',
        '    private func carriageVehicleDrawContext(','    private static func vehicleDrawTransform(','    private static func legacyVehicleWheel(',
        '    private func emitVehicleThermalEffects(', '    private func vehicleRigFrame(','    private static func translation(','    private static func rotationX(','    private static func rotationY(','    private static func rotationZ(']
    source=source.replace('// ACTUAL_RENDER_CONTEXT','\n'.join(block(renderer,x)for x in markers))
    modelLine=next(x.strip()for x in renderer.splitlines()if 'var modelInstances: [('in x)
    source=source.replace('// ACTUAL_MODEL_INSTANCES','private '+modelLine)
    for token,marker in [('OWN','let context=ownVehicleDrawContext('),('REMOTE','let context=remoteVehicleDrawContext('),('PARKED','let context=parkedVehicleDrawContext('),('CARRIAGE','let context=carriageVehicleDrawContext(')]:
        a=renderer.index(marker,renderer.index('    private func drawActors('));b=renderer.index('\n',renderer.index('modelInstances.append(',a))
        source=source.replace('// ACTUAL_'+token+'_APPEND',renderer[a:b])
    a=renderer.index('            let modelAngle = ',renderer.index('    private func drawActors('))
    b=renderer.index('\n            if let exact=queued?.transform',a)
    source=source.replace('// ACTUAL_INSTANCE_TRANSFORM',renderer[a:b])
    source=source.replace('// ACTUAL_PED_APPEND','private '+block(renderer,'        func appendPed(').strip())
    a=renderer.index('            let queued = occurrence.map',renderer.index('    private func drawActors('))
    b=renderer.index('\n            let mesh = ',a)
    source=source.replace('// ACTUAL_PED_TAKE',renderer[a:b])
    a=renderer.index('            let locomotion = ',renderer.index('    private func drawActors('))
    b=renderer.index('\n            let wire = ',a)
    source=source.replace('// ACTUAL_FALLBACK_LOCOMOTION',renderer[a:b])
    assert '// ACTUAL_'not in source
    for obsolete in ['vehicleAppearanceCodes','parkedTransforms','carriageTransforms','carriageIdentifiers','private func parkedVehicle(name:','let player=remotePlayers.first{Self.remoteAppearanceIsDriver']:
        assert obsolete not in renderer,obsolete
    assert 'transform=Self.vehicleDrawTransform(transform,context:vehicleContext)'in renderer
    assert 'Self.legacyVehicleWheel(index:index,front:wheel.contains("f_dummy"),context:vehicleContext,'in renderer
    assert 'let speed=vehicleContext?.own?.speed ?? 0'in renderer
    assert 'let drivenVehicleIDs = Set(remotePlayers.compactMap(\\.vehicleID))'in renderer
    assert 'for source in remoteVehicles where (isPassenger || source.id != currentVehicleID) && !drivenVehicleIDs.contains(source.id)'in renderer
    assert 'encodeTransparentVehicles(transparentVehicleDraws,encoder:encoder)'in renderer
    assert 'identity:"own",ownFoot:true)'in renderer
    paths=[]
    for name in names:p=out/name;p.write_bytes((ROOT/'ios/App'/name).read_bytes());paths.append(p)
    mainfile=out/'main.swift';mainfile.write_text(source)
    with(out/'compile.log').open('w')as log:
        subprocess.run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths),str(mainfile),'-o',str(out/'verify')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=600)
    result=subprocess.run([str(out/'verify')],capture_output=True,text=True,timeout=30)
    (out/'runtime.log').write_text(result.stdout+result.stderr)
    result.check_returncode()
    report=json.loads(result.stdout)
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    report.update(sourceHashes=hashes,sourceUnchanged=True,originalDataUsed=False,
        runtimeGPUOrUIUsed=False,networkOrPhysicsEngineUsed=False)
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
