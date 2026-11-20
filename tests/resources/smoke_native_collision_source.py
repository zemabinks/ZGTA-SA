#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Literal collision-source publication and actual native physical-cell retirement."""
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
    parser.add_argument('--historical-root', type=Path)
    parser.add_argument('--library', type=Path, default=ROOT / ('local-only/native-physics/macos-' + platform.machine()))
    args = parser.parse_args()
    source = (args.historical_root or ROOT).resolve()
    out = ROOT / 'local-only/research/collision-source-153' / str(time.time_ns())
    out.mkdir(parents=True)
    library = args.library.resolve() / 'libzgtasa_native_physics.a'
    subprocess.run(['python3', str(ROOT / 'native-physics/source_stamp.py'), 'check', str(library.parent)], check=True)
    paths = [source / 'ios/App' / (n + '.swift') for n in NAMES]
    renderer = source / 'ios/App/NativeWorldRenderer.swift'
    fixture = Path(__file__).with_suffix('.swift')
    frozen = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*paths, renderer, fixture, Path(__file__), library]}
    text = renderer.read_text()
    marker = '    private func synchronizeCollisionResourceSource()'
    helper = function(text, marker) if marker in text else 'func synchronizeCollisionResourceSource() {}'
    # Only the historical interface adapter is empty. Its actual old loader,
    # parser, ground-cell owner and physics engine remain unchanged.
    methods = helper + '\n' + function(text, '    private func loadCollision(name:String)')
    harness = out / 'Gate.swift'
    harness.write_text(fixture.read_text().replace('// ACTUAL_RENDERER_METHODS', methods))
    command = ['xcrun', 'swiftc', '-j', '1', '-whole-module-optimization', '-num-threads', '1', '-Onone',
               '-module-cache-path', str(out / 'modules'), '-I', str(ROOT / 'native-physics/include'),
               *map(str, paths), str(harness), '-L', str(library.parent), '-lzgtasa_native_physics',
               '-framework', 'Security', '-framework', 'CoreFoundation', '-o', str(out / 'collision-source')]
    with (out / 'compile.log').open('x') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    if result.returncode:
        print((out / 'compile.log').read_text()[-5000:]); result.check_returncode()
    result = subprocess.run([str(out / 'collision-source')], capture_output=True, text=True, timeout=90)
    (out / 'runtime.log').write_text(result.stdout + result.stderr)
    report = dict(status='PASS' if result.returncode == 0 else 'FAIL', exitCode=result.returncode,
                  sourceHashes=frozen, sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p, h in frozen.items()),
                  historical=bool(args.historical_root), output=result.stdout + result.stderr,
                  scope='Literal renderer methods; deterministic authored transport/binding seam; actual SCL2 parser, ground-cell owner, Rapier collider removal and raycast; no HTTP, UI, device or retail acceptance')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), **report), indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'exitCode', 'sourcesHeld', 'historical']}), str(out))
    print((result.stdout + result.stderr)[:2000]); result.check_returncode(); assert report['sourcesHeld']


if __name__ == '__main__':
    main()
