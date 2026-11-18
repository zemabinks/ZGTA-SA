#!/usr/bin/env python3
"""Exercise the actual motor/camera and Renderer call across display cadences.

This checks native fixed-step ownership, not original retail camera equality.
Owner-provided camera metadata and the local native physics library are needed.
"""
from pathlib import Path
import hashlib
import json
import platform
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def main():
    renderer = (ROOT / 'ios/App/NativeWorldRenderer.swift').read_text()
    start = renderer.index('gameCameraFrame=gameCamera.followFoot(')
    end = start + len('gameCameraFrame=gameCamera.followFoot(')
    depth = 1
    while depth:
        depth += (renderer[end] == '(') - (renderer[end] == ')')
        end += 1
    call = renderer[start:end]
    line_start = renderer.rfind('\n', 0, start) + 1
    prefix = renderer[renderer.rfind('\n', 0, line_start - 1) + 1:line_start]
    if 'let cameraAiming=' in prefix:
        call = prefix + call
    def property_(marker):
        first = renderer.index(marker)
        opening = renderer.index('{', first)
        depth = 1
        last = opening + 1
        while depth:
            depth += (renderer[last] == '{') - (renderer[last] == '}')
            last += 1
        return renderer[first:last].replace('private ', '')
    aim = '\n'.join(property_(marker) for marker in
                    ['var supportsFootWeaponAim:', 'var canMaintainFootAim:'])
    marker = '    private var currentFootVelocity:'
    velocity = renderer[renderer.index(marker):renderer.index('\n', renderer.index(marker))].replace('private ', '')
    source = (ROOT / 'smoke_native_camera_motion.swift').read_text().replace('// ACTUAL_RENDERER_CAMERA_CALL', call)
    source = source.replace('// ACTUAL_RENDERER_CURRENT_VELOCITY', velocity)
    source = source.replace('// ACTUAL_RENDERER_AIM_PREDICATES', aim)
    out = ROOT / 'local-only/research/camera-motion'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'renderer-call.sha256').write_text(hashlib.sha256(call.encode()).hexdigest() + '\n')
    with tempfile.TemporaryDirectory(prefix='camera-motion-', dir=out) as directory:
        work = Path(directory)
        swift = work / 'verify.swift'
        swift.write_text(source)
        names = ['ServerAddress', 'NativeGameInput', 'NativeGameCamera', 'SwiftRapierWorld',
                 'NativeCharacterMotor', 'NativeRapierCharacterQueries', 'NativeCharacterController']
        subprocess.run(['nice', '-n', '15', 'xcrun', 'swiftc', '-O', '-whole-module-optimization',
                        '-num-threads', '1', '-module-cache-path', str(out / 'modules'),
                        '-I', str(ROOT / 'native-physics/include'),
                        *[str(ROOT / 'ios/App' / (name + '.swift')) for name in names], str(swift),
                        '-L', str(ROOT / f'local-only/native-physics/macos-{platform.machine()}'),
                        '-lzgtasa_native_physics', '-framework', 'Security', '-framework', 'CoreFoundation',
                        '-o', str(work / 'verify')], check=True)
        result = subprocess.run([str(work / 'verify'), str(ROOT / 'local-only/site/game/native/camera.json')],
                                check=True, capture_output=True, text=True)
        report = json.loads(result.stdout)
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f"PASS camera motor ownership: {report['checks']} checks at15/30/60/120/144Hz and jitter; "
              'actual Renderer call, committed Rapier travel, repeated poses/substeps, stop/start, reset and invalid hints')


if __name__ == '__main__':
    main()
