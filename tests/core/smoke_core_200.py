#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Vehicle fire contact and retained core gameplay regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','tests/combat/smoke_native_vehicle_fire_contact.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_199.py',*sys.argv[1:]],cwd=ROOT,check=True)
print('PASS Core200 selected source chain; rendered contact and multiplayer require separate application evidence')
