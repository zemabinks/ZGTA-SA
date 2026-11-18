#!/usr/bin/env python3
"""Real Renderer task scheduling, animation-library and native motor boundary gate."""
from pathlib import Path
import argparse
import hashlib
import platform
import subprocess
import tempfile
from smoke_native_climb_runtime import function

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record-baseline', action='store_true')
    args = parser.parse_args()
    renderer = (ROOT / 'ios/App/NativeWorldRenderer.swift').read_text()
    start = renderer.index('        if !driving, let character {\n            lastFootVelocity =')
    publish = renderer[start:renderer.index('\n        if let characterOutput', start)]
    start = renderer.index('motion: { [self] step,state,intended in')
    boundary = renderer[renderer.index('\n', start):renderer.index('                    if let held=climbingMotion', start)]
    methods = '\n'.join(function(renderer, marker) for marker in
                        ['private func combatEligibility(', 'private func swimmingMotion(', 'private func personalFlightMotion(',
                         'private var personalFlightAnimationInput:', 'func cancelGameplayInput(', 'private func cancelFootAimForTask('])
    skeletal = (ROOT / 'ios/App/NativeSkeletalActor.swift').read_text()
    source = skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal', '')
    source += '\nfinal class NativeSkeletalActor {\n' + skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')] + '}\n'
    names = ['NativeCombatEligibility', 'NativeGunAnimation', 'NativeSwimAnimation', 'NativeFlightAnimation', 'NativeFootAnimation',
             'NativePersonalFlightController', 'NativeFootLocomotion', 'NativeHeadingContinuity',
             'NativeSprintController', 'NativeSwimController', 'NativeMelee']
    for name in names:
        source += '\n' + (ROOT / 'ios/App' / (name + '.swift')).read_text()
    harness = (ROOT / 'smoke_native_fixed_velocity.swift').read_text().split('@main enum Gate')[0]
    source += harness.replace('// ACTUAL_PUBLISH', publish).replace(
        '// ACTUAL_MOTION_BOUNDARY', boundary).replace('// ACTUAL_HANDOFFS', methods)
    source += (ROOT / 'smoke_native_task_handoffs.swift').read_text()
    output = ROOT / 'local-only/research/task-handoffs'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'runtime-source.swift').write_text(source)
    (output / 'renderer-methods.sha256').write_text(hashlib.sha256((publish + boundary + methods).encode()).hexdigest() + '\n')
    with tempfile.TemporaryDirectory(prefix='tasks-', dir=output) as directory:
        work = Path(directory)
        (work / 'main.swift').write_text(source)
        sources = [ROOT / 'ios/App' / (name + '.swift') for name in
                   ['SwiftRapierWorld', 'NativeCharacterMotor', 'NativeRapierCharacterQueries',
                    'NativeCharacterController', 'NativeGameInput']]
        # Baseline has no availability API; this is a test-local observation of
        # its actual published velocity, not a substitute implementation.
        if args.record_baseline and 'var currentVelocity:' not in sources[3].read_text():
            with (work / 'main.swift').open('a') as file:
                file.write('\nextension NativeCharacterController { var currentVelocity:SIMD3<Double> { stepVelocity }; var movementAvailable:Bool { true } }\n')
        subprocess.run(['swiftc', '-parse-as-library', '-whole-module-optimization', '-Onone', '-num-threads', '1', '-module-cache-path',
                        '/private/tmp/zgtasa-core-swift-modules', '-I', str(ROOT / 'native-physics/include'),
                        *map(str, sources), str(work / 'main.swift'), '-L',
                        str(ROOT / f'local-only/native-physics/macos-{platform.machine()}'),
                        '-lzgtasa_native_physics', '-framework', 'Security', '-framework', 'CoreFoundation',
                        '-o', str(work / 'verify')], check=True, timeout=900)
        subprocess.run([str(work / 'verify'), str(ROOT), 'baseline' if args.record_baseline else 'verify'], check=True)


if __name__ == '__main__':
    main()
