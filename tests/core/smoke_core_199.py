#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Vehicle thermal presentation and retained core gameplay regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','tests/vehicles/smoke_native_vehicle_thermal.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/vehicles/smoke_native_vehicle_identity.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_198.py',*sys.argv[1:]],cwd=ROOT,check=True)
print('PASS Core199 selected source chain; GPU, full browser/server and original retail parity require separate evidence')
