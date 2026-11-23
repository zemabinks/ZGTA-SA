#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core206 entity-relative climb handholds and exact scene lifetime."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
if '--with-physics' in sys.argv[1:]:
    for name in ['tests/movement/smoke_native_climb_carrier.py','tests/vehicles/smoke_native_support_runtime.py']:
        subprocess.run([sys.executable,name],cwd=ROOT,check=True)
subprocess.run([sys.executable,'tests/core/smoke_core_205.py',*sys.argv[1:]],cwd=ROOT,check=True)
