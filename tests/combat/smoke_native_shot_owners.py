#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual shot-owner lifetime, current body, tyre and triangle queries."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, time
ROOT = Path(__file__).resolve().parents[2]

def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private ', '')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='Historical vehicle-query predicate only')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    os.setpriority(os.PRIO_PROCESS, 0, 15)
    out = ROOT / 'local-only/research/shot-owners-175' / str(time.time_ns())
    out.mkdir(parents=True)
    current = ROOT / 'ios/App/NativeWorldRenderer.swift'
    selected = (args.source or current).resolve()
    player = ROOT / 'ios/App/NativeMultiplayerClient.swift'
    fixture = Path(__file__).with_suffix('.swift')
    names=['NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeLocalShotMesh','NativeShotOwners']
    compiled=[ROOT/'ios/App'/(name+'.swift')for name in names]
    paths = [current, selected, player, fixture, Path(__file__).resolve(),*compiled]
    frozen = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    source = current.read_text()
    carrier = fixture.read_text()
    for marker, token in [
        ('    private struct LocalShotOccupantFrame {', '// ACTUAL_OCCUPANT_FRAME'),
        ('    private struct LocalShotVehicleFrame {', '// ACTUAL_VEHICLE_FRAME'),
        ('    private func currentLocalShotOccupant(', '// ACTUAL_OCCUPANT_QUERY'),
        ('    private static func remoteAppearanceIsDriver(', '// ACTUAL_DRIVER_ROLE'),
    ]:
        carrier = carrier.replace(token, block(source, marker))
    for marker,token in [('    private func recordLocalShotPlayerOwners(', '// ACTUAL_PLAYER_ADMISSION'),('    private func recordLocalShotRegisteredOwners(', '// ACTUAL_VEHICLE_ADMISSION'),('    private func localShotVehicleIncarnation(', '// ACTUAL_VEHICLE_INCARNATION'),('    private func localShotOccupantIncarnation(', '// ACTUAL_OCCUPANT_INCARNATION'),('    private func currentLocalShotVehicleBody(', '// ACTUAL_CURRENT_BODY'),('    private func remoteVehicleDrawContext(', '// ACTUAL_REMOTE_CONTEXT'),('    private func parkedVehicleDrawContext(', '// ACTUAL_PARKED_CONTEXT'),('    private func ambientTrafficDrawContext(', '// ACTUAL_TRAFFIC_CONTEXT'),('    private static func vehicleDrawTransform(', '// ACTUAL_BODY_TRANSFORM'),('    private static func remoteDriverRenderKey(', '// ACTUAL_RENDER_KEY'),('    private static func shotMatrix(', '// ACTUAL_SHOT_MATRIX'),('    func predictedVehicle(', '// ACTUAL_PREDICTED_VEHICLE'),('    private func applying(', '// ACTUAL_APPLY_SNAPSHOT'),('    func vehicleModelOrigin(', '// ACTUAL_MODEL_ORIGIN'),('    private static func translation(', '// ACTUAL_TRANSLATION'),('    private static func rotationX(', '// ACTUAL_ROTATION_X'),('    private static func rotationY(', '// ACTUAL_ROTATION_Y'),('    private static func rotationZ(', '// ACTUAL_ROTATION_Z')]:
        carrier=carrier.replace(token,block(source,marker))
    for marker,token in [('    private struct ParkedVehicleDrawSnapshot {','// ACTUAL_PARKED_SNAPSHOT'),('    private struct VehicleDrawContext {','// ACTUAL_DRAW_CONTEXT'),('    private func localVehicleShotHits(','// ACTUAL_VEHICLE_HITS')]:
        carrier=carrier.replace(token,block(source,marker))
    assert 'recordLocalShotPlayerOwners()'in block(source,'    var remotePlayers: [RemotePlayer]')
    assert 'recordLocalShotRegisteredOwners()'in block(source,'    var remoteVehicles: [RemoteVehicle]')
    query=block(source,'    private func currentLocalShotVehicleBody(')
    assert not any(name in query for name in ['vehicleRigFrame(','.pose(','.frames(','.update(','.step(','ProcessInfo','riderMonotonicNow'])
    carrier = carrier.replace('// ACTUAL_VEHICLE_QUERY', block(selected.read_text(), '    private func currentLocalShotVehicleFrames('))
    carrier = carrier.replace('// ACTUAL_PLAYER', block(player.read_text(), 'struct RemotePlayer {'))
    carrier=carrier.replace('// ACTUAL_REMOTE_VEHICLE',block(player.read_text(),'struct RemoteVehicle {'))
    carrier=carrier.replace('// ACTUAL_VEHICLE_SEATS',block(player.read_text(),'struct NativeVehicleSeatSession {'))
    (out / 'Gate.swift').write_text(carrier)
    report = dict(status='PREPARED', startedAt=time.time(), sourceHashes=frozen,
        historicalPredicate=bool(args.source), scope='Literal admission/current-body/context/root/target methods, actual player/registered decoder and complete triangle/ray resolver; authored owner/physical snapshot/traffic/controller inputs. Rig and actor resources are identity tokens. No physics/pose stepping, GPU, App or retail acceptance')
    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), **report), indent=2) + '\n')
    save()
    try:
        if not args.prepare_only:
            with (out / 'compile.log').open('x') as log:
                result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-j', '1', '-whole-module-optimization', '-num-threads', '1', '-Onone', '-module-cache-path', str(out / 'modules'), *map(str,compiled), str(out / 'Gate.swift'), '-o', str(out / 'gate')], stdout=log, stderr=subprocess.STDOUT, timeout=240)
            report['compileExit'] = result.returncode
            save()
            assert result.returncode == 0, (out / 'compile.log').read_text()[-5000:]
            result = subprocess.run([str(out / 'gate')], capture_output=True, text=True, timeout=60)
            report.update(exitCode=result.returncode, output=result.stdout + result.stderr)
            save()
            assert result.returncode == 0, report['output']
            report['status'] = 'PASS'
    except BaseException as error:
        report.update(status='FAIL', error=repr(error))
        raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest() == h for n, h in frozen.items()), completedAt=time.time())
        save()
        print({k: v for k, v in report.items() if k != 'sourceHashes'})

if __name__ == '__main__':
    main()
