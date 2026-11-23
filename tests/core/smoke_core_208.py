#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core208 persistent equipment ownership at the climb-to-foot boundary."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
if '--with-physics' in sys.argv[1:]:
    subprocess.run([sys.executable,'tests/movement/smoke_native_climb_equipment.py'],cwd=ROOT,check=True)
subprocess.run([sys.executable,'tests/core/smoke_core_207.py',*sys.argv[1:]],cwd=ROOT,check=True)
