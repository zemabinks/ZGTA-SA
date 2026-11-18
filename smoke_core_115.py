#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run asset-free actor, draw, passenger-camera and boarding-clock gates."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent
if not shutil.which('xcrun'):
    raise SystemExit('These native foundation checks require macOS and Xcode Swift.')
base = root / 'local-only/research'
base.mkdir(parents=True, exist_ok=True)
out = Path(tempfile.mkdtemp(prefix='core115-', dir=base))
commands = [
    ['python3', 'smoke_native_actor_selection.py', '--out', str(out / 'selection')],
    ['python3', 'smoke_native_draw_occurrences.py', '--output', str(out / 'occurrences')],
    ['python3', 'smoke_native_passenger_camera.py', '--out', str(out / 'passenger-camera')],
    ['python3', 'smoke_native_rider_clock.py', '--out', str(out / 'boarding')],
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
