#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Partial vehicle-condition ownership and retained core gameplay regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
if '--with-physics' in sys.argv[1:]:
    subprocess.run(['python3', 'tests/vehicles/smoke_native_parked_health.py'], cwd=ROOT, check=True)
else:
    print('Parked partial-condition runtime gate requires --with-physics and the prebuilt host archive', flush=True)
subprocess.run(['python3', 'tests/core/smoke_core_195.py', *sys.argv[1:]], cwd=ROOT, check=True)
print('PASS Core196 selected source chain; parked runtime coverage requires --with-physics; rendered and retail parity remain separate')
