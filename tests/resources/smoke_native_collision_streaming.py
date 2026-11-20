#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Bounded asynchronous collision preparation and actual native physical-cell installation."""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
NAMES = ['ServerAddress', 'WorldCollision', 'NativeWorldRay', 'SwiftRapierWorld',
         'NativeGroundVehicle', 'NativeOtherVehicles', 'NativeUnattendedVehicle',
         'NativeVehicleDamage', 'NativeVehicleDamageController', 'NativeVehicleDynamics',
         'NativeVehicleForces', 'NativeBikeDynamics', 'NativeFlightDynamics',
         'NativeVehicleBuoyancy', 'NativeTrainDynamics', 'NativeVehicleCoupling']


def function(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private ', '')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, default=ROOT / ('local-only/native-physics/macos-' + platform.machine()))
    args = parser.parse_args()
    source = ROOT
    out = ROOT / 'local-only/research/collision-streaming-154' / str(time.time_ns())
    out.mkdir(parents=True)
    library = args.library.resolve() / 'libzgtasa_native_physics.a'
    subprocess.run(['python3', str(ROOT / 'native-physics/source_stamp.py'), 'check', str(library.parent)], check=True)
    paths = [source / 'ios/App' / (n + '.swift') for n in NAMES + ['NativeCollisionCellLoader']]
    fixture = Path(__file__).with_suffix('.swift')
    paths.append(fixture)
    frozen = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*paths, Path(__file__), library]}
    command = ['xcrun', 'swiftc', '-j', '1', '-whole-module-optimization', '-num-threads', '1', '-Onone',
               '-module-cache-path', str(out / 'modules'), '-I', str(ROOT / 'native-physics/include'),
               *map(str, paths), '-L', str(library.parent), '-lzgtasa_native_physics',
               '-framework', 'Security', '-framework', 'CoreFoundation', '-o', str(out / 'collision-source')]
    with (out / 'compile.log').open('x') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    if result.returncode:
        print((out / 'compile.log').read_text()[-5000:]); result.check_returncode()
    result = subprocess.run([str(out / 'collision-source')], capture_output=True, text=True, timeout=120)
    (out / 'runtime.log').write_text(result.stdout + result.stderr)
    report = dict(status='PASS' if result.returncode == 0 else 'FAIL', exitCode=result.returncode,
                  sourceHashes=frozen, sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p, h in frozen.items()),
                  output=result.stdout + result.stderr,
                  scope='Actual serial loader, bounded transport boundary, SCL2 spatial/physical preparation and real ground/Rapier ownership; authored bytes and deterministic worker/transport scheduling; no HTTP, UI, hardware or retail acceptance')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), **report), indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'exitCode', 'sourcesHeld']}), str(out))
    print((result.stdout + result.stderr)[:2000]); result.check_returncode(); assert report['sourcesHeld']


if __name__ == '__main__':
    main()
