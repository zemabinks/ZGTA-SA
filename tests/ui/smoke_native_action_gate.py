#!/usr/bin/env python3
"""Execute actual touch handlers and controller eligibility with inert UI boundaries."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def block(source, marker):
    start = source.index(marker)
    cursor = source.index('{', start)
    depth, end = 1, cursor + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expect-old', action='store_true',
                        help='Record the historical unfixed six-handler/controller leak.')
    parser.add_argument('--expect-radial-old', action='store_true',
                        help='Record the remaining historical diagonal-neutral mismatch.')
    parser.add_argument('--expect-right-old', action='store_true',
                        help='Record the historical per-axis camera-delivery mismatch.')
    args = parser.parse_args()
    source_path = ROOT / 'ios/App/NativeGameViewController.swift'
    source = source_path.read_text()
    inputs = [source_path, ROOT / 'ios/App/NativeGameInput.swift',
              ROOT / 'tests/ui/smoke_native_action_gate.py', ROOT / 'tests/ui/smoke_native_action_gate.swift']
    before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    names = ['toggleRun', 'jump', 'toggleAim', 'toggleGear', 'toggleCrouch', 'nextRadioStation']
    methods = [block(source, '@objc private func ' + name + '(') for name in names]
    policies = [block(source, 'private var ' + name + ':')
                for name in ['canNavigateMenus', 'acceptsHeldInput']]
    match = re.search(r'controllerGate\.accepts\(active: (.*?),\s*(?:axes|left):', source)
    assert match, 'Actual controller eligibility boundary not found'
    eligibility = match.group(1)
    start = source.index('controllerGate.accepts(')
    cursor = source.index('(', start)
    depth, end = 1, cursor + 1
    while depth:
        depth += (source[end] == '(') - (source[end] == ')')
        end += 1
    controller_call = source[start:end].replace('controllerGate.accepts', 'gate.accepts', 1)
    start = source.index('            let right = NativeInputMath.stick(')
    end = source.index('            gamepadRunning =', start)
    right_delivery = source[start:end]
    # Only access/ObjC exposure changes; actual expressions and method bodies execute.
    extracted = '\n'.join(policies + methods).replace('@objc ', '').replace('private ', '')
    fixture = (ROOT / 'tests/ui/smoke_native_action_gate.swift').read_text()
    fixture = fixture.replace('/* ACTUAL_HANDLERS */', extracted)
    fixture = fixture.replace('/* ACTUAL_CONTROLLER_ELIGIBILITY */', eligibility)
    fixture = fixture.replace('/* ACTUAL_CONTROLLER_CALL */', controller_call)
    fixture = fixture.replace('/* ACTUAL_RIGHT_DELIVERY */', right_delivery)
    output = ROOT / 'local-only/research/input-gate-112'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='run-', dir=output) as temporary:
        directory = Path(temporary)
        (directory / 'main.swift').write_text(fixture)
        subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(output / 'modules'),
                        str(ROOT / 'ios/App/NativeGameInput.swift'), str(directory / 'main.swift'),
                        '-o', str(directory / 'verify')], check=True, timeout=180)
        mode = ('old' if args.expect_old else 'radial-old' if args.expect_radial_old else
                'right-old' if args.expect_right_old else 'fixed')
        run = subprocess.run([str(directory / 'verify'), mode],
                             check=True, capture_output=True, text=True, timeout=30)
        result = json.loads(run.stdout)
        after = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        assert before == after, 'Test inputs changed during execution'
        result.update(sourceSHA256=hashlib.sha256(source.encode()).hexdigest(),
                      sourceHashes=before, sourceUnchanged=True,
                      actualControllerEligibility=eligibility,
                      scope='Actual handlers/input policies and controller gate; authored inert UI/renderer/radio boundaries. No retail, UIKit, motor, transport or device acceptance.')
        target = output / ('before-result.json' if args.expect_old else
                           'radial-before-result.json' if args.expect_radial_old else
                           'right-before-result.json' if args.expect_right_old else 'result.json')
        assert not ((args.expect_old or args.expect_radial_old or args.expect_right_old) and target.exists()), 'Historical result is immutable'
        target.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))


if __name__ == '__main__':
    main()
