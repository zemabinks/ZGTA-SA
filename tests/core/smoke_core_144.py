#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Legacy gravity lifetimes/force owners and the complete prior core chain."""
from pathlib import Path
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
arguments=sys.argv[1:]
subprocess.run(['python3','tests/network/test_samp_game_camera.py'],cwd=ROOT,check=True)
if '--with-physics' in arguments:
    subprocess.run(['python3','tests/physics/smoke_native_legacy_gravity.py'],cwd=ROOT,check=True)
if '--with-transport' in arguments:
    subprocess.run(['python3','tests/network/smoke_samp_gameplay.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_143.py',*arguments],cwd=ROOT,check=True)
print('PASS Core144 selected source gates; live sessions, special-task tuning and retail parity remain separate')
