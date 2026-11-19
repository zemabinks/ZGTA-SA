#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run portable native source regressions; SDK and gameplay acceptance are separate."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse
import json
import platform
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--with-transport', action='store_true',
                    help='Also run the full lifecycle gate using the prebuilt native host transport.')
args = parser.parse_args()
if not shutil.which('xcrun'):
    raise SystemExit('These native source checks require macOS and Xcode Swift.')
base = root / 'local-only/research'
base.mkdir(parents=True, exist_ok=True)
out = Path(tempfile.mkdtemp(prefix='core116-', dir=base))
commands = [
    ['python3', 'tests/core/smoke_core_115.py'],
    ['python3', 'tests/vehicles/smoke_native_rider_timed.py', '--out', str(out / 'rider')],
    ['python3', 'tests/network/smoke_native_connection_owners.py'],
    ['python3', 'tests/network/smoke_samp_spawn_info.py', '--out', str(out / 'spawn-info')],
]
if args.with_transport:
    library = root / ('local-only/native-samp/macos-' + platform.machine()) / 'libzgtasa_samp.a'
    if not library.is_file():
        raise SystemExit('Build the host transport first: python3 build_samp_transport.py --platform host')
    commands.append(['python3', 'tests/network/smoke_samp_lifecycle.py'])
results = []
for command in commands:
    started = time.monotonic()
    print('Running ' + command[1], flush=True)
    result = subprocess.run(command, cwd=root)
    results.append({'command': command, 'exitCode': result.returncode,
                    'seconds': time.monotonic() - started})
    (out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    result.check_returncode()
print('PASS: Core116 portable native source regressions; retail parity unverified', flush=True)
