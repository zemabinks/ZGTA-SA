#!/usr/bin/env python3
"""Run the core regression gate; retail-runtime parity is a separate gate.

Owner-provided assets and the native physics toolchain must be prepared first.
Results/logs stay under ignored local-only; no original fixtures are published.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only/native-physics/tests/core-gameplay-gate'


def hashes():
    paths = [*sorted((ROOT / 'ios/App').glob('*.swift')),
             ROOT / 'weapon_inventory.js', ROOT / 'selfhost_backend.js', ROOT / 'local_projectiles.js']
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def main():
    if sys.platform != 'darwin':
        raise SystemExit('This gate requires the macOS Swift/Metal development host. Server tests also run independently with Node.')
    OUT.mkdir(parents=True, exist_ok=True)
    before = hashes()
    cases = [(p.removesuffix('.py'), ['python3', p]) for p in [
        'smoke_native_heading_transitions.py', 'smoke_native_task_transitions.py',
        'smoke_native_shot_delivery.py',
        'smoke_native_climb.py', 'smoke_native_climb_runtime.py',
        'smoke_native_ammo_reconciliation.py', 'smoke_native_inventory_wire.py',
        'smoke_native_camera_visibility.py',
        'smoke_native_controls.py', 'smoke_native_horn.py', 'smoke_native_wire.py',
        'smoke_native_foot_locomotion.py', 'smoke_native_foot_animation.py',
        'smoke_native_gun_animation.py', 'smoke_native_swim_animation.py',
        'smoke_native_swim_sprint.py', 'smoke_native_personal_flight.py',
        'smoke_native_flight_animation.py', 'smoke_native_camera.py',
        'smoke_native_remote_foot.py', 'smoke_native_rider_playback.py',
        'smoke_native_weapon_effects.py',
    ]]
    cases += [(p.removesuffix('.js'), ['node', p]) for p in [
        'smoke_weapon_inventory.js', 'smoke_weapon_cadence.js', 'smoke_weapon_streams.js', 'smoke_native_server.js', 'smoke_inventory_ack.js', 'smoke_jetpack_drop.js',
    ]]
    cases.append(('core_physics_transitions', ['zsh', 'smoke_core_physics_transitions.sh']))

    def run(case):
        name, command = case
        start = time.monotonic()
        with (OUT / (name + '.log')).open('w') as log:
            try:
                result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
                code = result.returncode
            except subprocess.TimeoutExpired:
                log.write('\nFAIL: timed out after600s\n')
                code = 124
        row = {'name': name, 'command': command, 'returncode': code, 'seconds': round(time.monotonic()-start, 2)}
        print(('PASS ' if code == 0 else 'FAIL ') + name, flush=True)
        return row

    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(run, cases))

    # Compile integration boundaries against the actual helpers, not stand-ins.
    for name in ['weapon_state']:
        source = ROOT / f'smoke_native_{name}.swift'
        with tempfile.TemporaryDirectory(prefix='zgta-core-' + name + '-') as temporary:
            binary = str(Path(temporary) / 'verify')
            dependencies = ['NativeInventoryPrediction', 'NativeWeaponState']
            compile_command = ['xcrun', 'swiftc', '-O', '-module-cache-path', str(OUT / 'modules')]
            compile_command += [str(ROOT / 'ios/App' / (n+'.swift')) for n in dependencies]
            compile_command += [str(source), '-o', binary]
            compile_result = run(('compile_' + name, compile_command))
            results.append(compile_result)
            if compile_result['returncode'] == 0:
                results.append(run((name, [binary])))

    unchanged = before == hashes()
    report = {'at': datetime.now(timezone.utc).isoformat(), 'sourceUnchanged': unchanged,
              'evidence': 'native/browser regression and isolated network tests; not original retail-runtime parity',
              'hashes': before, 'tests': results}
    (OUT / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    failed = [r['name'] for r in results if r['returncode'] != 0]
    if not unchanged:
        failed.append('source changed during gate; rerun against a frozen snapshot')
    print(f'{sum(r["returncode"] == 0 for r in results)}/{len(results)} gates passed; sources unchanged={unchanged}')
    if failed:
        print('Failures: ' + ', '.join(failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
