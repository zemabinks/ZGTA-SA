#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run asset-free actor, draw, passenger-camera and boarding-clock gates."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[2]
if not shutil.which('xcrun'):
    raise SystemExit('These native foundation checks require macOS and Xcode Swift.')
base = root / 'local-only/research'
base.mkdir(parents=True, exist_ok=True)
out = Path(tempfile.mkdtemp(prefix='core115-', dir=base))
commands = [
    ['python3', 'tests/resources/smoke_native_actor_selection.py', '--out', str(out / 'selection')],
    ['python3', 'tests/resources/smoke_native_draw_occurrences.py', '--output', str(out / 'occurrences')],
    ['python3', 'tests/vehicles/smoke_native_passenger_camera.py', '--out', str(out / 'passenger-camera')],
    ['python3', 'tests/vehicles/smoke_native_rider_clock.py', '--out', str(out / 'boarding')],
]
results = []
for command in commands:
    started = time.monotonic()
    print('Running ' + command[1], flush=True)
    result = subprocess.run(command, cwd=root)
    results.append({'command': command, 'exitCode': result.returncode,
                    'seconds': time.monotonic() - started})
    (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    result.check_returncode()
print('PASS: Core115 native foundation source regressions', flush=True)
