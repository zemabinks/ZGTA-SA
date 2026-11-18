#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run independently authored placement and mission persistence regressions."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--server-only', action='store_true', help='Run the Node server regressions only.')
args = parser.parse_args()
root = Path(__file__).resolve().parent
commands = [['node', 'smoke_selfhost_position_resume.js'],
            ['node', 'smoke_selfhost_tp_units.js'],
            ['node', 'smoke_selfhost_mission_persistence.js']]
if not args.server_only:
    commands += [['python3', 'smoke_native_placement.py'],
                 ['python3', 'smoke_native_placement_wire.py']]
for command in commands:
    print('Running ' + command[1], flush=True)
    subprocess.run(command, cwd=root, check=True)
print('PASS: Core114 source regressions', flush=True)
