#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core122 source gates; real physics is optional and game assets stay separate."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,os,subprocess

root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__,add_help=False)
p.add_argument('--with-physics',action='store_true')
args,prior=p.parse_known_args()
os.setpriority(os.PRIO_PROCESS,0,15)
commands=[['python3','tests/core/smoke_core_121.py',*prior],
          ['python3','tests/vehicles/smoke_native_vehicle_presentation.py'],
          ['python3','tests/vehicles/smoke_native_remote_bike_owner.py']]
if args.with_physics:commands.append(['python3','tests/vehicles/smoke_native_parked_phase.py'])
for command in commands:subprocess.run(command,cwd=root,check=True)
print('PASS Core122 selected source gates; rendered/device/retail acceptance remains separate')
