#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Registered vehicle condition publication and retained core regression chain."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['node', 'tests/vehicles/smoke_vehicle_condition_publication.js'],
    ['python3', 'tests/network/smoke_native_vehicle_condition.py'],
    ['python3', 'tests/core/smoke_core_182.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core184 condition publication and selected core gates; cumulative vehicle damage, rendered App and retail accuracy remain separate')
