#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Opt-in grouped-shot authority and retained native gameplay regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['node','tests/combat/smoke_ordinary_shot_groups.js'],
    ['python3','tests/network/smoke_native_shot_groups.py'],
    ['python3','tests/combat/smoke_native_scoped_targets.py'],
    ['python3','tests/combat/smoke_native_scoped_coverage.py'],
    ['python3','tests/ui/smoke_native_weapon_icons.py'],
    ['python3','tests/core/smoke_core_172.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core173 selected source/socket regressions; full App/vehicle-damage/retail acceptance remains separate')
