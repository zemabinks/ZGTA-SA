#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run independently authored placement and mission persistence regressions."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--server-only', action='store_true', help='Run the Node server regressions only.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
commands = [['node', 'tests/network/smoke_selfhost_position_resume.js'],
            ['node', 'tests/server/smoke_selfhost_tp_units.js'],
            ['node', 'tests/server/smoke_selfhost_mission_persistence.js']]
if not args.server_only:
    commands += [['python3', 'tests/network/smoke_native_placement.py'],
                 ['python3', 'tests/network/smoke_native_placement_wire.py']]
for command in commands:
    print('Running ' + command[1], flush=True)
    subprocess.run(command, cwd=root, check=True)
print('PASS: Core114 source regressions', flush=True)
