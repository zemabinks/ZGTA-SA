#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Human shot markers, head/shell/flash presentation and retained gameplay gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/network/smoke_native_human_shots.py'],
    ['python3','tests/resources/smoke_native_weapon_flashes.py'],
    ['python3','tests/core/smoke_core_169.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core170 selected source gates; live original-world effects, passenger gun controllers, struck reactions, muzzle point lights, actual audio output and retail parity remain separate')
