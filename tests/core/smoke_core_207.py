#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core207 cause-specific climb release handoff to the fixed foot motor."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
if '--with-physics' in sys.argv[1:]:
    for name in ['tests/movement/smoke_native_swim_retirement.py','tests/combat/smoke_native_aim_ownership.py','tests/movement/smoke_native_fixed_velocity.py','tests/movement/smoke_native_climb_release.py','tests/movement/smoke_native_fall_damage.py','tests/movement/smoke_native_effort_recovery.py']:
        subprocess.run([sys.executable,name],cwd=ROOT,check=True)
subprocess.run([sys.executable,'tests/core/smoke_core_206.py',*sys.argv[1:]],cwd=ROOT,check=True)
