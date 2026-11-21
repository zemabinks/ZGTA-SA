#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Query-time shot owners, exact icon preparation and retained core checks."""
from pathlib import Path
import os
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/combat/smoke_native_shot_owners.py'],
    ['python3', 'tests/resources/test_native_weapon_icons.py'],
    ['node', 'tests/resources/smoke_native_weapon_icon_http.js'],
    ['python3', 'tests/core/smoke_core_173.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core174 selected source checks; App, geometry refresh, hardware and retail acceptance remain separate')
