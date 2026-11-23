#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core205 launch clearance and inventory-owned reload progress."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['node','tests/server/smoke_reload_notices.js'],cwd=ROOT,check=True)
if '--with-physics' in sys.argv[1:]:
    subprocess.run([sys.executable,'tests/movement/smoke_native_jump_clearance.py'],cwd=ROOT,check=True)
subprocess.run([sys.executable,'tests/core/smoke_core_204.py',*sys.argv[1:]],cwd=ROOT,check=True)
