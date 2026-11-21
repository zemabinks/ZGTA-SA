#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Astride fall ownership, existing-NPC handoff and retained core regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/vehicles/smoke_native_rider_fall_metadata.py'],
    ['python3','tests/vehicles/smoke_native_traffic_rider_fall.py'],
    ['python3','tests/vehicles/smoke_native_traffic_rider_ownership.py'],
    ['python3','tests/core/smoke_core_167.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core168 selected source gates; full application, passenger retirement, traffic AI, physics and retail acceptance remain separate')
