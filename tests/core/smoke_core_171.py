#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Remote authoritative hit reactions and retained shot/gameplay gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/movement/smoke_native_remote_struck.py'],
    ['python3','tests/core/smoke_core_170.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core171 selected source gates; local ordinary hit resolution, seated gun controllers, muzzle point lights, actual audio output and retail parity remain separate')
