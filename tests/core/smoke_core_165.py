#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Traffic transition/session ownership, passenger camera and retained gates."""
from pathlib import Path
import os, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
commands = [
    ['python3', 'tests/network/smoke_native_traffic_transition.py'],
    ['python3', 'tests/network/smoke_native_traffic_session.py'],
]
if '--with-physics' in sys.argv:
    commands.append(['python3', 'tests/ui/smoke_native_camera_roles.py'])
commands.append(['python3', 'tests/core/smoke_core_164.py', *sys.argv[1:]])
for command in commands:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core165 selected source gates; SDK, rendered traffic interactions and original-game acceptance remain separate')
