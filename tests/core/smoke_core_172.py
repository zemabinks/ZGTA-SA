#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Local ordinary pellet resolution and retained core gameplay gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/combat/smoke_native_local_shots.py'],
    ['python3','tests/combat/smoke_native_shot_targeting.py'],
    ['python3','tests/ui/smoke_native_original_controller.py'],
    ['python3','tests/network/smoke_native_inventory_bootstrap.py'],
    ['python3','tests/network/smoke_original_world_wire.py'],
    ['python3','tests/core/smoke_core_171.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core172 selected source gates; actual original-mesh hit acceptance, full multi-target server authority and retail parity remain separate')
