#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Bounded city collision preparation and the existing selected gameplay gates."""
from pathlib import Path
import os
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:]
if '--with-physics' in args:
    subprocess.run(['python3','tests/resources/smoke_native_collision_streaming.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_153.py',*args],cwd=ROOT,check=True)
print('PASS Core154 selected source gates; normal installed gameplay, hardware and original-retail acceptance remain separate')
